--[[
GearSwap file locator.

Given a player name and main job, find the most-likely GearSwap data file
that's currently loaded. Tries the common naming conventions used by the
GearSwap community (lower / upper / mixed case), falling back to a
job-only file when no character-specific one exists.

This is a TEXT search — we don't actually ask GearSwap which file it has
loaded (no public API for that). We assume the player follows the
standard `<Character>_<JOB>.lua` convention inside addons/GearSwap/data/.

Returns absolute path string or nil if nothing matches.
]]

local locator = {}

-- Be robust about Windower's addon_path. It can come back with either
-- backslashes or forward slashes depending on platform / version, and the
-- trailing separator is sometimes missing. Normalize, then strip the
-- addon's own folder to land on the addons/ root.
local SEP = package.config:sub(1, 1) or '\\'
local function normalize(p)
    p = tostring(p or '')
    p = p:gsub('/', SEP)
    if p:sub(-1) ~= SEP then p = p .. SEP end
    return p
end

local addon_dir = normalize(windower.addon_path or '')
-- Strip the addon's own folder name + trailing separator to land on the
-- addons/ root. Lua patterns treat both '\' and '/' as literals (no
-- regex-style escape needed) — the earlier double-escape was matching
-- TWO backslashes instead of one, so the strip silently no-op'd and we
-- ended up with "addons/gsui/GearSwap/data/" instead of
-- "addons/GearSwap/data/". This version handles both slash styles.
local addons_root = addon_dir:gsub('[^\\/]+[\\/]$', '')
local GS_DATA_DIR = addons_root .. 'GearSwap' .. SEP .. 'data' .. SEP

local function file_exists(path)
    local f = io.open(path, 'r')
    if f then f:close() return true end
    return false
end

-- Iterate over plausible filename forms in priority order.
-- Most GearSwap setups use either `<Name>_<JOB>.lua` (job-specific) or a
-- single `<Name>.lua` that dispatches internally based on main_job.
local function candidates(player, job)
    local out = {}
    if player and player ~= '' and job and job ~= '' then
        table.insert(out, player .. '_' .. job:upper() .. '.lua')
        table.insert(out, player .. '_' .. job:lower() .. '.lua')
        table.insert(out, player:lower() .. '_' .. job:lower() .. '.lua')
        table.insert(out, player:upper() .. '_' .. job:upper() .. '.lua')
    end
    if player and player ~= '' then
        table.insert(out, player .. '.lua')
        table.insert(out, player:lower() .. '.lua')
    end
    if job and job ~= '' then
        table.insert(out, job:upper() .. '.lua')
        table.insert(out, job:lower() .. '.lua')
    end
    return out
end

-- Recursively walk the GearSwap data dir collecting every .lua file.
-- Returns a list of { path = absolute, filename = leaf, rel = relative-to-data-dir }
-- so callers can both load by absolute path AND display the subfolder
-- structure to the user. Uses Windower's get_dir / dir_exists APIs
-- which are bundled with every Windower install.
--
-- Subfolder layouts are common in the GearSwap community for organizing
-- sets per character / per job (e.g. data/<Character>/<job>.lua or
-- data/jobs/<Character>_<JOB>.lua). The earlier locator only scanned
-- the direct data/ dir which missed those layouts.
local function scan_dir(dir, rel_prefix, into, depth)
    depth = depth or 0
    if depth > 6 then return end                   -- runaway-recursion safety
    if not windower or not windower.get_dir then return end
    local ok, entries = pcall(windower.get_dir, dir)
    if not ok or type(entries) ~= 'table' then return end
    for _, name in ipairs(entries) do
        if name ~= '.' and name ~= '..' then
            local full = dir .. name
            local rel  = (rel_prefix == '') and name or (rel_prefix .. SEP .. name)
            -- A directory check first; ENTRIES may contain folders without
            -- any extension hint, so always probe dir_exists before
            -- treating as a file.
            if windower.dir_exists and windower.dir_exists(full) then
                scan_dir(full .. SEP, rel, into, depth + 1)
            elseif name:sub(-4):lower() == '.lua' then
                into[#into + 1] = { path = full, filename = name, rel = rel }
            end
        end
    end
end

local function full_scan()
    local out = {}
    scan_dir(GS_DATA_DIR, '', out, 0)
    table.sort(out, function(a, b) return a.rel:lower() < b.rel:lower() end)
    return out
end

-- Public: find_active(player, job) -> { path, filename, rel } or nil
--
-- Strategy:
--   1. Fast path: try direct filename candidates in data/ root. This
--      is what the addon has always done; covers the common case
--      without a full directory walk.
--   2. Fallback: scan recursively and look for any .lua whose LEAF
--      filename matches a candidate. Catches users who put their
--      files in subfolders like data/<Character>/<JOB>.lua or
--      data/jobs/<Character>_<JOB>.lua.
function locator.find_active(player, job)
    local cands = candidates(player, job)
    -- Fast path
    for _, fname in ipairs(cands) do
        local p = GS_DATA_DIR .. fname
        if file_exists(p) then
            return { path = p, filename = fname, rel = fname }
        end
    end
    -- Recursive fallback. Build a lowercase set of leaf names we want,
    -- then walk the dir tree once and pick the first matching entry.
    local want = {}
    for _, fname in ipairs(cands) do want[fname:lower()] = true end
    for _, e in ipairs(full_scan()) do
        if want[e.filename:lower()] then
            return e
        end
    end
    return nil
end

-- Public: list_all() -> sorted list of every .lua file under data/,
-- including subfolders. Each entry is { path, filename, rel } where
-- `rel` is the path relative to data/ (handy for showing subfolder
-- groupings in a picker UI).
function locator.list_all()
    return full_scan()
end

function locator.data_dir()
    return GS_DATA_DIR
end

return locator

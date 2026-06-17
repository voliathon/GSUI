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
-- Resolution order (matches GearSwap's own subfolder logic so we pick
-- THE SAME file GearSwap loaded, not just any file with a matching
-- leaf name):
--
--   1. data/<filename>            (root, the historical layout)
--   2. data/<player>/<filename>   (per-character folder, GS preferred)
--   3. data/<player_lowercase>/<filename>
--   4. ANY other folder with a matching leaf name (recursive fallback)
--
-- For each tier we walk every filename candidate (the various
-- <Name>_<JOB>.lua / <Name>.lua / <JOB>.lua casings) before stepping
-- down to the next tier. So we always prefer "in the player's named
-- folder" over "any other folder", which matches user expectation:
-- if data/Kalitzo/MNK.lua AND data/Backups/MNK.lua both exist, we
-- pick Kalitzo's (the one GearSwap actually uses) every time.
function locator.find_active(player, job)
    local cands = candidates(player, job)

    -- Tier 1: data/ root direct lookup
    for _, fname in ipairs(cands) do
        local p = GS_DATA_DIR .. fname
        if file_exists(p) then
            return { path = p, filename = fname, rel = fname }
        end
    end

    -- Tier 2 + 3: player-named folder. Try both the exact player name
    -- casing and the lowercase variant since GearSwap is case-sensitive
    -- on most filesystems but the player may use either.
    local player_folders = {}
    if player and player ~= '' then
        player_folders[#player_folders+1] = player
        if player:lower() ~= player then player_folders[#player_folders+1] = player:lower() end
    end
    for _, folder in ipairs(player_folders) do
        for _, fname in ipairs(cands) do
            local p = GS_DATA_DIR .. folder .. SEP .. fname
            if file_exists(p) then
                return { path = p, filename = fname, rel = folder .. SEP .. fname }
            end
        end
    end

    -- Tier 4: recursive scan, but PREFER results whose path starts
    -- with the player folder. Build a lowercase set of leaf names we
    -- want, then walk; if multiple match, pick the highest-priority
    -- one (player-folder match > shallowest depth > alphabetical).
    local want = {}
    for _, fname in ipairs(cands) do want[fname:lower()] = true end
    local matches = {}
    for _, e in ipairs(full_scan()) do
        if want[e.filename:lower()] then
            matches[#matches+1] = e
        end
    end
    if #matches == 0 then return nil end
    local function score(e)
        local rel_lower = e.rel:lower()
        for _, folder in ipairs(player_folders) do
            if rel_lower:sub(1, #folder + 1) == folder:lower() .. SEP then
                return 0          -- best: in player's folder
            end
        end
        -- Count separators -> depth. Shallower = higher priority
        -- (more likely to be the "main" file vs an archive copy).
        local depth = 1
        for _ in rel_lower:gmatch(SEP) do depth = depth + 1 end
        return depth
    end
    table.sort(matches, function(a, b)
        local sa, sb = score(a), score(b)
        if sa ~= sb then return sa < sb end
        return a.rel:lower() < b.rel:lower()
    end)
    return matches[1]
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

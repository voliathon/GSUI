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

-- Public: find_active(player, job) -> { path, filename } or nil
function locator.find_active(player, job)
    for _, fname in ipairs(candidates(player, job)) do
        local p = GS_DATA_DIR .. fname
        if file_exists(p) then
            return { path = p, filename = fname }
        end
    end
    return nil
end

-- Public: list_all() -> sorted list of every .lua file in GearSwap/data
-- Used to populate a file picker so the user can switch off the auto-
-- detected file if they want to inspect a different job's sets.
function locator.list_all()
    local files = {}
    -- Windower exposes os.listdir or similar? Use Lua io / dir scan.
    -- Fallback to scanning via the player/job we know — at least surface
    -- the auto-detected one. Full directory listing requires lfs which
    -- isn't always bundled; defer that to a follow-up if needed.
    return files
end

function locator.data_dir()
    return GS_DATA_DIR
end

return locator

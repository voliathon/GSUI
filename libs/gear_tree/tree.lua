-- GearTree tree builder
-- Takes the flat assignment list from parser.lua and builds a hierarchical
-- tree. Provides helpers for the UI to walk, flatten (respecting expand state),
-- and produce equip command strings.

local tree = {}

----------------------------------------------------------------------
-- Node structure
----------------------------------------------------------------------
-- A node is a table with:
--   key          string  -- this segment's name (e.g. "WS", "Rudra's Storm")
--   path         table   -- full path from root: {"sets","precast","WS"}
--   children     table   -- ordered list of child nodes
--   child_map    table   -- map from key -> child node, for fast lookup
--   assignment   table?  -- the parser assignment for this node, if any
--   has_gear     bool    -- true if this path has a `sets.X = ...` definition
--   expanded     bool    -- UI state: is this node's children visible
--
-- Equippability: a node is equippable iff has_gear is true. That includes
-- empty tables (sets.precast.JA.Steal = {}), set_combine() results, and
-- references (sets.precast.JA['Sneak Attack'] = sets.buff['Sneak Attack']).
-- Pure container paths (e.g. "precast" — never assigned directly, only has
-- children) are NOT equippable; clicking them just expands/collapses.

local function new_node(key, path)
    return {
        key = key,
        path = path,
        children = {},
        child_map = {},
        assignment = nil,
        has_gear = false,
        expanded = false,
    }
end

----------------------------------------------------------------------
-- Build tree from assignments
----------------------------------------------------------------------

function tree.build(assignments)
    local root = new_node('sets', { 'sets' })

    for _, a in ipairs(assignments) do
        local keys = a.keys
        -- keys[1] is always "sets"; walk from keys[2] downward
        local node = root
        for idx = 2, #keys do
            local k = keys[idx]
            local child = node.child_map[k]
            if not child then
                local path = {}
                for j = 1, idx do path[j] = keys[j] end
                child = new_node(k, path)
                node.children[#node.children + 1] = child
                node.child_map[k] = child
            end
            node = child
        end
        node.assignment = a
        node.has_gear = true
    end

    -- Keep display order tied to the Lua file. Children are appended when
    -- their path is first seen by the parser, which scans top to bottom.

    return root
end

----------------------------------------------------------------------
-- Path → equip command string
----------------------------------------------------------------------
-- Produce a string that Gearswap's `gs equip` handler can parse.
-- Gearswap's parse_set_to_keys handles either dot or bracket notation,
-- so we use dot for identifier-safe keys and bracket for the rest.
-- We use single quotes for bracket keys since Windower's chat tokenizer
-- is friendlier to them than double quotes.

function tree.equip_command(node)
    if not node.has_gear then return nil end
    local s = node.path[1] -- "sets"
    for i = 2, #node.path do
        local k = node.path[i]
        k = tostring(k or '')
        if k == '' then
            return nil, 'Cannot serialize an empty path segment for gs equip.'
        end
        if k:find('[\r\n]') then
            return nil, 'Cannot serialize a path segment containing a newline.'
        end
        if k:match('^[%a_][%w_]*$') then
            s = s .. '.' .. k
        else
            -- Use double-quoted bracket syntax so apostrophes stay intact.
            local escaped = k:gsub('\\', '\\\\'):gsub('"', '\\"')
            s = s .. '["' .. escaped .. '"]'
        end
    end
    return 'gs equip ' .. s
end

-- Just the path string without the "gs equip " prefix; useful for display.
function tree.path_string(node)
    local s = node.path[1]
    for i = 2, #node.path do
        local k = tostring(node.path[i] or '')
        if k:match('^[%a_][%w_]*$') then
            s = s .. '.' .. k
        else
            local escaped = k:gsub('\\', '\\\\'):gsub('"', '\\"')
            s = s .. '["' .. escaped .. '"]'
        end
    end
    return s
end

----------------------------------------------------------------------
-- Flatten for UI rendering
----------------------------------------------------------------------
-- Walk the tree in display order, respecting expand state. Returns an
-- ordered list of {node, depth, is_last_at_depth} suitable for rendering.
--
-- Redundant singleton wrappers are flattened for display only. Example:
--   sets.buff.Doom.Doom
-- renders as a single "Doom" leaf under buff instead of a folder "Doom"
-- containing one child set also named "Doom". The underlying node/path is
-- untouched, so equip commands and source references still target the real
-- GearSwap set.

local function normalize_display_key(value)
    local text = tostring(value or '')
    text = text:lower()
    text = text:gsub("[%s_%-%p]+", "")
    return text
end

local function is_redundant_singleton_wrapper(node)
    if not node or node.has_gear then return false end
    if not node.children or #node.children ~= 1 then return false end

    local child = node.children[1]
    if not child or not child.has_gear then return false end
    if child.children and #child.children > 0 then return false end

    return normalize_display_key(node.key) == normalize_display_key(child.key)
end

function tree.flatten(root)
    local out = {}
    local function walk(node, depth)
        -- Skip root itself; children of root are the top-level entries
        for _, child in ipairs(node.children) do
            if is_redundant_singleton_wrapper(child) then
                -- Display the real gear set at the wrapper's depth. This removes
                -- the visual duplicate without mutating the semantic tree.
                out[#out + 1] = { node = child.children[1], depth = depth }
            else
                out[#out + 1] = { node = child, depth = depth }
                if child.expanded and #child.children > 0 then
                    walk(child, depth + 1)
                end
            end
        end
    end
    walk(root, 0)
    return out
end

----------------------------------------------------------------------
-- Find a node by path (table of keys) — useful for tests and for the
-- "remember which nodes were expanded across reloads" feature.
----------------------------------------------------------------------

function tree.find(root, path)
    local node = root
    for i = 2, #path do
        node = node.child_map[path[i]]
        if not node then return nil end
    end
    return node
end

----------------------------------------------------------------------
-- Expand / collapse helpers
----------------------------------------------------------------------

function tree.expand_all(root)
    local function walk(n)
        n.expanded = true
        for _, c in ipairs(n.children) do walk(c) end
    end
    walk(root)
end

function tree.collapse_all(root)
    local function walk(n)
        n.expanded = false
        for _, c in ipairs(n.children) do walk(c) end
    end
    walk(root)
end

-- Toggle one node. Returns the new expanded state.
function tree.toggle(node)
    node.expanded = not node.expanded
    return node.expanded
end

----------------------------------------------------------------------
-- Gear preview: what slots does this node define directly?
-- Returns a list of {slot, value_source} pairs, sorted by slot.
----------------------------------------------------------------------

local SLOT_ORDER = {
    main = 1, sub = 2, range = 3, ammo = 4,
    head = 5, neck = 6, ear1 = 7, ear2 = 8, left_ear = 7, right_ear = 8, lear = 7, rear = 8,
    body = 9, hands = 10, ring1 = 11, ring2 = 12, left_ring = 11, right_ring = 12, lring = 11, rring = 12,
    back = 13, waist = 14, legs = 15, feet = 16,
}

function tree.gear_preview(node)
    if not node.has_gear or not node.assignment then return {} end
    local rhs = node.assignment.rhs
    local slots = rhs.slots or {}
    local out = {}
    for slot, val in pairs(slots) do
        out[#out + 1] = { slot = slot, value = val }
    end
    table.sort(out, function(a, b)
        local oa = SLOT_ORDER[a.slot] or 99
        local ob = SLOT_ORDER[b.slot] or 99
        if oa == ob then return a.slot < b.slot end
        return oa < ob
    end)
    return out
end

-- Describe the assignment kind for a node, for use in tooltips/preview.
function tree.describe(node)
    if not node.has_gear then return 'container' end
    local rhs = node.assignment.rhs
    if rhs.kind == 'table' then
        local n = 0
        for _ in pairs(rhs.slots or {}) do n = n + 1 end
        return string.format('%d slots', n)
    elseif rhs.kind == 'combine' then
        local n = 0
        for _ in pairs(rhs.slots or {}) do n = n + 1 end
        return string.format('combine, %d overrides', n)
    elseif rhs.kind == 'ref' then
        return 'ref -> ' .. (rhs.target or '?')
    else
        return rhs.kind
    end
end

return tree

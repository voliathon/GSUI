-- Shared GearSwap slot helpers for GearTree.

local slots = {}

slots.order = {
    'main', 'sub', 'range', 'ammo',
    'head', 'neck', 'left_ear', 'right_ear',
    'body', 'hands', 'left_ring', 'right_ring',
    'back', 'waist', 'legs', 'feet',
}

local aliases = {
    main = 'main',
    sub = 'sub',
    range = 'range',
    ranged = 'range',
    ammo = 'ammo',
    head = 'head',
    neck = 'neck',
    ear1 = 'left_ear',
    lear = 'left_ear',
    learring = 'left_ear',
    left_ear = 'left_ear',
    ear2 = 'right_ear',
    rear = 'right_ear',
    rearring = 'right_ear',
    right_ear = 'right_ear',
    body = 'body',
    hands = 'hands',
    ring1 = 'left_ring',
    lring = 'left_ring',
    left_ring = 'left_ring',
    ring2 = 'right_ring',
    rring = 'right_ring',
    right_ring = 'right_ring',
    back = 'back',
    waist = 'waist',
    legs = 'legs',
    feet = 'feet',
}

slots.aliases_by_canonical = {}
for alias, canonical in pairs(aliases) do
    slots.aliases_by_canonical[canonical] = slots.aliases_by_canonical[canonical] or {}
    slots.aliases_by_canonical[canonical][#slots.aliases_by_canonical[canonical] + 1] = alias
end

function slots.canonical(slot)
    if not slot then return nil end
    return aliases[slot] or aliases[slot:lower()] or slot
end

function slots.is_slot(slot)
    return aliases[slot] ~= nil or aliases[(slot or ''):lower()] ~= nil
end

function slots.ordered_changes(changes)
    local out = {}
    for _, slot in ipairs(slots.order) do
        if changes[slot] then
            out[#out + 1] = slot
        end
    end
    return out
end

return slots

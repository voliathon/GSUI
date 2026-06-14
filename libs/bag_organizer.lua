local res = require('resources')
local packets = require('packets')
local scanner = require('libs/inventory_scanner')

local organizer = {}

local anywhere_bags = {
    inventory=true, wardrobe=true, wardrobe2=true, wardrobe3=true,
    wardrobe4=true, wardrobe5=true, wardrobe6=true, wardrobe7=true,
    wardrobe8=true, satchel=true, sack=true, case=true,
}
local mog_only_bags = {safe=true, safe2=true, storage=true, locker=true}

local move_queue = {}
local move_timer = 0
local MOVE_DELAY = 0.5
local in_mog_house = false

function organizer.set_mog_house(val)
    in_mog_house = val
end

-- Returns whether ANY mog-storage bag is currently writable.
--
-- The live check reads `enabled` flags from `windower.ffxi.get_items()`.
-- Each mog-only bag's `enabled` flag is true when the server has granted
-- the client access to that bag, which happens in three situations:
--
--   * Inside the player's Mog House (all four mog bags enabled)
--   * At a Nomad Moogle (Tu'Lia, Whitegate, Adoulin, etc.) -- the bag
--     the player selected from the moogle's menu becomes enabled
--   * At a Porter Moogle -- typically Storage becomes enabled
--
-- The previous implementation only checked `items.safe.enabled`, which
-- silently blocked transfers when the user was at a Nomad Moogle and
-- selected Mog Safe 2 / Storage / Locker instead of Mog Safe.
--
-- Packet-based detection (0x05F BGM, 0x00A zone finish) still updates
-- the cached `in_mog_house` flag as a fallback for the actual mog house.
function organizer.is_in_mog_house()
    local ok, items = pcall(windower.ffxi.get_items)
    if ok and items then
        for bag in pairs(mog_only_bags) do
            if items[bag] and items[bag].enabled == true then
                in_mog_house = true
                return true
            end
        end
        in_mog_house = false
        return false
    end
    return in_mog_house
end

-- Per-bag accessibility check. Returns true if the named bag is
-- currently writable from the player's location:
--
--   * "Anywhere" bags (inventory, wardrobe1-8, satchel, sack, case)
--     are always accessible while logged in.
--   * Mog-only bags (safe, safe2, storage, locker) require either
--     standing in the mog house OR a Nomad/Porter Moogle interaction
--     that has flipped this specific bag's `enabled` flag.
--
-- This is what the gsui.lua transfer guards should consult instead of
-- the coarse is_in_mog_house() check -- it correctly allows transfers
-- to/from whichever bag the Nomad Moogle has unlocked without
-- requiring the user to be at every other mog bag's home location.
function organizer.is_bag_currently_accessible(bag_name)
    if anywhere_bags[bag_name] then return true end
    if not mog_only_bags[bag_name] then return false end
    local ok, items = pcall(windower.ffxi.get_items)
    if not ok or not items then return false end
    local bag = items[bag_name]
    if not bag then return false end
    -- If `enabled` isn't exposed for some reason, fall back to the
    -- cached mog-house flag so we don't accidentally block transfers
    -- when the client API briefly omits the field.
    if bag.enabled == nil then return in_mog_house end
    return bag.enabled == true
end

function organizer.is_bag_accessible(bag_name)
    if anywhere_bags[bag_name] then return true end
    return mog_only_bags[bag_name] or false
end

function organizer.is_mog_bag(bag_name)
    return mog_only_bags[bag_name] or false
end

-- Find rings/earrings with identical copies in same bag
function organizer.find_conflicts(all_bag_items)
    local conflicts = {}
    local paired = {left_ring=true, right_ring=true, left_ear=true, right_ear=true}
    for bag_name, items in pairs(all_bag_items) do
        local by_key = {}
        for _, item in ipairs(items) do
            local is_paired = false
            if item.slots then
                for _, slot in ipairs(item.slots) do
                    if paired[slot] then is_paired = true; break end
                end
            end
            if is_paired then
                local aug_str = item.augments and table.concat(item.augments, '|') or 'none'
                local key = item.id .. ':' .. aug_str
                by_key[key] = by_key[key] or {}
                table.insert(by_key[key], item)
            end
        end
        for _, group in pairs(by_key) do
            if #group > 1 then
                table.insert(conflicts, {bag=bag_name, items=group, name=group[1].name})
            end
        end
    end
    return conflicts
end

-- Find non-equipment items scattered across multiple bags
function organizer.find_scattered(all_bag_items)
    local locations = {}
    for bag_name, items in pairs(all_bag_items) do
        for _, item in ipairs(items) do
            if not item.slots or #item.slots == 0 then
                if not locations[item.id] then
                    locations[item.id] = {name=item.name, bags={}}
                end
                locations[item.id].bags[bag_name] = (locations[item.id].bags[bag_name] or 0) + item.count
            end
        end
    end
    local scattered = {}
    for id, info in pairs(locations) do
        local n = 0
        for _ in pairs(info.bags) do n = n + 1 end
        if n > 1 then
            table.insert(scattered, {id=id, name=info.name, bags=info.bags})
        end
    end
    table.sort(scattered, function(a, b) return a.name < b.name end)
    return scattered
end

-- Queue an item move between bags
function organizer.queue_move(src_bag, src_index, dest_bag, count)
    table.insert(move_queue, {
        src_bag=src_bag, src_index=src_index,
        dest_bag=dest_bag, count=count,
    })
end

-- Process one move per tick with throttle.
--
-- We prefer Windower's native item-movement API over raw 0x029 packet
-- injection. The native calls stay in sync with whatever the current
-- Windower / FFXI client expects (HMAC fields, extra padding bytes,
-- Target Index conventions, etc.); the hand-rolled 0x029 we used to ship
-- was silently rejected by the server after a SE update -- packet fired,
-- both bags enabled, zero items moved.
--
--   get_item(bag_id, slot, count)  -- pulls FROM `bag_id` slot INTO inventory
--   put_item(bag_id, slot, count)  -- pushes FROM inventory slot INTO `bag_id`
--
-- Bag-to-bag with neither side being inventory falls back to the legacy
-- 0x029 packet (no native API for that, and FFXI itself routes through
-- inventory in the menu).
function organizer.process_queue()
    if #move_queue == 0 then return false end
    if os.clock() - move_timer < MOVE_DELAY then return true end
    local move = table.remove(move_queue, 1)
    local bag_ids = scanner.get_all_bag_ids()
    local src_id = bag_ids[move.src_bag]
    local dest_id = bag_ids[move.dest_bag]
    if src_id and dest_id then
        if move.dest_bag == 'inventory' then
            windower.ffxi.get_item(src_id, move.src_index, move.count)
        elseif move.src_bag == 'inventory' then
            windower.ffxi.put_item(dest_id, move.src_index, move.count)
        else
            local p = packets.new('outgoing', 0x029)
            p['Count'] = move.count
            p['Bag'] = src_id
            p['Target Bag'] = dest_id
            p['Current Index'] = move.src_index
            p['Target Index'] = 0x52
            packets.inject(p)
        end
    end
    move_timer = os.clock()
    return #move_queue > 0
end

function organizer.is_moving()
    return #move_queue > 0
end

function organizer.clear_queue()
    move_queue = {}
end

function organizer.get_queue_count()
    return #move_queue
end

return organizer

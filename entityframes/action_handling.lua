local packets = require('packets')
local set = require('set')
local client_data = require('resources')
local entities = require('entities')
local world = require('world')
local party = require('party')
local os = require('os')

local starting_categories = set(8,7,9,14,15)
local completed_categories = set(4,11,3,5,6)

local spell_categories = set(8,4)
local item_categories = set(5,9)
local weapon_skill_categories = set(3,7,11)
local job_ability_categories = set(6,14,15)

current_actions = {}
previous_actions = {}

aggro = {}

local is_npc = function(mob_id)
    local is_pc = mob_id < 0x01000000
    local is_pet = mob_id > 0x01000000 and mob_id % 0x1000 > 0x700

    -- filter out pcs and known pet IDs
    if is_pc or is_pet then return false end

    return true
end

local get_party_ids = function()
    local s = set()
    for i = 1, 18 do
        local member = party[i]
        if member ~= nil then
            s:add(member.id)
        end
    end
    return s
end

local handle_incoming_action = function(action, info)
    if not action.category then 
        return 
    end

    local party = get_party_ids()
    if is_npc(action.actor) then
        -- track aggro
        local a = aggro[action.actor]
        if a == nil then
            a = { actor = entities.npcs:by_id(action.actor), }
        end
        if party:contains(action.targets[1].id) then
            a.primary_target = entities:by_id(action.targets[1].id)
        else
            a.primary_target = nil
        end

        if a.primary_target ~= nil then
            a.last_action_time = os.clock()

            aggro[action.actor] = a
        else
            aggro[action.actor] = nil
        end
    elseif party:contains(action.actor) then
        for i = 1, action.target_count do
            local a = aggro[action.targets[i].id]
            if a == nil then
                a = { actor = entities.npcs:by_id(action.targets[i].id) }
            end
            a.last_action_time = os.clock()
            a.primary_target = entities.pcs:by_id(action.actor)
            
            aggro[action.targets[i].id] = a
        end        
    end

    if not starting_categories:contains(action.category) and not completed_categories:contains(action.category) then
        return 
    end

    -- if it's a starting packet, the action id is in param2
    local action_id = action.param
    if starting_categories:contains(action.category) then
        action_id = action.targets[1].actions[1].param
    end

    if action_id == 0 then 
        return 
    end

    local action_data = nil
    if spell_categories:contains(action.category) then
        action_data = client_data.spells[action_id]
    elseif job_ability_categories:contains(action.category) then
        action_data = client_data.job_abilities[action_id]
    elseif is_npc(action.actor) then
        action_data = client_data.monster_abilities[action_id]
    elseif weapon_skill_categories:contains(action.category) then
        action_data = client_data.weapon_skills[action_id]
    elseif item_categories:contains(action.category) then
        action_data = client_data.items[action_id]
    end

    -- couldn't find the action, let's just give some debug output.
    if not action_data then
        action_data = {en='Unknown (id:'..action_id..', cat: '..action.category..')'}
    end 

    local complete = completed_categories:contains(action.category)
    local interrupted = (action.targets[1].actions[1].message == 0 and action.targets[1].id == action.actor)
    if interrupted or complete then
        -- cast was interrupted or completed
        previous_actions[action.actor] = {actor=entities:by_id(action.actor), target=entities:by_id(action.targets[1].id), action=action_data, interrupted=interrupted, time=os.clock()}
        current_actions[action.actor] = nil;
    else
        current_actions[action.actor] = {actor=entities:by_id(action.actor), target=entities:by_id(action.targets[1].id), action=action_data, time=os.clock()}
    end
end

packets.incoming[0x028]:register(handle_incoming_action)
world.zone_change:register(function(...)
    current_actions = {}
    previous_actions = {}

    aggro = {}
end)
do
    local MAX_NUM_HUB_INVENTORY_SLOTS = 65535
    local DEFAULT_UPDATE_PERIOD_IN_TICKS = 60
    local MIN_UPDATE_PERIOD_IN_TICKS = 1

    local function get_cargo_bay_entity_inventory_bonus(entity)
        local total_bonus = 20 -- TODO: get this from data-stage prototype somehow
        local quality_scale = 1.0 + 0.3 * entity.quality.level
        return math.floor(total_bonus * quality_scale + 0.5)
    end

    local function get_unlimited_hub_slot_count(entity)
        local bay_entities = entity.surface.find_entities_filtered{type="cargo-bay"}
        local num_slots = entity.prototype.get_inventory_size(defines.inventory.cargo_landing_pad_main)
        for _, bay in ipairs(bay_entities) do
            local status = bay.status
            if status == defines.entity_status.normal then
                num_slots = num_slots + get_cargo_bay_entity_inventory_bonus(bay)
            end
        end
        return num_slots
    end

    local function get_or_create_bag(this_surface_storage)
        if this_surface_storage.bag == nil then
            this_surface_storage.bag = {
                num_used_slots = 0,
                num_slots = 0,
                contents = {}
            }
        end

        return this_surface_storage.bag
    end

    local function update_hub_on_surface(surface)
        if storage.dirty_hub_surfaces[surface.index] ~= nil then
            storage.dirty_hub_surfaces[surface.index] = nil

            local this_surface_storage = storage.per_surface[surface.index]

            local hub_entities = surface.find_entities_filtered{type={"cargo-landing-pad", "space-platform-hub"}}
            if #hub_entities == 0 then
                this_surface_storage.hub = nil
            else
                local entity = hub_entities[1]
                local num_slots = get_unlimited_hub_slot_count(entity)
                this_surface_storage.hub = {
                    entity = entity,
                    num_slots = num_slots
                }

                local bag = get_or_create_bag(this_surface_storage)
                bag.num_slots = math.max(0, num_slots - MAX_NUM_HUB_INVENTORY_SLOTS)
            end
        end
    end

    local function update_controls_on_surface(surface)
        if storage.dirty_control_surfaces[surface.index] ~= nil then
            storage.dirty_control_surfaces[surface.index] = nil

            local this_surface_storage = storage.per_surface[surface.index]

            local control_entities = surface.find_entities_filtered{name="hub-limiter-combinator"}
            if #control_entities == 0 then
                this_surface_storage.controls = nil
            else
                local entity = control_entities[1]
                this_surface_storage.controls = {
                    entity = entity
                }
            end

            local status_entities = surface.find_entities_filtered{name="hub-bag-status-combinator"}
            this_surface_storage.bag_status_combinators = {}
            for _, entity in ipairs(status_entities) do
                table.insert(this_surface_storage.bag_status_combinators, {entity=entity})
            end
        end
    end

    local function update_surface(surface)
        update_hub_on_surface(surface)
        update_controls_on_surface(surface)
    end

    local function get_update_period_in_ticks_from_controls(controls)
        local combinator_entity = controls.entity
        local control_behavior = combinator_entity.get_control_behavior()

        if control_behavior.valid and control_behavior.enabled then
            for _, section in ipairs(control_behavior.sections) do
                if section.active then
                    for _, filter in ipairs(section.filters) do
                        if filter ~= nil and filter.value ~= nil and filter.value.name == "signal-T" then
                            return math.max(MIN_UPDATE_PERIOD_IN_TICKS, filter.min)
                        end
                    end
                end
            end

            return DEFAULT_UPDATE_PERIOD_IN_TICKS
        end

        return nil
    end

    local function get_item_thresholds_from_controls(controls)
        local combinator_entity = controls.entity
        local control_behavior = combinator_entity.get_control_behavior()
        
        local thresholds = {}

        if control_behavior.valid and control_behavior.enabled then
            for _, section in ipairs(control_behavior.sections) do
                if section.active then
                    for _, filter in ipairs(section.filters) do
                        if filter ~= nil and filter.value ~= nil and (filter.value.type == "item" or filter.value.type == "entity") then
                            local item_count = filter.min or 0
                            local item_name = filter.value.name
                            local item_quality = filter.value.quality
                            
                            local key = item_name .. "$" .. item_quality
                            thresholds[key] = (thresholds[key] or 0) + item_count
                        end
                    end
                end
            end
        end

        return thresholds
    end

    local function transfer_normal_items_to_bag(inventory, bag, item, item_prototype, num_stacks)
        local key = item.name .. "$" .. item.quality
        if bag.contents[key] == nil then
            bag.contents[key] = {
                num_stacks = 0,
                stack_size = item_prototype.stack_size,
                item = {name = item.name, quality = item.quality},
                item_prototype = item_prototype
            }
        end

        local num_items_to_remove = item_prototype.stack_size * num_stacks
        local num_items_removed = inventory.remove({name=item.name, quality=item.quality, count=num_items_to_remove})
        assert(num_items_removed == num_items_to_remove, "Removed fewer items than expected from an inventory.")
        bag.contents[key].num_stacks = bag.contents[key].num_stacks + num_stacks
        bag.num_used_slots = bag.num_used_slots + num_stacks
    end

    local function try_transfer_items_to_bag(inventory, bag, item, item_prototype, num_stacks)
        local item_type = item_prototype.type

        -- Moving tools/ammo like normal items disregards durability, which may
        -- increase the actual value in some cases, however there's no good alternative
        -- with the current API. 
        -- Though if the inventory is well behaved then we should only be
        -- moving full stacks, in which case the durability is always full.
        if item_type == "item" or item_type == "tool" or item_type == "ammo" or item_type == "module" then
            transfer_normal_items_to_bag(inventory, bag, item, item_prototype, num_stacks)
            return true
        end
        
        return false
    end

    local function transfer_normal_items_from_bag(inventory, bag, item, item_prototype, num_stacks)
        local key = item.name .. "$" .. item.quality
        if bag.contents[key] == nil then
            assert(false, "Bag does not actually contain the item")
        end

        assert(bag.contents[key].num_stacks >= num_stacks, "Bag does not contain enough items")

        local num_items_to_add = item_prototype.stack_size * num_stacks
        local num_items_added = inventory.insert({name=item.name, quality=item.quality, count=num_items_to_add})
        assert(num_items_added == num_items_to_add, "Added fewer items than expected to an inventory.")
        bag.contents[key].num_stacks = bag.contents[key].num_stacks - num_stacks
        bag.num_used_slots = bag.num_used_slots - num_stacks

        if bag.contents[key].num_stacks == 0 then
            bag.contents[key] = nil
        end
    end

    local function transfer_items_from_bag(inventory, bag, item, item_prototype, num_stacks)
        local item_type = item_prototype.type
        
        if item_type == "item" or item_type == "tool" or item_type == "ammo" or item_type == "module"  then
            transfer_normal_items_from_bag(inventory, bag, item, item_prototype, num_stacks)
        else
            assert(false, "Bag contains an item of unsupported type.")
        end
    end

    local function update_hub_contents(hub, bag, item_thresholds)
        local entity = hub.entity
        local num_slots = hub.num_slots

        local inventory = hub.entity.get_inventory(defines.inventory.cargo_landing_pad_main) -- == .hub_main

        local counts_by_key = {}

        -- Inventory to bag
        if bag.num_used_slots < bag.num_slots then
            local inventory_contents = inventory.get_contents()
            for _, item in ipairs(inventory_contents) do
                local key = item.name .. "$" .. item.quality
                counts_by_key[key] = item.count
                local threshold = item_thresholds[key]
                if threshold ~= nil then
                    local item_prototype = prototypes.item[item.name]
                    local stack_size = item_prototype.stack_size
                    local num_full_stacks_in_inventory = math.floor(item.count / stack_size)
                    local max_full_stacks_in_inventory = math.max(1, math.ceil(threshold / stack_size))

                    if num_full_stacks_in_inventory > max_full_stacks_in_inventory then
                        local ideal_num_stacks_to_transfer_to_bag = num_full_stacks_in_inventory - max_full_stacks_in_inventory
                        local num_empty_bag_slots = bag.num_slots - bag.num_used_slots

                        local actual_num_stacks_to_transfer_to_bag = math.min(num_empty_bag_slots, ideal_num_stacks_to_transfer_to_bag)
                        if actual_num_stacks_to_transfer_to_bag > 0 then
                            try_transfer_items_to_bag(inventory, bag, item, item_prototype, actual_num_stacks_to_transfer_to_bag)
                        end
                    end
                end
            end
        end

        -- Bag to inventory
        if bag.num_used_slots > 0 then
            local num_empty_stacks = inventory.count_empty_stacks()

            for key, bag_item_stack in pairs(bag.contents) do
                local threshold = item_thresholds[key]
                local item_prototype = bag_item_stack.item_prototype
                local stack_size = item_prototype.stack_size
                local num_full_stacks_in_inventory = math.floor((counts_by_key[key] or 0) / stack_size)
                local max_full_stacks_in_inventory = math.max(1, math.ceil((threshold or (MAX_NUM_HUB_INVENTORY_SLOTS * stack_size)) / stack_size))

                --game.print(serpent.block({item=key, num_full_stacks_in_inventory=num_full_stacks_in_inventory, max_full_stacks_in_inventory=max_full_stacks_in_inventory, in_bag=bag_item_stack.num_stacks}))
                if num_full_stacks_in_inventory < max_full_stacks_in_inventory then
                    local ideal_num_stacks_to_transfer_from_bag = max_full_stacks_in_inventory - num_full_stacks_in_inventory

                    local actual_num_stacks_to_transfer_from_bag = math.min(num_empty_stacks, ideal_num_stacks_to_transfer_from_bag, bag_item_stack.num_stacks)
                    if actual_num_stacks_to_transfer_from_bag > 0 then
                        transfer_items_from_bag(inventory, bag, bag_item_stack.item, item_prototype, actual_num_stacks_to_transfer_from_bag)
                        num_empty_stacks = num_empty_stacks - actual_num_stacks_to_transfer_from_bag
                    end
                end
            end

            -- Try forcibly spilling back to inventory if bag is overflowing. Will happen if cargo bays are removed.
            if bag.num_slots < bag.num_used_slots then
                for key, bag_item_stack in pairs(bag.contents) do
                    local item_prototype = bag_item_stack.item_prototype
                    local actual_num_stacks_to_transfer_from_bag = math.min(num_empty_stacks, bag_item_stack.num_stacks)
                    if actual_num_stacks_to_transfer_from_bag > 0 then
                        transfer_items_from_bag(inventory, bag, bag_item_stack.item, item_prototype, actual_num_stacks_to_transfer_from_bag)
                        num_empty_stacks = num_empty_stacks - actual_num_stacks_to_transfer_from_bag
                    end
                end
            end
        end
    end

    local function update_bag_status_combinators(combinators, hub, bag)
        for _, combinator in ipairs(combinators) do
            local combinator_entity = combinator.entity
            local control_behavior = combinator_entity.get_control_behavior()
            while control_behavior.remove_section(1) do end
            control_behavior.enabled = true
            local contents_section = control_behavior.add_section()
            local slot = 1
            for key, bag_item_stack in pairs(bag.contents) do
                contents_section.set_slot(slot, {
                    value = bag_item_stack.item,
                    min = bag_item_stack.num_stacks * bag_item_stack.stack_size
                })
                slot = slot + 1
            end

            local num_slots = hub.num_slots
            local metadata_section = control_behavior.add_section()
            metadata_section.set_slot(1, {
                value = {type = "virtual", name = "signal-S", quality = "normal"},
                min = bag.num_slots
            })
            metadata_section.set_slot(2, {
                value = {type = "virtual", name = "signal-U", quality = "normal"},
                min = bag.num_used_slots
            })
        end
    end

    local function process_surface(surface, tick_offset)
        local this_surface_storage = storage.per_surface[surface.index]
        local controls = this_surface_storage.controls
        local hub = this_surface_storage.hub
        if hub ~= nil and controls ~= nil then
            local update_period = get_update_period_in_ticks_from_controls(controls)
            if (game.tick + tick_offset) % update_period == 0 then
                local bag = get_or_create_bag(this_surface_storage)
                local item_thresholds = get_item_thresholds_from_controls(controls)
                update_hub_contents(hub, bag, item_thresholds)
                update_bag_status_combinators(this_surface_storage.bag_status_combinators, hub, bag)
            end
        end
    end

    local entity_changed_events = {
        defines.events.script_raised_built,
        defines.events.on_built_entity,
        defines.events.on_space_platform_built_entity,
        defines.events.on_robot_built_entity,
        defines.events.script_raised_destroy,
        defines.events.on_player_mined_entity,
        defines.events.on_space_platform_mined_entity,
        defines.events.on_robot_mined_entity,
        defines.events.on_entity_died,
        defines.events.script_raised_revive
    }

    local entity_changed_events_filter = {
        { filter = "type", type = "cargo-bay" },
        { filter = "type", type = "cargo-landing-pad" },
        { filter = "type", type = "space-platform-hub" },
        { filter = "name", name = "hub-limiter-combinator" },
        { filter = "name", name = "hub-bag-status-combinator" },
    }

    for _, event_id in ipairs(entity_changed_events) do
        script.on_event(event_id, function(event)
                if event.entity.name == "hub-limiter-combinator" or event.entity.name == "hub-bag-status-combinator" then
                    storage.dirty_control_surfaces[event.entity.surface.index] = true
                else
                    storage.dirty_hub_surfaces[event.entity.surface.index] = true
                end
            end,
            entity_changed_events_filter
        )
    end

    script.on_event(defines.events.on_surface_created, function(event)
        storage.per_surface[event.surface_index] = {}
    end)

    script.on_event(defines.events.on_surface_deleted, function(event)
        storage.per_surface[event.surface_index] = nil
    end)

    script.on_event(defines.events.on_tick, function(event)
        -- We offset updates for each surface in time to reduce stutter.
        local tick_offset = 0
        for _, surface in pairs(game.surfaces) do
            update_surface(surface)

            process_surface(surface, tick_offset)

            tick_offset = tick_offset + 1
        end
    end)

    local function init()
        storage.dirty_hub_surfaces = {}
    
        storage.dirty_control_surfaces = {}
    
        storage.per_surface = {}
        for _, surface in pairs(game.surfaces) do
            storage.per_surface[surface.index] = {}

            table.insert(storage.dirty_hub_surfaces, surface)
            table.insert(storage.dirty_control_surfaces, surface)
        end
    end

    script.on_init(function()
        init()
    end)

    script.on_configuration_changed(function()
        init()
    end)
end
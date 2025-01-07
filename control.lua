do
    local is_initialized = false
    local hubs = {}

    local function get_unlimited_hub_slot_count(entity)
        -- TODO: this
        return 100000
    end

    local function add_hub(entity)
        table.insert(hubs, { entity=entity, slot_count=get_unlimited_hub_slot_count(entity) })
    end

    local function update_hub(entity)
        for _, hub in ipairs(hubs) do
            if hub.entity == entity then
                hub.slot_count = get_unlimited_hub_slot_count(hub.entity)
                break
            end
        end
    end

    local function init()
        for _, surface in pairs(game.surfaces) do
            local hub_entities = surface.find_entities_filtered{type="cargo-landing-pad"}
            for _, entity in ipairs(hub_entities) do
                add_hub(entity)
            end
        end

        is_initialized = true
    end

    script.on_event(defines.events.on_tick, function(event)
        if not is_initialized then
            init()
        end

        for _, hub in ipairs(hubs) do
            local inventory = hub.entity.get_inventory(defines.inventory.cargo_landing_pad_main)
            local contents = inventory.get_contents()

            for _, item in ipairs(contents) do
                game.print(item.name .. tostring(prototypes.item[item.name].type == "tool"))
            end
        end
    end)
end
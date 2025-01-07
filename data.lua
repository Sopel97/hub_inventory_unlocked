do
    local hub_limiter_combinator_entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
    hub_limiter_combinator_entity.localised_name = {"", "Hub Limiter Combinator"}
    hub_limiter_combinator_entity.name = "hub_limiter_combinator"
    hub_limiter_combinator_entity.minable = {mining_time = 0.1, result = "hub_limiter_combinator"}
    data:extend({hub_limiter_combinator_entity})

    local hub_limiter_combinator_item = table.deepcopy(data.raw["item"]["constant-combinator"])
    hub_limiter_combinator_item.name = "hub_limiter_combinator"
    hub_limiter_combinator_item.place_result = "hub_limiter_combinator"
    hub_limiter_combinator_item.order = "z[hub_limiter_combinator]"
    data:extend({hub_limiter_combinator_item})
end
do
    local hub_limiter_combinator_entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
    hub_limiter_combinator_entity.localised_name = {"", "Hub Limiter Combinator"}
    hub_limiter_combinator_entity.name = "hub-limiter-combinator"
    hub_limiter_combinator_entity.minable = {mining_time = 0.1, result = "hub-limiter-combinator"}
    data:extend({hub_limiter_combinator_entity})

    local hub_limiter_combinator_item = table.deepcopy(data.raw["item"]["constant-combinator"])
    hub_limiter_combinator_item.name = "hub-limiter-combinator"
    hub_limiter_combinator_item.place_result = "hub-limiter-combinator"
    hub_limiter_combinator_item.order = "z[hub-limiter-combinator]"
    data:extend({hub_limiter_combinator_item})

    local hub_bag_status_combinator_entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
    hub_bag_status_combinator_entity.localised_name = {"", "Hub Bag Status Combinator"}
    hub_bag_status_combinator_entity.name = "hub-bag-status-combinator"
    hub_bag_status_combinator_entity.minable = {mining_time = 0.1, result = "hub-bag-status-combinator"}
    data:extend({hub_bag_status_combinator_entity})

    local hub_bag_status_combinator_item = table.deepcopy(data.raw["item"]["constant-combinator"])
    hub_bag_status_combinator_item.name = "hub-bag-status-combinator"
    hub_bag_status_combinator_item.place_result = "hub-bag-status-combinator"
    hub_bag_status_combinator_item.order = "z[hub-bag-status-combinator]"
    data:extend({hub_bag_status_combinator_item})
end
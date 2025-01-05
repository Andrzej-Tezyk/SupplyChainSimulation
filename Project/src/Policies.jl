abstract type OrderingPolicy end

struct SSPolicy <: OrderingPolicy
    s::Float64  # reorder point
    S::Float64  # order-up-to level
end

function calculate_order_quantity(policy::SSPolicy, state::SimulationState, storage::Storage, product::Product)
    current_inventory = get(state.inventory, (storage, product), 0)
    if current_inventory <= policy.s
        return policy.S - current_inventory
    end
    return 0.0
end 
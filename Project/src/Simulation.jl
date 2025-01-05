include("Types.jl")
include("Network.jl")
include("State.jl")
include("Policies.jl")

function process_orders!(state::SimulationState)
    for order in state.pending_orders
        if order.due_date == state.current_time
            if isa(order.destination, Storage)
                state.inventory[(order.destination, order.product)] = 
                    get(state.inventory, (order.destination, order.product), 0) + order.quantity
            end
            push!(state.fulfilled_orders, order)
        end
    end
    
    # Remove fulfilled orders from pending
    filter!(o -> o.due_date > state.current_time, state.pending_orders)
end

function update_inventory!(state::SimulationState)
    for storage in state.network.storages
        for product in state.network.products
            if haskey(state.inventory, (storage, product))
                # Add holding costs
                state.total_costs += state.inventory[(storage, product)] * storage.products[product]
            end
        end
    end
end

function place_orders!(state::SimulationState, policies::Dict)
    for storage in state.network.storages
        for product in state.network.products
            if haskey(policies, (storage, product))
                policy = policies[(storage, product)]
                quantity = calculate_order_quantity(policy, state, storage, product)
                
                if quantity > 0
                    # Find best supplier based on cost and lead time
                    best_lane = nothing
                    min_cost = Inf
                    
                    for lane in state.network.lanes
                        if lane.destination == storage && lane.origin isa Supplier
                            total_cost = lane.fixed_cost + lane.unit_cost * quantity
                            if total_cost < min_cost
                                min_cost = total_cost
                                best_lane = lane
                            end
                        end
                    end
                    
                    if !isnothing(best_lane)
                        order = Order(
                            state.current_time,
                            best_lane.origin,
                            storage,
                            product,
                            quantity,
                            state.current_time + best_lane.time
                        )
                        push!(state.pending_orders, order)
                        state.total_costs += min_cost
                    end
                end
            end
        end
    end
end

function process_demand!(state::SimulationState)
    for demand in state.network.demands
        current_demand = demand.quantities[state.current_time]
        if current_demand > 0
            # Find closest storage with inventory
            fulfilled = false
            for storage in state.network.storages
                if haskey(state.inventory, (storage, demand.product)) && 
                   state.inventory[(storage, demand.product)] >= current_demand
                    state.inventory[(storage, demand.product)] -= current_demand
                    fulfilled = true
                    break
                end
            end
            
            if !fulfilled
                state.lost_sales[(demand.customer, demand.product)] = 
                    get(state.lost_sales, (demand.customer, demand.product), 0) + current_demand
            end
        end
    end
end

function simulate(network::SupplyChainNetwork, policies::Dict)
    state = initialize_state(network)
    
    for t in 1:network.horizon
        state.current_time = t
        process_orders!(state)
        update_inventory!(state)
        place_orders!(state, policies)
        process_demand!(state)
    end
    
    return state
end
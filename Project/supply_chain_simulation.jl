using Distributions

# Basic types
abstract type Node end
abstract type Location <: Node end

# Product definition
struct Product
    name::String
    base_price::Float64
end

# Node types
struct Supplier <: Node
    name::String
    location::String
end

mutable struct Storage <: Location
    name::String
    location::String
    products::Dict{Product, Float64}  # Product -> holding cost
    inventory::Dict{Product, Float64}  # Product -> quantity
end

struct Customer <: Node
    name::String
    region::String
end

# Transportation lane
struct Lane
    origin::Node
    destination::Node
    time::Int64
    fixed_cost::Float64
    unit_cost::Float64
end

# Order representation
struct Order
    creation_time::Int64
    origin::Node
    destination::Node
    product::Product
    quantity::Float64
    due_date::Int64
end

# Demand representation
struct Demand
    customer::Customer
    product::Product
    quantities::Vector{Float64}
    sales_price::Float64
    lost_sales_cost::Float64
end

# Network structure
mutable struct SupplyChainNetwork
    horizon::Int64
    suppliers::Vector{Supplier}
    storages::Vector{Storage}
    customers::Vector{Customer}
    products::Vector{Product}
    lanes::Vector{Lane}
    demands::Vector{Demand}
end

# State tracking
mutable struct SimulationState
    network::SupplyChainNetwork
    current_time::Int64
    inventory::Dict{Tuple{Storage, Product}, Float64}
    pending_orders::Vector{Order}
    fulfilled_orders::Vector{Order}
    lost_sales::Dict{Tuple{Customer, Product}, Float64}
    total_costs::Float64
end

# Network creation functions
function create_network(horizon::Int64)
    SupplyChainNetwork(
        horizon,
        Supplier[],
        Storage[],
        Customer[],
        Product[],
        Lane[],
        Demand[]
    )
end

function add_supplier!(network::SupplyChainNetwork, supplier::Supplier)
    push!(network.suppliers, supplier)
end

function add_storage!(network::SupplyChainNetwork, storage::Storage)
    push!(network.storages, storage)
end

function add_customer!(network::SupplyChainNetwork, customer::Customer)
    push!(network.customers, customer)
end

function add_product!(network::SupplyChainNetwork, product::Product)
    push!(network.products, product)
end

function add_lane!(network::SupplyChainNetwork, lane::Lane)
    push!(network.lanes, lane)
end

function add_demand!(network::SupplyChainNetwork, demand::Demand)
    push!(network.demands, demand)
end

# Simulation functions
function initialize_state(network::SupplyChainNetwork)
    SimulationState(
        network,
        1,
        Dict{Tuple{Storage, Product}, Float64}(),
        Order[],
        Order[],
        Dict{Tuple{Customer, Product}, Float64}(),
        0.0
    )
end

function process_orders!(state::SimulationState)
    for order in state.pending_orders
        if order.due_date == state.current_time
            if isa(order.destination, Storage)
                state.inventory[(order.destination, order.product)] = 
                    get(state.inventory, (order.destination, order.product), 0.0) + order.quantity
            end
            push!(state.fulfilled_orders, order)
        end
    end
    
    filter!(o -> o.due_date > state.current_time, state.pending_orders)
end

function update_inventory!(state::SimulationState)
    for storage in state.network.storages
        for product in state.network.products
            if haskey(state.inventory, (storage, product))
                state.total_costs += state.inventory[(storage, product)] * storage.products[product]
            end
        end
    end
end

# Ordering policy
struct SSPolicy
    s::Float64  # reorder point
    S::Float64  # order-up-to level
end

function calculate_order_quantity(policy::SSPolicy, state::SimulationState, storage::Storage, product::Product)
    current_inventory = get(state.inventory, (storage, product), 0.0)
    if current_inventory <= policy.s
        return policy.S - current_inventory
    end
    return 0.0
end

function place_orders!(state::SimulationState, policies::Dict)
    for storage in state.network.storages
        for product in state.network.products
            if haskey(policies, (storage, product))
                policy = policies[(storage, product)]
                quantity = calculate_order_quantity(policy, state, storage, product)
                
                if quantity > 0
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
                    get(state.lost_sales, (demand.customer, demand.product), 0.0) + current_demand
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

# Helper function for seasonal demand
function generate_seasonal_demand(horizon::Int64; base::Float64=50.0, amplitude::Float64=20.0)
    demand = Float64[]
    for t in 1:horizon
        seasonal_factor = amplitude * sin(2π * t / 365)
        daily_demand = base + seasonal_factor + rand(Poisson(10))
        push!(demand, max(0.0, daily_demand))
    end
    return demand
end 
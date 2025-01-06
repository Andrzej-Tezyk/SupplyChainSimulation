using Distributions
using Plots
using Statistics

# Basic types and structures
abstract type Node end
abstract type Location <: Node end

struct Product
    name::String
    base_price::Float64
end

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

struct Lane
    origin::Node
    destination::Node
    time::Int64
    fixed_cost::Float64
    unit_cost::Float64
end

struct Order
    creation_time::Int64
    origin::Node
    destination::Node
    product::Product
    quantity::Float64
    due_date::Int64
end

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
    inventory_history::Dict{Tuple{Storage, Product}, Vector{Float64}}
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
    state = SimulationState(
        network,
        1,
        Dict{Tuple{Storage, Product}, Float64}(),
        Dict{Tuple{Storage, Product}, Vector{Float64}}(),
        Order[],
        Order[],
        Dict{Tuple{Customer, Product}, Float64}(),
        0.0
    )
    
    # Initialize inventory from storage initial conditions
    for storage in network.storages
        for (product, quantity) in storage.inventory
            state.inventory[(storage, product)] = quantity
            state.inventory_history[(storage, product)] = Float64[quantity]
        end
    end
    
    return state
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
                current_level = state.inventory[(storage, product)]
                
                # Record inventory level in history
                if !haskey(state.inventory_history, (storage, product))
                    state.inventory_history[(storage, product)] = Float64[]
                end
                push!(state.inventory_history[(storage, product)], current_level)
                
                # Add holding costs
                state.total_costs += current_level * storage.products[product]
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

function plot_inventory_levels(state::SimulationState)
    p = plot(
        title="Inventory Levels Over Time",
        xlabel="Time (days)",
        ylabel="Inventory Level",
        legend=:topright
    )
    
    colors = [:blue, :red, :green]
    styles = [:solid, :dash, :dot]
    
    for (i, storage) in enumerate(state.network.storages)
        for (j, product) in enumerate(state.network.products)
            if haskey(state.inventory_history, (storage, product))
                history = state.inventory_history[(storage, product)]
                plot!(p, 1:length(history), history,
                    label="$(storage.name) - $(product.name)",
                    color=colors[i],
                    linestyle=styles[j])
            end
        end
    end
    
    return p
end

function plot_demand_patterns(state::SimulationState)
    p = plot(
        title="Demand Patterns",
        xlabel="Time (days)",
        ylabel="Demand Quantity",
        legend=:topright
    )
    
    for demand in state.network.demands
        plot!(p, 1:state.network.horizon, demand.quantities,
            label="$(demand.customer.region) - $(demand.product.name)")
    end
    
    return p
end

function plot_costs_breakdown(state::SimulationState)
    # Calculate different cost components
    holding_costs = Dict{String, Float64}()
    transportation_costs = Dict{String, Float64}()
    lost_sales_costs = Dict{String, Float64}()
    
    for storage in state.network.storages
        holding_costs[storage.name] = 0.0
        for product in state.network.products
            if haskey(state.inventory, (storage, product))
                holding_costs[storage.name] += state.inventory[(storage, product)] * 
                    storage.products[product]
            end
        end
    end
    
    # Create bar plot for costs
    costs_data = [
        sum(values(holding_costs)),
        sum(values(lost_sales_costs)),
        state.total_costs - sum(values(holding_costs)) - sum(values(lost_sales_costs))
    ]
    
    p = bar(["Holding Costs", "Lost Sales Costs", "Transportation Costs"],
        costs_data,
        title="Cost Breakdown",
        ylabel="Cost (\$)",
        legend=false,
        rotation=45)
    
    return p
end

function plot_service_level(state::SimulationState)
    total_demand = Dict{Tuple{Customer, Product}, Float64}()
    fulfilled_demand = Dict{Tuple{Customer, Product}, Float64}()
    
    # Calculate total and fulfilled demand
    for demand in state.network.demands
        total = sum(demand.quantities)
        lost = get(state.lost_sales, (demand.customer, demand.product), 0.0)
        total_demand[(demand.customer, demand.product)] = total
        fulfilled_demand[(demand.customer, demand.product)] = total - lost
    end
    
    # Calculate service levels
    service_levels = []
    labels = []
    
    for ((customer, product), total) in total_demand
        if total > 0
            fulfilled = fulfilled_demand[(customer, product)]
            push!(service_levels, (fulfilled / total) * 100)
            push!(labels, "$(customer.region)\n$(product.name)")
        end
    end
    
    p = bar(labels,
        service_levels,
        title="Service Levels by Market and Product",
        ylabel="Service Level (%)",
        legend=false,
        rotation=45)
    
    return p
end

# Create simulation instance
function run_simulation()
    # Create products
    smart_thermostat = Product("Smart Thermostat", 200.0)
    security_camera = Product("Security Camera", 150.0)
    smart_lighting = Product("Smart Lighting", 100.0)

    # Create suppliers
    usa_factory = Supplier("USA Factory", "USA")
    asia_factory = Supplier("Asia Factory", "China")

    # Create distribution centers
    europe_dc = Storage("Europe DC", "Germany", 
        Dict(smart_thermostat => 0.5, security_camera => 0.7, smart_lighting => 0.3),
        Dict(smart_thermostat => 100.0, security_camera => 100.0, smart_lighting => 100.0))

    namerica_dc = Storage("North America DC", "USA",
        Dict(smart_thermostat => 0.5, security_camera => 0.7, smart_lighting => 0.3),
        Dict(smart_thermostat => 100.0, security_camera => 100.0, smart_lighting => 100.0))

    asia_dc = Storage("Asia Pacific DC", "Singapore",
        Dict(smart_thermostat => 0.5, security_camera => 0.7, smart_lighting => 0.3),
        Dict(smart_thermostat => 100.0, security_camera => 100.0, smart_lighting => 100.0))

    # Create markets
    eu_market = Customer("EU Market", "Europe")
    us_market = Customer("US Market", "North America")
    asia_market = Customer("Asia Market", "Asia")

    # Initialize network
    horizon = 365
    network = create_network(horizon)

    # Add components to network
    for supplier in [usa_factory, asia_factory]
        add_supplier!(network, supplier)
    end

    for dc in [europe_dc, namerica_dc, asia_dc]
        add_storage!(network, dc)
    end

    for market in [eu_market, us_market, asia_market]
        add_customer!(network, market)
    end

    for product in [smart_thermostat, security_camera, smart_lighting]
        add_product!(network, product)
    end

    # Add transportation lanes
    lanes = [
        Lane(usa_factory, namerica_dc, 5, 1000.0, 10.0),
        Lane(usa_factory, europe_dc, 15, 2000.0, 20.0),
        Lane(usa_factory, asia_dc, 20, 2500.0, 25.0),
        Lane(asia_factory, namerica_dc, 20, 2500.0, 25.0),
        Lane(asia_factory, europe_dc, 25, 3000.0, 30.0),
        Lane(asia_factory, asia_dc, 5, 1000.0, 10.0)
    ]

    for lane in lanes
        add_lane!(network, lane)
    end

    # Add demands to network
    demands = [
        Demand(eu_market, smart_thermostat, generate_seasonal_demand(horizon, base=50.0, amplitude=30.0), 200.0, 50.0),
        Demand(us_market, security_camera, rand(Poisson(40), horizon), 150.0, 40.0),
        Demand(asia_market, smart_lighting, rand(Poisson(60), horizon), 100.0, 30.0)
    ]

    for demand in demands
        add_demand!(network, demand)
    end

    # Define ordering policies
    policies = Dict()
    for dc in [europe_dc, namerica_dc, asia_dc]
        for product in [smart_thermostat, security_camera, smart_lighting]
            policies[(dc, product)] = SSPolicy(50.0, 200.0)
        end
    end

    # Run simulation
    final_state = simulate(network, policies)

    # Print results
    println("Simulation Results:")
    println("Total Lost Sales: ", sum(values(final_state.lost_sales)))
    println("Total Fulfilled Orders: ", length(final_state.fulfilled_orders))
    println("Total Costs: ", final_state.total_costs)
    
    # Create visualizations
    p1 = plot_inventory_levels(final_state)
    p2 = plot_demand_patterns(final_state)
    p3 = plot_costs_breakdown(final_state)
    p4 = plot_service_level(final_state)
    
    # Combine plots into a single figure
    combined_plot = plot(p1, p2, p3, p4, layout=(2,2), size=(1200,800))
    display(combined_plot)
    savefig(combined_plot, "supply_chain_analysis.png")
    
    println("\nDetailed Cost Breakdown:")
    holding_costs = 0.0
    lost_sales_costs = 0.0
    
    # Calculate holding costs
    for storage in final_state.network.storages
        for product in final_state.network.products
            if haskey(final_state.inventory_history, (storage, product))
                storage_holding_cost = sum(final_state.inventory_history[(storage, product)]) * 
                    storage.products[product]
                holding_costs += storage_holding_cost
                println("Holding costs for $(storage.name) - $(product.name): \$", round(storage_holding_cost, digits=2))
            end
        end
    end
    
    # Calculate lost sales costs
    for ((customer, product), quantity) in final_state.lost_sales
        for demand in final_state.network.demands
            if demand.customer == customer && demand.product == product
                cost = quantity * demand.lost_sales_cost
                lost_sales_costs += cost
                println("Lost sales costs for $(customer.region) - $(product.name): \$", round(cost, digits=2))
            end
        end
    end
    
    transportation_costs = final_state.total_costs - holding_costs - lost_sales_costs
    
    println("\nTotal Holding Costs: \$", round(holding_costs, digits=2))
    println("Total Lost Sales Costs: \$", round(lost_sales_costs, digits=2))
    println("Total Transportation Costs: \$", round(transportation_costs, digits=2))
    
    return final_state
end

# Run the simulation
final_state = run_simulation() 
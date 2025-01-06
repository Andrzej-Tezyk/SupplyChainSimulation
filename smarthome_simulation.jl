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
    revenue::Float64
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
        0.0,
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
                
                # Add daily holding costs to total costs
                daily_holding_cost = current_level * storage.products[product]
                state.total_costs += daily_holding_cost
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
            # Try to fulfill from any storage
            for storage in state.network.storages
                if haskey(state.inventory, (storage, demand.product)) && 
                   state.inventory[(storage, demand.product)] >= current_demand
                    state.inventory[(storage, demand.product)] -= current_demand
                    # Add revenue separately instead of subtracting from costs
                    state.revenue += current_demand * demand.sales_price
                    fulfilled = true
                    break
                end
            end
            
            if !fulfilled
                # Track lost sales
                key = (demand.customer, demand.product)
                state.lost_sales[key] = get(state.lost_sales, key, 0.0) + current_demand
                # Add lost sales cost
                state.total_costs += current_demand * demand.lost_sales_cost
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

# Helper functions for demand patterns
function generate_seasonal_demand(horizon::Int64; 
        base::Float64=50.0, 
        amplitude::Float64=20.0, 
        trend::Float64=0.0)  # trend is % increase per year
    demand = Float64[]
    for t in 1:horizon
        seasonal_factor = amplitude * sin(2π * t / 365)
        trend_factor = base * (trend/100) * (t/365)  # Convert yearly trend to daily
        daily_demand = base + trend_factor + seasonal_factor + rand(Poisson(5))
        push!(demand, max(0.0, daily_demand))
    end
    return demand
end

function generate_trending_demand(horizon::Int64;
        base::Float64=50.0,
        trend::Float64=0.0,  # trend is % increase per year
        noise_factor::Float64=0.2)
    demand = Float64[]
    for t in 1:horizon
        trend_factor = base * (trend/100) * (t/365)
        noise = rand(Normal(0, base * noise_factor))
        daily_demand = base + trend_factor + noise
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
    holding_costs = 0.0
    lost_sales_costs = 0.0
    transportation_costs = 0.0
    
    # Calculate holding costs - daily accumulation
    for storage in state.network.storages
        for product in state.network.products
            if haskey(state.inventory_history, (storage, product))
                # Calculate holding cost for each day
                for daily_inventory in state.inventory_history[(storage, product)]
                    holding_costs += daily_inventory * storage.products[product]
                end
            end
        end
    end
    
    # Calculate lost sales costs
    for ((customer, product), quantity) in state.lost_sales
        for demand in state.network.demands
            if demand.customer == customer && demand.product == product
                lost_sales_costs += quantity * demand.lost_sales_cost
                break
            end
        end
    end
    
    # Transportation costs are what remains from total costs
    transportation_costs = state.total_costs - holding_costs - lost_sales_costs
    
    # Create bar plot for costs
    costs_data = [holding_costs, lost_sales_costs, transportation_costs]
    
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
        key = (demand.customer, demand.product)
        total = sum(demand.quantities)  # Total demand over the horizon
        lost = get(state.lost_sales, key, 0.0)  # Total lost sales
        total_demand[key] = total
        fulfilled_demand[key] = total - lost  # Fulfilled = Total - Lost
    end
    
    # Calculate service levels
    service_levels = []
    labels = []
    
    for ((customer, product), total) in total_demand
        if total > 0
            fulfilled = fulfilled_demand[(customer, product)]
            service_level = (fulfilled / total) * 100  # Convert to percentage
            push!(service_levels, service_level)
            push!(labels, "$(customer.region)\n$(product.name)")
        end
    end
    
    # Create bar plot
    p = bar(labels,
        service_levels,
        title="Service Levels by Market and Product",
        ylabel="Service Level (%)",
        legend=false,
        rotation=45)
    
    # Add value labels
    annotate!(p, [(i, v + maximum(service_levels)*0.02, 
        text("$(round(v, digits=1))%", 8)) for (i, v) in enumerate(service_levels)])
    
    return p
end

function plot_revenue(state::SimulationState)
    # Calculate daily revenues
    daily_revenue = zeros(state.network.horizon)
    daily_confidence = zeros(state.network.horizon)
    
    # Calculate revenue and confidence interval for each day
    for t in 1:state.network.horizon
        day_revenues = Float64[]  # Store all possible revenues for this day
        
        # Calculate all possible revenue outcomes for this day
        for demand in state.network.demands
            current_demand = demand.quantities[t]
            if current_demand > 0
                push!(day_revenues, current_demand * demand.sales_price)
            end
        end
        
        # Calculate daily revenue and its confidence interval
        daily_revenue[t] = sum(day_revenues)
        if length(day_revenues) > 0
            se = std(day_revenues) / sqrt(length(day_revenues))
            daily_confidence[t] = 1.96 * se
        end
    end
    
    # Create the plot
    p = plot(
        title="Daily Revenue Over Time",
        xlabel="Time (days)",
        ylabel="Daily Revenue (\$)",
        legend=true
    )
    
    # Plot main line with confidence intervals
    plot!(p, 1:length(daily_revenue), daily_revenue, 
        ribbon=daily_confidence,
        label="Daily Revenue with 95% CI",
        color=:blue,
        linewidth=2,
        fillalpha=0.3)
    
    return p, daily_confidence
end

function plot_cumulative_revenue(state::SimulationState, daily_confidence::Vector{Float64})
    # Calculate daily revenues and cumulative revenue
    daily_revenue = zeros(state.network.horizon)
    cumulative_revenue = zeros(state.network.horizon)
    cumulative_confidence = zeros(state.network.horizon)
    
    # Calculate revenue for each day
    for t in 1:state.network.horizon
        for demand in state.network.demands
            current_demand = demand.quantities[t]
            if current_demand > 0
                fulfilled = false
                for storage in state.network.storages
                    if haskey(state.inventory, (storage, demand.product)) && 
                       state.inventory[(storage, demand.product)] >= current_demand
                        fulfilled = true
                        break
                    end
                end
                
                if fulfilled
                    daily_revenue[t] += current_demand * demand.sales_price
                end
            end
        end
    end
    
    # Calculate cumulative revenue and confidence intervals
    cumulative_revenue[1] = daily_revenue[1]
    cumulative_confidence[1] = daily_confidence[1]
    
    for t in 2:state.network.horizon
        cumulative_revenue[t] = cumulative_revenue[t-1] + daily_revenue[t]
        # Sum up the confidence intervals
        cumulative_confidence[t] = sum(daily_confidence[1:t])  # Direct sum for cumulative CI
    end
    
    # Create the plot
    p = plot(
        title="Cumulative Revenue Over Time",
        xlabel="Time (days)",
        ylabel="Cumulative Revenue (\$)",
        legend=true
    )
    
    # Plot main line with confidence intervals
    plot!(p, 1:length(cumulative_revenue), cumulative_revenue, 
        ribbon=cumulative_confidence,
        label="Cumulative Revenue with 95% CI",
        color=:blue,
        linewidth=2,
        fillalpha=0.3)
    
    return p
end

# Create simulation instance
function run_simulation()
    # Create products with original prices
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

    # Add demands to network with different patterns
    demands = [
        # Smart Thermostat
        Demand(eu_market, smart_thermostat, 
            generate_seasonal_demand(horizon, base=60.0, amplitude=20.0, trend=10.0), 
            300.0, 20.0),
        
        # Security Camera
        Demand(us_market, security_camera,
            generate_trending_demand(horizon, base=50.0, trend=5.0, noise_factor=0.1),
            250.0, 15.0),
        
        # Smart Lighting
        Demand(asia_market, smart_lighting,
            generate_trending_demand(horizon, base=70.0, trend=0.0, noise_factor=0.1),
            200.0, 10.0)
    ]

    for demand in demands
        add_demand!(network, demand)
    end

    # Original ordering policies
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
    p5, daily_confidence = plot_revenue(final_state)
    p6 = plot_cumulative_revenue(final_state, daily_confidence)
    
    # Save individual plots
    savefig(p1, ".\\plots\\inventory_levels.png")
    savefig(p2, ".\\plots\\demand_patterns.png")
    savefig(p3, ".\\plots\\costs_breakdown.png")
    savefig(p4, ".\\plots\\service_levels.png")
    savefig(p5, ".\\plots\\revenue.png")
    savefig(p6, ".\\plots\\cumulative_revenue.png")
    
    # Create and save combined plots
    combined_plot1 = plot(p1, p2, p3, p4, layout=(2,2), size=(1200,800))
    combined_plot2 = plot(p5, p6, layout=(2,1), size=(1200,800))
    
    savefig(combined_plot1, ".\\plots\\supply_chain_analysis1.png")
    savefig(combined_plot2, ".\\plots\\supply_chain_analysis2.png")
    
    display(combined_plot1)
    display(combined_plot2)
    
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
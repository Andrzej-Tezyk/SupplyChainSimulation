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

struct SimulationParameters
    # Product parameters
    product_prices::Dict{String, Float64}  # Base prices for products
    sales_prices_markup::Float64  # Markup percentage for sales prices
    lost_sales_cost_ratio::Float64  # Ratio of lost sales cost to base price
    
    # Inventory parameters
    initial_inventory::Float64  # Initial inventory for each product
    holding_cost_rates::Dict{String, Float64}  # Holding cost rates by product
    
    # Ordering parameters
    reorder_point::Float64  # s in (s,S) policy
    order_up_to::Float64  # S in (s,S) policy
    
    # Transportation parameters
    transport_fixed_costs::Dict{String, Float64}  # Fixed costs by distance type
    transport_unit_costs::Dict{String, Float64}  # Unit costs by distance type
    transport_times::Dict{String, Int64}  # Transport times by distance type
    
    # Demand parameters
    base_demand::Dict{String, Float64}  # Base demand by product
    seasonal_amplitude::Float64  # Amplitude for seasonal patterns
    trend_percentage::Float64  # Yearly trend percentage
    noise_factor::Float64  # Noise factor for demand variation
end

# Default parameters
function default_parameters()
    SimulationParameters(
        # Product parameters
        Dict("Smart Thermostat" => 200.0, "Security Camera" => 150.0, "Smart Lighting" => 100.0),
        1.5,  # 50% markup
        0.1,  # 10% of base price for lost sales cost
        
        # Inventory parameters
        100.0,  # Initial inventory
        Dict("Smart Thermostat" => 0.5, "Security Camera" => 0.7, "Smart Lighting" => 0.3),
        
        # Ordering parameters
        50.0,   # Reorder point
        200.0,  # Order up to level
        
        # Transportation parameters
        Dict("short" => 1000.0, "medium" => 2000.0, "long" => 2500.0),
        Dict("short" => 10.0, "medium" => 20.0, "long" => 25.0),
        Dict("short" => 5, "medium" => 15, "long" => 20),
        
        # Demand parameters
        Dict("Smart Thermostat" => 60.0, "Security Camera" => 50.0, "Smart Lighting" => 70.0),
        20.0,   # Seasonal amplitude
        10.0,   # Trend percentage
        0.1     # Noise factor
    )
end

# Create parameter variations for each set
function get_product_parameters_higher()
    base = default_parameters()
    return SimulationParameters(
        Dict("Smart Thermostat" => 300.0, "Security Camera" => 225.0, "Smart Lighting" => 150.0),  # 50% higher
        2.0,  # Higher markup (100% vs 50%)
        0.15, # Higher lost sales cost ratio
        base.initial_inventory,
        base.holding_cost_rates,
        base.reorder_point,
        base.order_up_to,
        base.transport_fixed_costs,
        base.transport_unit_costs,
        base.transport_times,
        base.base_demand,
        base.seasonal_amplitude,
        base.trend_percentage,
        base.noise_factor
    )
end

function get_product_parameters_lower()
    base = default_parameters()
    return SimulationParameters(
        Dict("Smart Thermostat" => 100.0, "Security Camera" => 75.0, "Smart Lighting" => 50.0),  # 50% lower
        1.25,  # Lower markup (25% vs 50%)
        0.05,  # Lower lost sales cost ratio
        base.initial_inventory,
        base.holding_cost_rates,
        base.reorder_point,
        base.order_up_to,
        base.transport_fixed_costs,
        base.transport_unit_costs,
        base.transport_times,
        base.base_demand,
        base.seasonal_amplitude,
        base.trend_percentage,
        base.noise_factor
    )
end

function get_inventory_parameters_higher()
    base = default_parameters()
    return SimulationParameters(
        base.product_prices,
        base.sales_prices_markup,
        base.lost_sales_cost_ratio,
        200.0,  # Double initial inventory
        Dict("Smart Thermostat" => 0.75, "Security Camera" => 1.05, "Smart Lighting" => 0.45),  # 50% higher
        base.reorder_point,
        base.order_up_to,
        base.transport_fixed_costs,
        base.transport_unit_costs,
        base.transport_times,
        base.base_demand,
        base.seasonal_amplitude,
        base.trend_percentage,
        base.noise_factor
    )
end

function get_inventory_parameters_lower()
    base = default_parameters()
    return SimulationParameters(
        base.product_prices,
        base.sales_prices_markup,
        base.lost_sales_cost_ratio,
        50.0,  # Half initial inventory
        Dict("Smart Thermostat" => 0.25, "Security Camera" => 0.35, "Smart Lighting" => 0.15),  # 50% lower
        base.reorder_point,
        base.order_up_to,
        base.transport_fixed_costs,
        base.transport_unit_costs,
        base.transport_times,
        base.base_demand,
        base.seasonal_amplitude,
        base.trend_percentage,
        base.noise_factor
    )
end

function get_ordering_parameters_higher()
    base = default_parameters()
    return SimulationParameters(
        base.product_prices,
        base.sales_prices_markup,
        base.lost_sales_cost_ratio,
        base.initial_inventory,
        base.holding_cost_rates,
        75.0,   # 50% higher reorder point
        300.0,  # 50% higher order up to
        base.transport_fixed_costs,
        base.transport_unit_costs,
        base.transport_times,
        base.base_demand,
        base.seasonal_amplitude,
        base.trend_percentage,
        base.noise_factor
    )
end

function get_ordering_parameters_lower()
    base = default_parameters()
    return SimulationParameters(
        base.product_prices,
        base.sales_prices_markup,
        base.lost_sales_cost_ratio,
        base.initial_inventory,
        base.holding_cost_rates,
        25.0,   # 50% lower reorder point
        100.0,  # 50% lower order up to
        base.transport_fixed_costs,
        base.transport_unit_costs,
        base.transport_times,
        base.base_demand,
        base.seasonal_amplitude,
        base.trend_percentage,
        base.noise_factor
    )
end

function get_transport_parameters_higher()
    base = default_parameters()
    return SimulationParameters(
        base.product_prices,
        base.sales_prices_markup,
        base.lost_sales_cost_ratio,
        base.initial_inventory,
        base.holding_cost_rates,
        base.reorder_point,
        base.order_up_to,
        Dict("short" => 1500.0, "medium" => 3000.0, "long" => 3750.0),  # 50% higher
        Dict("short" => 15.0, "medium" => 30.0, "long" => 37.5),  # 50% higher
        Dict("short" => 7, "medium" => 22, "long" => 30),  # 40% longer
        base.base_demand,
        base.seasonal_amplitude,
        base.trend_percentage,
        base.noise_factor
    )
end

function get_transport_parameters_lower()
    base = default_parameters()
    return SimulationParameters(
        base.product_prices,
        base.sales_prices_markup,
        base.lost_sales_cost_ratio,
        base.initial_inventory,
        base.holding_cost_rates,
        base.reorder_point,
        base.order_up_to,
        Dict("short" => 500.0, "medium" => 1000.0, "long" => 1250.0),  # 50% lower
        Dict("short" => 5.0, "medium" => 10.0, "long" => 12.5),  # 50% lower
        Dict("short" => 3, "medium" => 10, "long" => 14),  # 30% faster
        base.base_demand,
        base.seasonal_amplitude,
        base.trend_percentage,
        base.noise_factor
    )
end

function get_demand_parameters_higher()
    base = default_parameters()
    return SimulationParameters(
        base.product_prices,
        base.sales_prices_markup,
        base.lost_sales_cost_ratio,
        base.initial_inventory,
        base.holding_cost_rates,
        base.reorder_point,
        base.order_up_to,
        base.transport_fixed_costs,
        base.transport_unit_costs,
        base.transport_times,
        Dict("Smart Thermostat" => 90.0, "Security Camera" => 75.0, "Smart Lighting" => 105.0),  # 50% higher
        30.0,   # 50% higher seasonal amplitude
        15.0,   # 50% higher trend
        0.15    # 50% higher noise
    )
end

function get_demand_parameters_lower()
    base = default_parameters()
    return SimulationParameters(
        base.product_prices,
        base.sales_prices_markup,
        base.lost_sales_cost_ratio,
        base.initial_inventory,
        base.holding_cost_rates,
        base.reorder_point,
        base.order_up_to,
        base.transport_fixed_costs,
        base.transport_unit_costs,
        base.transport_times,
        Dict("Smart Thermostat" => 30.0, "Security Camera" => 25.0, "Smart Lighting" => 35.0),  # 50% lower
        10.0,   # 50% lower seasonal amplitude
        5.0,    # 50% lower trend
        0.05    # 50% lower noise
    )
end

# Run all sensitivity analyses
function run_all_sensitivity_analyses()
    # Create base case
    println("Running base case simulation...")
    run_simulation(default_parameters(), "./plots/base")
    
    # Run sensitivity analyses
    sensitivity_cases = [
        ("product_higher", get_product_parameters_higher()),
        ("product_lower", get_product_parameters_lower()),
        ("inventory_higher", get_inventory_parameters_higher()),
        ("inventory_lower", get_inventory_parameters_lower()),
        ("ordering_higher", get_ordering_parameters_higher()),
        ("ordering_lower", get_ordering_parameters_lower()),
        ("transport_higher", get_transport_parameters_higher()),
        ("transport_lower", get_transport_parameters_lower()),
        ("demand_higher", get_demand_parameters_higher()),
        ("demand_lower", get_demand_parameters_lower())
    ]
    
    for (case_name, params) in sensitivity_cases
        println("Running sensitivity analysis for: ", case_name)
        output_dir = "./plots/sens/$case_name"
        run_simulation(params, output_dir)
    end
end

# Run all analyses
run_all_sensitivity_analyses() 
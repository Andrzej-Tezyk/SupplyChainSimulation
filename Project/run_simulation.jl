include("supply_chain_simulation.jl")

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
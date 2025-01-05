mutable struct SimulationState
    network::SupplyChainNetwork
    current_time::Int64
    inventory::Dict{Tuple{Storage, Product}, Float64}
    pending_orders::Vector{Order}
    fulfilled_orders::Vector{Order}
    lost_sales::Dict{Tuple{Customer, Product}, Float64}
    total_costs::Float64
end

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
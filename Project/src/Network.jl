mutable struct SupplyChainNetwork
    horizon::Int64
    suppliers::Vector{Supplier}
    storages::Vector{Storage}
    customers::Vector{Customer}
    products::Vector{Product}
    lanes::Vector{Lane}
    demands::Vector{Demand}
end

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
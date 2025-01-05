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
    inventory::Dict{Product, Float64}   # Product -> quantity
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
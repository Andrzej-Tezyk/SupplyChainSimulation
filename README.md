# SmartHome Supply Chain Simulation

**University Project**

## Project Overview
This project implements a supply chain simulation for SmartHome Innovations, a global provider of smart home technologies. The simulation models a multi-period, multi-product supply chain network under varying demand conditions and delivery times.

## Key Features
- Multi-echelon supply chain network modeling
- Multiple product types (Smart Thermostats, Security Cameras, Smart Lighting)
- Dynamic demand patterns with seasonality and trends
- Flexible transportation network with varying costs and times
- Inventory management with (s,S) ordering policies
- Service level and cost analysis
- Revenue tracking and visualization
- Comprehensive sensitivity analysis framework

## Network Structure
The simulation includes:
- **Manufacturers**: USA and Asia factories
- **Distribution Centers**: Europe, North America, and Asia-Pacific
- **Markets**: European, US, and Asian markets

## Analysis Capabilities
- Inventory level tracking
- Demand pattern visualization
- Cost breakdown analysis
- Service level monitoring
- Revenue analysis with confidence intervals
- Sensitivity analysis for:
  - Product parameters
  - Inventory parameters
  - Ordering parameters
  - Transportation parameters
  - Demand parameters

## Visualization
The simulation generates comprehensive visualizations saved in:
- `./plots/base/` for base scenario
- `./plots/sens/` for sensitivity analyses

## Implementation
Built in Julia using:
- Distributions.jl
- Plots.jl
- Statistics.jl

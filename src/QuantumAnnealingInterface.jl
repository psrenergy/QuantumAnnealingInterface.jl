module QuantumAnnealingInterface

using LinearAlgebra
using QuantumAnnealing
import QUBODrivers:
    MOI,
    QUBODrivers,
    QUBOTools,
    Sample,
    SampleSet,
    @setup,
    sample,
    ising

@setup Optimizer begin
    name       = "Simulated Quantum Annealer"
    sense      = :min
    domain     = :spin
    version    = v"0.2.0"
    attributes = begin
        "num_reads"::Integer                                     = 1_000
        "annealing_time"::Float64                                = 1.0
        "annealing_schedule"::QuantumAnnealing.AnnealingSchedule = QuantumAnnealing.AS_LINEAR
        "steps"::Integer                                         = 0
        "order"::Integer                                         = 4
        "mean_tol"::Float64                                      = 1E-6
        "max_tol"::Float64                                       = 1E-4
        "iteration_limit"::Integer                               = 100
        "state_steps"::Union{Integer,Nothing}                    = nothing
    end
end

const ATTR_LIST = [
    :steps,
    :order,
    :mean_tol,
    :max_tol,
    :iteration_limit,
    :state_steps,
]

function sample(sampler::Optimizer{T}) where {T}
    # Retrieve Model
    h, J, α, β  = ising(sampler, Dict)
    ising_model = merge(h, J)

    # Retrieve Attributes
    n                  = MOI.get(sampler, MOI.NumberOfVariables())
    m                  = MOI.get(sampler, MOI.RawOptimizerAttribute("num_reads"))
    silent             = MOI.get(sampler, MOI.Silent())
    annealing_time     = MOI.get(sampler, MOI.RawOptimizerAttribute("annealing_time"))
    annealing_schedule = MOI.get(sampler, MOI.RawOptimizerAttribute("annealing_schedule"))
    
    attrs = Dict{Symbol,Any}(
        attr => MOI.get(
            sampler,
            MOI.RawOptimizerAttribute(string(attr))
        )
        for attr in ATTR_LIST
    )

    # Run simulation
    results = @timed QuantumAnnealing.simulate(
        ising_model,
        annealing_time,
        annealing_schedule;
        silence=silent,
        attrs...
    )
    simulation_time = results.time

    # Measurement & Probabilities
    ρ = results.value
    P = cumsum(real.(diag(ρ)))

    # Sample states
    results = @timed sample_states(P, h, J, α, β, n, m)
    samples = results.value

    sampling_time = results.time

    # Write metadata
    metadata = Dict{String,Any}(
        "origin" => "Quantum Annealing Simulation",
        "time"   => Dict{String,Any}(
            "sampling"   => sampling_time,
            "simulation" => simulation_time,
            "effective"  => simulation_time + sampling_time,
        ),
    )

    return SampleSet{T}(samples, metadata)
end

function sample_states(
    P::Vector{Float64},
    h::Dict{Int,T},
    J::Dict{Tuple{Int,Int},T},
    α::T,
    β::T,
    n::Integer,
    m::Integer,
) where {T}
    samples = Vector{Sample{T,Int}}(undef, m)

    for i = 1:m
        ψ = sample_state(P, n)
        λ = QUBOTools.value(h, J, ψ, α, β)

        samples[i] = Sample{T}(ψ, λ)
    end

    return samples
end

function sample_state(P::Vector{Float64}, n::Integer)
    # Sample p ~ [0, 1]
    p = rand()

    # Run Binary Search
    i = first(searchsorted(P, p))

    # Format as spin vector i.e. ψ ∈ {±1}ⁿ
    ψ = 2 * digits(Int, i - 1; base=2, pad=n) .- 1

    return ψ
end

end # module

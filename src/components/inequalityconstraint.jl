mutable struct InequalityConstraint{T,N,Nc,Cs} <: AbstractConstraint{T,N}
    id::Int64
    name::String

    constraints::Cs
    pid::Int64
    # bodyid::Int64

    s0::SVector{N,T}
    s1::SVector{N,T}
    γ0::SVector{N,T}
    γ1::SVector{N,T}
    

    function InequalityConstraint(data...; name::String="")
        bounddata = Tuple{Bound,Int64}[]
        for info in data
            if typeof(info[1]) <: Bound
                push!(bounddata, info)
            else
                for subinfo in info
                    push!(bounddata, subinfo)
                end
            end
        end

        T = getT(bounddata[1][1])

        pid = bounddata[1][2]
        bodyids = Int64[]
        constraints = Bound{T}[]
        N = 0
        for set in bounddata
            push!(constraints, set[1])
            @assert set[2] == pid
            N += getNc(set[1])
        end
        constraints = Tuple(constraints)
        Nc = length(constraints)

        s0 = ones(T, N)
        s1 = ones(T, N)
        γ0 = ones(T, N)
        γ1 = ones(T, N)

<<<<<<< HEAD
        new{T,N,Nc,typeof(constraints)}(getGlobalID(), constraints, pid, s0, s1, γ0, γ1)
=======
        new{T,N,typeof(constraints)}(getGlobalID(), name, constraints, pid, s0, s1, γ0, γ1)
>>>>>>> master
    end
end


Base.length(::InequalityConstraint{T,N}) where {T,N} = N

function resetVars!(ineqc::InequalityConstraint{T,N}) where {T,N}
    ineqc.s0 = @SVector ones(T, N)
    ineqc.s1 = @SVector ones(T, N)
    ineqc.γ0 = @SVector ones(T, N)
    ineqc.γ1 = @SVector ones(T, N)

    return 
end


<<<<<<< HEAD
function g(ineqc::InequalityConstraint{T,N,1}, mechanism) where {T,N}
    g(ineqc.constraints[1], getbody(mechanism, ineqc.pid), mechanism.Δt, mechanism.No)
end

function g2(ineqc::InequalityConstraint{T,N,1}, mechanism) where {T,N}
    g2(ineqc.constraints[1], getbody(mechanism, ineqc.pid), mechanism.Δt, mechanism.No)
end

@generated function g(ineqc::InequalityConstraint{T,N,Nc}, mechanism) where {T,N,Nc}
    vec = [:(g(ineqc.constraints[$i], getbody(mechanism, ineqc.pid), mechanism.Δt, mechanism.No)) for i = 1:Nc]
    :(SVector{N,T}($(vec...)))
end

function gs(ineqc::InequalityConstraint{T,N,1}, mechanism) where {T,N}
    g(ineqc.constraints[1], getbody(mechanism, ineqc.pid), mechanism.Δt, mechanism.No) - ineqc.s1[1]
end

@generated function gs(ineqc::InequalityConstraint{T,N,Nc}, mechanism) where {T,N,Nc}
    vec = [:(g(ineqc.constraints[$i], getbody(mechanism, ineqc.pid), mechanism.Δt, mechanism.No)) for i = 1:Nc]
    :(SVector{N,T}($(vec...)) - ineqc.s1)
=======
function g(mechanism, ineqc::InequalityConstraint{T,1}) where {T}
    g(ineqc.constraints[1], getbody(mechanism, ineqc.pid), mechanism.Δt, mechanism.No)
end

@generated function g(mechanism, ineqc::InequalityConstraint{T,N}) where {T,N}
    vec = [:(g(ineqc.constraints[$i], getbody(mechanism, ineqc.pid), mechanism.Δt, mechanism.No)) for i = 1:N]
    :(SVector{N,T}($(vec...)))
end

function gs(mechanism, ineqc::InequalityConstraint{T,1}) where {T}
    g(ineqc.constraints[1], getbody(mechanism, ineqc.pid), mechanism.Δt, mechanism.No) - ineqc.s1[1]
end

@generated function gs(mechanism, ineqc::InequalityConstraint{T,N}) where {T,N}
    vec = [:(g(ineqc.constraints[$i], getbody(mechanism, ineqc.pid), mechanism.Δt, mechanism.No) - ineqc.s1[$i]) for i = 1:N]
    :(SVector{N,T}($(vec...)))
>>>>>>> master
end

function h(ineqc::InequalityConstraint)
    ineqc.s1 .* ineqc.γ1
end

function hμ(ineqc::InequalityConstraint{T}, μ) where T
    ineqc.s1 .* ineqc.γ1 .- μ
end


<<<<<<< HEAD
function schurf(ineqc::InequalityConstraint{T,N,Nc}, body, mechanism) where {T,N,Nc}
=======
function schurf(mechanism, ineqc::InequalityConstraint{T,N}, body) where {T,N}
>>>>>>> master
    val = @SVector zeros(T, 6)
    for i = 1:Nc
        val += schurf(ineqc, ineqc.constraints[i], i, body, mechanism.μ, mechanism.Δt, mechanism.No, mechanism)
    end
    return val
end

function schurD(ineqc::InequalityConstraint{T,N,Nc}, body, Δt) where {T,N,Nc}
    val = @SMatrix zeros(T, 6, 6)
    for i = 1:Nc
        val += schurD(ineqc, ineqc.constraints[i], i, body, Δt)
    end
    return val
end

<<<<<<< HEAD
@generated function ∂g∂pos(ineqc::InequalityConstraint{T,N,Nc}, body, mechanism) where {T,N,Nc}
    vec = [:(∂g∂pos(ineqc.constraints[$i], mechanism.No)) for i = 1:Nc]
    :(vcat($(vec...)))
end

@generated function ∂g∂vel(ineqc::InequalityConstraint{T,N,Nc}, body, mechanism) where {T,N,Nc}
    vec = [:(∂g∂vel(ineqc.constraints[$i], mechanism.Δt, mechanism.No)) for i = 1:Nc]
=======
@generated function ∂g∂pos(mechanism, ineqc::InequalityConstraint{T,N}, body) where {T,N}
    vec = [:(∂g∂pos(ineqc.constraints[$i], mechanism.No)) for i = 1:N]
    :(vcat($(vec...)))
end

@generated function ∂g∂vel(mechanism, ineqc::InequalityConstraint{T,N}, body) where {T,N}
    vec = [:(∂g∂vel(ineqc.constraints[$i], mechanism.Δt, mechanism.No)) for i = 1:N]
>>>>>>> master
    :(vcat($(vec...)))
end
mutable struct EqualityConstraint{T,N,Nc,Cs} <: AbstractConstraint{T,N}
    id::Int64
    name::String
    active::Bool

    constraints::Cs
    parentid::Union{Int64,Nothing}
    childids::SVector{Nc,Int64}
    inds::SVector{Nc,SVector{2,Int64}} # indices for minimal coordinates, assumes joints

    λsol::Vector{SVector{N,T}}

    function EqualityConstraint(data...; name::String="")
        jointdata = Tuple{Joint,Int64,Int64}[]
        for info in data
            if info[1] isa Joint
                push!(jointdata, info)
            else
                for subinfo in info
                    push!(jointdata, subinfo)
                end
            end
        end

        T = getT(jointdata[1][1])# .T

        parentid = jointdata[1][2]
        childids = Int64[]
        constraints = Joint{T}[]
        inds = Vector{Int64}[]
        N = 0
        for set in jointdata
            push!(constraints, set[1])
            @assert set[2] == parentid
            push!(childids, set[3])

            Nset = getN(set[1])
            if isempty(inds)
                push!(inds, [1;3-Nset])
            else
                push!(inds, [last(inds)[2]+1;last(inds)[2]+3-Nset])
            end
            N += Nset
        end
        constraints = Tuple(constraints)
        Nc = length(constraints)
        

        λsol = [zeros(T, N) for i=1:2]

        new{T,N,Nc,typeof(constraints)}(getGlobalID(), name, true, constraints, parentid, childids, inds, λsol)
    end
end


function setPosition!(mechanism, eqc::EqualityConstraint, xθ; iter::Bool = true)
    if !iter
        _setPosition!(mechanism, eqc, xθ)
    else
        currentvals = minimalCoordinates(mechanism)
        _setPosition!(mechanism, eqc, xθ)
        for id in recursivedirectchildren!(mechanism.graph, eqc.id)
            component = getcomponent(mechanism, id)
            if component isa EqualityConstraint
                _setPosition!(mechanism, component, currentvals[id])
            end
        end
    end

    return
end

# TODO make zero alloc
# TODO currently assumed constraints are in order and only joints which is the case unless very low level constraint setting
function _setPosition!(mechanism, eqc::EqualityConstraint{T,N,Nc}, xθ) where {T,N,Nc}
    @assert length(xθ)==3*Nc-N
    n = Int64(Nc/2)
    body1 = getbody(mechanism, eqc.parentid)
    for i = 1:n
        body2 = getbody(mechanism, eqc.childids[i])
        Δx = getPositionDelta(eqc.constraints[i], body1, body2, xθ[SUnitRange(eqc.inds[i][1],eqc.inds[i][2])]) 
        Δq = getPositionDelta(eqc.constraints[i+1], body1, body2, xθ[SUnitRange(eqc.inds[i+1][1],eqc.inds[i+1][2])])
        
        p1, p2 = eqc.constraints[i].vertices
        setPosition!(body1, body2; p1 = p1, p2 = p2, Δx = Δx, Δq = Δq)
    end
    return
end

# TODO make zero alloc
# TODO currently assumed constraints are in order and only joints which is the case unless very low level constraint setting
function setVelocity!(mechanism, eqc::EqualityConstraint{T,N,Nc}, vω) where {T,N,Nc}
    @assert length(vω)==3*Nc-N
    n = Int64(Nc/2)
    body1 = getbody(mechanism, eqc.parentid)
    for i = 1:n
        body2 = getbody(mechanism, eqc.childids[i])
        Δv = getVelocityDelta(eqc.constraints[i], body1, body2, vω[SUnitRange(eqc.inds[i][1],eqc.inds[i][2])])
        Δω = getVelocityDelta(eqc.constraints[i+1], body1, body2, vω[SUnitRange(eqc.inds[i+1][1],eqc.inds[i+1][2])])
        
        p1, p2 = eqc.constraints[i].vertices
        setVelocity!(body1, body2; p1 = p1, p2 = p2, Δv = Δv, Δω = Δω)
    end
    return
end

# TODO make zero alloc
function setForce!(mechanism, eqc::EqualityConstraint{T,N,Nc}, Fτ::AbstractVector) where {T,N,Nc}
    @assert length(Fτ)==3*Nc-N
    for i = 1:Nc
        setForce!(eqc.constraints[i], getbody(mechanism, eqc.parentid), getbody(mechanism, eqc.childids[i]),  Fτ[SUnitRange(eqc.inds[i][1],eqc.inds[i][2])])
    end
    return
end

@generated function minimalCoordinates(mechanism, eqc::EqualityConstraint{T,N,Nc}) where {T,N,Nc}
    vec = [:(minimalCoordinates(eqc.constraints[$i], getbody(mechanism, eqc.parentid), getbody(mechanism, eqc.childids[$i]))) for i = 1:Nc]
    return :(svcat($(vec...)))
end

@inline function GtλTof!(mechanism, body::Body, eqc::EqualityConstraint)
    isactive(eqc) && (body.state.d -= zerodimstaticadjoint(∂g∂ʳpos(mechanism, eqc, body.id)) * eqc.λsol[2])
    return
end

@generated function g(mechanism, eqc::EqualityConstraint{T,N,Nc}) where {T,N,Nc}
    vec = [:(g(eqc.constraints[$i], getbody(mechanism, eqc.parentid), getbody(mechanism, eqc.childids[$i]), mechanism.Δt)) for i = 1:Nc]
    return :(svcat($(vec...)))
end
@generated function gc(mechanism, eqc::EqualityConstraint{T,N,Nc}) where {T,N,Nc}
    vec = [:(g(eqc.constraints[$i], getbody(mechanism, eqc.parentid), getbody(mechanism, eqc.childids[$i]))) for i = 1:Nc]
    return :(svcat($(vec...)))
end

@inline function ∂g∂ʳpos(mechanism, eqc::EqualityConstraint, id::Integer)
    id == eqc.parentid ? (return ∂g∂ʳposa(mechanism, eqc, id)) : (return ∂g∂ʳposb(mechanism, eqc, id))
end

@inline function ∂g∂ʳvel(mechanism, eqc::EqualityConstraint, id::Integer)
    id == eqc.parentid ? (return ∂g∂ʳvela(mechanism, eqc, id)) : (return ∂g∂ʳvelb(mechanism, eqc, id))
end

@generated function ∂g∂ʳposa(mechanism, eqc::EqualityConstraint{T,N,Nc}, id::Integer) where {T,N,Nc}
    vec = [:(∂g∂ʳposa(eqc.constraints[$i], getbody(mechanism, id), getbody(mechanism, eqc.childids[$i]))) for i = 1:Nc]
    return :(vcat($(vec...)))
end
@generated function ∂g∂ʳposb(mechanism, eqc::EqualityConstraint{T,N,Nc}, id::Integer) where {T,N,Nc}
    vec = [:(∂g∂ʳposb(eqc.constraints[$i], getbody(mechanism, eqc.parentid), getbody(mechanism, id))) for i = 1:Nc]
    return :(vcat($(vec...)))
end

@generated function ∂g∂ʳvela(mechanism, eqc::EqualityConstraint{T,N,Nc}, id::Integer) where {T,N,Nc}
    vec = [:(∂g∂ʳvela(eqc.constraints[$i], getbody(mechanism, id), getbody(mechanism, eqc.childids[$i]), mechanism.Δt)) for i = 1:Nc]
    return :(vcat($(vec...)))
end
@generated function ∂g∂ʳvelb(mechanism, eqc::EqualityConstraint{T,N,Nc}, id::Integer) where {T,N,Nc}
    vec = [:(∂g∂ʳvelb(eqc.constraints[$i], getbody(mechanism, eqc.parentid), getbody(mechanism, id), mechanism.Δt)) for i = 1:Nc]
    return :(vcat($(vec...)))
end

@generated function ∂Fτ∂ua(mechanism, eqc::EqualityConstraint{T,N,Nc}, id) where {T,N,Nc}
    vec = [:(∂Fτ∂ua(eqc.constraints[$i], getbody(mechanism, id))) for i = 1:Nc]
    return :(hcat($(vec...)))
end
@generated function ∂Fτ∂ub(mechanism, eqc::EqualityConstraint{T,N,Nc}, id) where {T,N,Nc}
    vec = [:(∂Fτ∂ub(eqc.constraints[$i], getbody(mechanism, eqc.parentid), getbody(mechanism, id))) for i = 1:Nc]
    return :(hcat($(vec...)))
end

# Derivatives NOT accounting for quaternion specialness

function ∂g∂posc(mechanism, eqc::EqualityConstraint, id::Integer)
    id == eqc.parentid ? (return ∂g∂posac(mechanism, eqc, id)) : (return ∂g∂posbc(mechanism, eqc, id))
end

function ∂g∂posac(mechanism, eqc::EqualityConstraint{T,N,Nc}, id::Integer) where {T,N,Nc}
    vec = [hcat(∂g∂posac(eqc.constraints[i], getbody(mechanism, id), getbody(mechanism, eqc.childids[i]))) for i = 1:Nc]
    return vcat(vec...)
end
function ∂g∂posbc(mechanism, eqc::EqualityConstraint{T,N,Nc}, id::Integer) where {T,N,Nc}
    vec = [hcat(∂g∂posbc(eqc.constraints[i], getbody(mechanism, eqc.parentid), getbody(mechanism, id))) for i = 1:Nc]
    return vcat(vec...)
end
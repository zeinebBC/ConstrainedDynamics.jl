mutable struct Mechanism{T,N}
    tend::T
    steps::Base.OneTo{Int64}
    dt::T
    g::T
    No::Int64

    origin::Origin{T}
    bodies::UnitDict{Base.OneTo{Int64},Body{T}}
    eqconstraints::UnitDict{UnitRange{Int64},<:EqualityConstraint{T}}
    ineqconstraints::UnitDict{UnitRange{Int64},<:InequalityConstraint{T}}

    #TODO remove once EqualityConstraint is homogenous
    normf::T
    normΔs::T

    graph::Graph{N}

    ldu::SparseLDU{T}
    storage::Storage{T}

    μ::Float64
    αmax::Float64

    #TODO no constraints input
    function Mechanism(origin::Origin{T},bodies::Vector{Body{T}},
        eqcs::Vector{<:EqualityConstraint{T}}, ineqcs::Vector{<:InequalityConstraint{T}};
        tend::T=10., dt::T=.01, g::T=-9.81, No=2) where T


        resetGlobalID()

        Nb = length(bodies)
        Ne = length(eqcs)
        Ni = length(ineqcs)
        N = Nb+Ne
        steps = Int(ceil(tend/dt))

        currentid = 1

        bdict = Dict{Int64,Int64}()
        for (ind,body) in enumerate(bodies)
            push!(body.x, [body.x[1] for i=1:No-1]...)
            push!(body.q, [body.q[1] for i=1:No-1]...)
            push!(body.F, [body.F[1] for i=1:No-1]...)
            push!(body.τ, [body.τ[1] for i=1:No-1]...)

            for c in eqcs
                c.pid == body.id && (c.pid = currentid)
                for (ind,bodyid) in enumerate(c.bodyids)
                    if bodyid == body.id
                        c.bodyids = setindex(c.bodyids,currentid,ind)
                        c.constraints[ind].cid = currentid
                    end
                end
            end

            for c in ineqcs
                c.pid == body.id && (c.pid = currentid)
            end

            body.id = currentid
            currentid+=1

            bdict[body.id] = ind
        end

        eqdict = Dict{Int64,Int64}()
        for (ind,c) in enumerate(eqcs)
            c.id = currentid
            currentid+=1

            eqdict[c.id] = ind
        end

        ineqdict = Dict{Int64,Int64}()
        for (ind,c) in enumerate(ineqcs)
            c.id = currentid
            currentid+=1

            ineqdict[c.id] = ind
        end

        normf = zero(T)
        normΔs = zero(T)

        graph = Graph(origin,bodies,eqcs,ineqcs)
        ldu = SparseLDU(graph,bodies,eqcs,ineqcs,bdict,eqdict,ineqdict)

        storage = Storage{T}(steps,Nb,Ne)

        bodies = UnitDict(bodies)
        eqcs = UnitDict((eqcs[1].id):(eqcs[Ne].id),eqcs)
        if !isempty(ineqcs)
            ineqcs = UnitDict((ineqcs[1].id):(ineqcs[Ni].id),ineqcs)
        else
            ineqcs = UnitDict(0:0,ineqcs)
        end
        new{T,N}(tend,Base.OneTo(steps),dt,g,No,origin,bodies,eqcs,ineqcs,normf,normΔs,graph,ldu,storage,1,1)
    end

    function Mechanism(origin::Origin{T},bodies::Vector{Body{T}};
        tend::T=10., dt::T=.01, g::T=-9.81, No=2) where T

        constraints = EqualityConstraint{T}[] # Vector{EqualityConstraint{T}}(undef,0)
        for body in bodies
            push!(constraints,EqualityConstraint(OriginConnection(origin,body)))
        end
        Mechanism(origin,bodies,constraints,tend=tend, dt=dt, g=g, No=No)
    end

    function Mechanism(origin::Origin{T},bodies::Vector{Body{T}},constraints::Vector{<:EqualityConstraint{T}};
        tend::T=10., dt::T=.01, g::T=-9.81, No=2) where T

        ineqconstraints = InequalityConstraint{T}[] # Vector{InequalityConstraint{T}}(undef,0)
        Mechanism(origin,bodies,constraints,ineqconstraints,tend=tend, dt=dt, g=g, No=No)
    end
end

function Base.show(io::IO, mime::MIME{Symbol("text/plain")}, M::Mechanism{T}) where {T}
    summary(io, M); println(io, " with ", length(M.bodies), " bodies and ", length(M.eqconstraints), " constraints")
end

function setentries!(mechanism::Mechanism)
    graph = mechanism.graph
    ldu = mechanism.ldu

    for (id,body) in pairs(mechanism.bodies)
        for cid in directchildren(graph,id)
            setLU!(getentry(ldu,(id,cid)),id,geteqconstraint(mechanism,cid),mechanism)
        end

        diagonal = getentry(ldu,id)
        setDandΔs!(diagonal,body,mechanism)
        for cid in ineqchildren(graph,id)
            extendDandΔs!(diagonal,body,getineqconstraint(mechanism,cid),mechanism)
        end
    end

    for node in mechanism.eqconstraints
        id = node.id

        for cid in directchildren(graph,id)
            setLU!(getentry(ldu,(id,cid)),node,cid,mechanism)
        end

        for cid in loopchildren(graph,id)
            setLU!(getentry(ldu,(id,cid)))
        end

        diagonal = getentry(ldu,id)
        setDandΔs!(diagonal,node,mechanism)
    end
end

@inline getbody(mechanism::Mechanism,id::Int64) = mechanism.bodies[id]
@inline getbody(mechanism::Mechanism,id::Nothing) = mechanism.origin
@inline geteqconstraint(mechanism::Mechanism,id::Int64) = mechanism.eqconstraints[id]
@inline getineqconstraint(mechanism::Mechanism,id::Int64) = mechanism.ineqconstraints[id]

# @inline function getnode(mechanism::Mechanism,id::Int64) # should only be used in setup
#      if haskey(mechanism.bdict,id)
#          return getbody(mechanism,id)
#      elseif haskey(mechanism.cdict,id)
#          return getconstraint(mechanism,id)
#      elseif id == mechanism.originid
#          return mechanism.origin
#      else
#          error("not found.")
#      end
#  end

@inline function normf(body::Body{T},mechanism::Mechanism) where T
    f = dynamics(body,mechanism)
    return dot(f,f)
end

@inline function normf(c::EqualityConstraint,mechanism::Mechanism)
    f = g(c,mechanism)
    return dot(f,f)
end

@inline function normf(ineqc::InequalityConstraint,mechanism::Mechanism)
    f = gs(ineqc,mechanism)
    d = h(ineqc)
    return dot(f,f)+dot(d,d)
end

@inline function normfμ(ineqc::InequalityConstraint,mechanism::Mechanism)
    f = gs(ineqc,mechanism)
    d = hμ(ineqc,mechanism.μ)
    return dot(f,f)+dot(d,d)
end

@inline function GtλTof!(body::Body,eqc::EqualityConstraint,mechanism)
    body.f -= ∂g∂pos(eqc,body.id,mechanism)'*eqc.s1
    return
end

@inline function NtγTof!(body::Body,ineqc::InequalityConstraint,mechanism)
    body.f -= ∂g∂pos(ineqc,body,mechanism)'*ineqc.γ1

    # impact = ineqc.constraints
    # g = 9.81
    # cf = impact.cf
    # dt = mechanism.dt
    #
    # Nx = SVector{6,Float64}(0,0,1,0,0,0)'
    # Nv = dt*Nx
    # D = Float64[1 0 0 0 0 0;0 1 0 0 0 0]
    #
    # s1 = body.s1
    # γ1 = ineqc.γ1[1]
    # sl1 = ineqc.s1[1]
    #
    # Dv = D*s1
    #
    #
    # body.f -= Nx'*γ1
    #
    # ezg = SVector{3,Float64}(0,0,-mechanism.g)
    # b = D[:,1:3]*(body.m*(( - getv1(body,dt))/dt + ezg) - body.F[2])
    #
    # if norm(b)>0
    #     b = b/norm(b)*minimum([norm(b);cf*γ1])
    # end
    #
    # body.f -= D'*b

    return
end

@inline function normf(mechanism::Mechanism)
    mechanism.normf = 0

    for body in mechanism.bodies
        mechanism.normf += normf(body,mechanism)
    end
    foreach(addNormf!,mechanism.eqconstraints,mechanism)
    foreach(addNormf!,mechanism.ineqconstraints,mechanism)
    # for ineqc in mechanism.ineqconstraints
    #     mechanism.normf += normf(ineqc,mechanism)
    # end

    return sqrt(mechanism.normf)
end

@inline function meritf(mechanism::Mechanism)
    mechanism.normf = 0

    for body in mechanism.bodies
        mechanism.normf += normf(body,mechanism)
    end
    foreach(addNormf!,mechanism.eqconstraints,mechanism)
    foreach(addNormfμ!,mechanism.ineqconstraints,mechanism)
    # for ineqc in mechanism.ineqconstraints
    #     mechanism.normf += normfμ(ineqc,mechanism)
    # end

    return sqrt(mechanism.normf)
end

@inline function normΔs(mechanism::Mechanism)
    mechanism.normΔs = 0

    mechanism.normΔs += mapreduce(normΔs,+,mechanism.bodies)
    foreach(addNormΔs!,mechanism.eqconstraints,mechanism)
    foreach(addNormΔs!,mechanism.ineqconstraints,mechanism)

    return sqrt(mechanism.normΔs)
end

@inline function addNormf!(ineqc::InequalityConstraint,mechanism::Mechanism)
    mechanism.normf += normf(ineqc,mechanism)
    return
end

@inline function addNormfμ!(ineqc::InequalityConstraint,mechanism::Mechanism)
    mechanism.normf += normfμ(ineqc,mechanism)
    return
end

@inline function addNormf!(eqc::EqualityConstraint,mechanism::Mechanism)
    mechanism.normf += normf(eqc,mechanism)
    return
end

@inline function addNormΔs!(component::Component,mechanism::Mechanism)
    mechanism.normΔs += normΔs(component)
    return
end

function computeα!(mechanism::Mechanism)
    ldu = mechanism.ldu

    τ = 0.995
    # αmax = 1.
    mechanism.αmax = 1.

    for ineqc in mechanism.ineqconstraints
        computeα!(ineqc,getineq(ldu,ineqc.id),τ,mechanism)
        # Δs = getineq(ldu,ineqc.id).Δs
        # Δγ = getineq(ldu,ineqc.id).Δγ

        # for (i,el) in enumerate(Δs)
        #     if el > 0
        #         temp = minimum([1.;τ*ineqc.s1[i]/el])
        #         αmax = minimum([αmax;temp])
        #     end
        # end

        # for (i,el) in enumerate(Δγ)
        #     if el > 0
        #         temp = minimum([1.;τ*ineqc.γ1[i]/el])
        #         αmax = minimum([αmax;temp])
        #     end
        # end
    end

    # mechanism.αmax = αmax

    return
end

function computeα!(ineqc::InequalityConstraint,ineqentry::InequalityEntry,τ, mechanism)
    findminforα!(ineqc.s1,ineqentry.Δs,τ,mechanism)
    findminforα!(ineqc.γ1,ineqentry.Δγ,τ,mechanism)
    return
end

function findminforα!(sγ1::SVector{N,T},Δsγ::SVector{N,T},τ,mechanism) where {N,T}
    for i=1:N
        temp = τ*sγ1[i]/Δsγ[i]
        (temp > 0) && (temp < mechanism.αmax) && (mechanism.αmax = temp)
    end

    return 
end

function saveToTraj!(mechanism::Mechanism,t)
    No = mechanism.No
    for (ind,body) in enumerate(mechanism.bodies)
        mechanism.storage.x[ind][t]=body.x[No]
        mechanism.storage.q[ind][t]=body.q[No]
    end
    for (ind,constraint) in enumerate(mechanism.eqconstraints)
        mechanism.storage.λ[ind][t]=constraint.s1
    end
end

@inline function updatePos!(body::Body,dt)
    x2 = body.x[2]
    q2 = body.q[2]
    body.x[1] = x2
    body.x[2] = x2 + getvnew(body)*dt
    body.q[1] = q2
    body.q[2] = dt/2*(Lmat(q2)*ωbar(body,dt))
    return
end


function simulate!(mechanism::Mechanism;save::Bool=false,debug::Bool=false,disp::Bool=false)
    bodies = mechanism.bodies
    constraints = mechanism.eqconstraints
    dt = mechanism.dt
    foreach(s0tos1!,bodies)
    foreach(s0tos1!,constraints)

    for i=mechanism.steps
        newton!(mechanism,warning=debug)
        save && saveToTraj!(mechanism,i)
        foreach(updatePos!,bodies,dt)

        disp && (i*dt)%1<dt*(1.0-.1) && display(i*dt)
    end
    return
end

function simulate_ip!(mechanism::Mechanism;save::Bool=false,debug::Bool=false,disp::Bool=false)
    bodies = mechanism.bodies
    eqcs = mechanism.eqconstraints
    ineqcs = mechanism.ineqconstraints
    dt = mechanism.dt
    foreach(s0tos1!,bodies)
    foreach(s0tos1!,eqcs)
    foreach(s0tos1!,ineqcs)

    for i=mechanism.steps
        # newton!(mechanism,warning=debug)
        # newton_ip!(mechanism,bodies[1])
        newton_ip!(mechanism,warning=debug)
        save && saveToTraj!(mechanism,i)
        foreach(updatePos!,bodies,dt)

        disp && (i*dt)%1<dt*(1.0-.1) && display(i*dt)
    end
    return
end


function plotθ(mechanism::Mechanism{T},id) where T
    n = length(mechanism.bodies)
    θ = zeros(T,n,length(mechanism.steps))
    for i=1:n
        qs = mechanism.storage.q[i]
        for (t,q) in enumerate(qs)
            θ[i,t] = angleaxis(q)[1]*sign(angleaxis(q)[2][1])
        end
    end

    p = plot(collect(0:mechanism.dt:mechanism.tend-mechanism.dt),θ[id[1],:])
    for ind in Iterators.rest(id,2)
        plot!(collect(0:mechanism.dt:mechanism.tend-mechanism.dt),θ[ind,:])
    end
    return p
end

function plotλ(mechanism::Mechanism{T},id) where T
    n = sum(length.(mechanism.eqconstraints))
    λ = zeros(T,n,length(mechanism.steps))
    startpos = 1
    endpos = 0
    for i=1:length(mechanism.eqconstraints)
        endpos = startpos + length(mechanism.eqconstraints[i]) -1

        λs = mechanism.storage.λ[i]
        for (t,val) in enumerate(λs)
            λ[startpos:endpos,t] = val
        end

        startpos = endpos + 1
    end

    p = plot(collect(0:mechanism.dt:mechanism.tend-mechanism.dt),λ[id[1],:])
    for ind in Iterators.rest(id,2)
        plot!(collect(0:mechanism.dt:mechanism.tend-mechanism.dt),λ[ind,:])
    end
    return p
end

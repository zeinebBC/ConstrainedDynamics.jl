mutable struct Friction{T,Nc} <: Bound{T,Nc}
    Nx::Adjoint{T,SVector{6,T}}
    D::SMatrix{2,6,T,12}
    cf::T
    offset::SVector{6,T}


    function Friction(body::Body{T}, normal::AbstractVector{T}, cf::T;offset::AbstractVector{T} = zeros(3)) where T
        @assert cf>0
        normal = normal / norm(normal)

        # Derived from plane equation a*v1 + b*v2 + distance*v3 = p - offset
        A = Array(svd(skew(normal)).V) # gives two plane vectors
        A[:,3] = normal # to ensure correct sign
        Ainv = inv(A)
        ainv3 = Ainv[3,:]
        Nx = [ainv3;0;0;0]'
        D = [A[:,1:2];zeros(3,2)]'
        offset = [offset;0;0;0]

        new{T,2}(Nx, D, cf, offset), body.id
    end
end


@inline function g(ineqc, friction::Friction, body::Body, Δt, No)
    γ1 = ineqc.γ1[1]
    [
        friction.Nx[SVector(1, 2, 3)]' * (getx3(body, Δt) - friction.offset[SVector(1, 2, 3)])
        friction.cf * γ1 - body.β1
    ]
        body.β1^2 - body.b1'*body.b1
end

@inline function g2(ineqc, friction::Friction, body::Body, Δt, No)
    body.β1^2 - body.b1'*body.b1
end


function Bfc(ineqc, friction::Friction, body::Body, Δt)
    D = friction.D
    M = getM(body)
    cf = friction.cf

    γ1 = ineqc.γ1[1]
    ψ1 = ineqc.γ1[2]
    s21 = ineqc.s1[2]
    b1 = body.b1
    β1 = body.β1

    ψ1/β1*(I + (β1-s21)/(β1^2*s21) * b1*b1')
end

function Xinvfc(ineqc, friction::Friction, body::Body, Δt)
    γ1 = ineqc.γ1[1]
    ψ1 = ineqc.γ1[2]
    s11 = ineqc.s1[1]
    s21 = ineqc.s1[2]
    cf = friction.cf

    [
        γ1/s11 0
        -γ1*ψ1*cf/(s11*s21) ψ1/s21
    ]
end
function extendeddgdpos(ineqc, friction::Friction{T}, body::Body, Δt) where T
    D = friction.D
    B = Bfc(ineqc,friction,body, Δt)

    b1 = body.b1
    β1 = body.β1

    [friction.Nx' -1/β1*D'/B*b1]
end

<<<<<<< HEAD
@inline ∂g∂pos(friction::Friction{T}, No) where T = [friction.Nx;(@SVector zeros(T,6))']
@inline ∂g∂vel(friction::Friction{T}, Δt, No) where T = [friction.Nx * Δt;(@SVector zeros(T,6))']

@inline function schurf(ineqc, friction::Friction, i, body::Body, μ, Δt, No, mechanism)
    ci = g(friction, body, Δt, No)
=======
# Direct stuff
@inline function setFrictionForce!(mechanism, ineqc, friction::Friction, i, body::Body)
    No = mechanism.No
    cf = friction.cf
    γ1 = ineqc.γ1[i]
>>>>>>> master
    D = friction.D

    γ1 = ineqc.γ1
    b1 = body.b1
    β1 = body.β1
    Dv = D*body.s1

<<<<<<< HEAD
    Xinv = Xinvfc(ineqc, friction, body, Δt)
    B = Bfc(ineqc,friction,body, Δt)
    Nxtext = extendeddgdpos(ineqc, friction, body, Δt)
    

    return 1/2*D'*b1 + Nxtext * Xinv * (ci - μ./γ1 + 1/(2*β1)*[0;1]*g2(ineqc,friction,body, Δt, No)) + D'/B*(Dv*Δt + γ1[2]/β1*b1)
end

@inline function schurD(ineqc, friction::Friction, i, body::Body, Δt)
    D = friction.D

    Xinv = Xinvfc(ineqc, friction, body, Δt)
    B = Bfc(ineqc,friction,body, Δt)
    Nxtext = extendeddgdpos(ineqc, friction, body, Δt)

    return Nxtext * Xinv * ∂g∂vel(friction, Δt, 2) + D'/B*D*Δt
end
=======
    f = body.f
    v = body.s1
    body.s1 = @SVector zeros(6)
    dyn = dynamics(mechanism, body)
    body.s1 = v
    body.f = f

    b0 = D*dyn

    if norm(b0) > cf*γ1
        friction.b = b0/norm(b0)*cf*γ1
    else
        friction.b = b0
    end

    B = D'*friction.b
    F += B[SVector(1,2,3)]
    τ += B[SVector(4,5,6)]
    setForce!(body,F,τ,No)
    
    return
end

# # Smooth stuff
# @inline function setFrictionForce!(mechanism, ineqc, friction::Friction, i, body::Body)
#     Δt = mechanism.Δt
#     No = mechanism.No
#     M = getM(body)
#     v = body.s1
#     cf = friction.cf
#     γ1 = ineqc.γ1[i]
#     D = friction.D

#     B = D'*friction.b
#     F = body.F[No] - B[SVector(1,2,3)]
#     τ = body.τ[No] - B[SVector(4,5,6)]
#     setForce!(body,F,τ,No)

#     ψ = Δt*norm(D*v)
    
#     f = body.f
#     body.s1 = @SVector zeros(6)
#     dyn = D/M*dynamics(body,mechanism)*Δt^2
#     body.s1 = v
#     body.f = f
    
#     X = D/M*D' * Δt^2 + I*(ψ/(cf*γ1))

#     friction.b = X\dyn
#     B = D'*friction.b
#     F += B[SVector(1,2,3)]
#     τ += B[SVector(4,5,6)]
#     setForce!(body,F,τ,No)
#     return
# end
>>>>>>> master

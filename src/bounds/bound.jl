abstract type Bound{T,Nc} end

Base.show(io::IO, bound::Bound) = summary(io, bound)

getT(bound::Bound{T}) where T = T
getNc(bound::Bound{T,Nc}) where {T,Nc} = Nc


@inline g(bound::Bound{T}) where T = zero(T)

@inline ∂g∂pos(bound::Bound{T}) where T = @SVector zeros(T, 6)
@inline ∂g∂vel(bound::Bound{T}) where T = @SVector zeros(T, 6)
@inline schurf(bound::Bound{T}) where T = @SVector zeros(T, 6)
@inline schurD(bound::Bound{T}) where T = @SMatrix zeros(T, 6, 6)


using RecipesBase

struct SampledSignal{U,T} <: AbstractArray{U,1}
    samples::AbstractVector{U}
    stepsize::T
    offset::T
end

"""
sampledsignal(ValueType, numsamples, stepsize, offset)
sampledsignal(f, axis)
"""
sampledsignal(U,n,dt,t0) = SampledSignal(zeros(U,n),dt,t0)
sampledsignal(f,axis) = SampledSignal(f.(axis),axis[2]-axis[1],axis[1])
sampledsignal(U::Type,axis) = sampledsignal(U, length(axis), stepsize(axis), offset(axis))
sampledsignal(axis::AbstractRange, samples::AbstractArray) = SampledSignal(samples, stepsize(axis), offset(axis))

Base.size(signal::SampledSignal) = size(signal.samples)
Base.length(signal::SampledSignal) = length(signal.samples)
Base.eltype(signal::SampledSignal) = eltype(signal.samples)
Base.getindex(signal::SampledSignal, i) = signal.samples[i]
Base.setindex!(signal::SampledSignal, v, i) = (signal.samples[i] = v)

Base.:/(s::SampledSignal, a::Number) = SampledSignal(s.samples./a, s.stepsize, s.offset)
Base.:*(a::Number, s::SampledSignal) = SampledSignal(a.*s.samples, s.stepsize, s.offset)

LinearAlgebra.norm(s::SampledSignal) = sqrt(stepsize(axis(s))) * LinearAlgebra.norm(samples(s))

stepsize(signal::SampledSignal) = signal.stepsize
offset(signal::SampledSignal) = signal.offset
axis(signal::SampledSignal) = axis(offset(signal), stepsize(signal), length(signal))
support(signal::SampledSignal) = first(axis(signal)) : last(axis(signal))
samples(signal::SampledSignal) = signal.samples

RecipesBase.@recipe f(s::SampledSignal) = (axis(s), samples(s))


function Base.:+(s1::SampledSignal, s2::SampledSignal)

    T = promote_type(eltype(s1), eltype(s2))

    @assert stepsize(s1) ≈ stepsize(s2)
    Δt = stepsize(s1)

    rel_offset = offset(s1) - offset(s2)
    frac_part = abs(round(Int,rel_offset/Δt)*Δt - rel_offset)
    @assert frac_part < 1e3*eps(eltype(T))

    # if offset(s2) < offset(s1)
    #     @warn "Support extended to the left!"
    #     @show offset(s1) offset(s2) Δt
    # end
    #
    # if offset(s1)+(length(s1)-1)*Δt < offset(s2)+(length(s2)-1)*Δt
    #     @warn "Support extended to the right!"
    #     @show offset(s1)+(length(s1)-1)*Δt
    #     @show offset(s2)+(length(s2)-1)*Δt
    #     @show Δt
    # end

    t0 = min(offset(s1), offset(s2))
    t1 = max(offset(s1)+(length(s1)-1)*Δt, offset(s2)+(length(s2)-1)*Δt)

    n = round(Int, (t1-t0)/Δt) + 1
    s = sampledsignal(T,n,Δt,t0)

    for i in 1:length(s1)
        t = offset(s1) + (i-1)*Δt
        j = round(Int,(t-t0)/Δt) + 1
        s.samples[j] += s1.samples[i]
    end

    for i in 1:length(s2)
        t = offset(s2) + (i-1)*Δt
        j = round(Int,(t-t0)/Δt) + 1
        s.samples[j] += s2.samples[i]
    end

    return s
end

function add!(s1::SampledSignal, s2::SampledSignal)

    tol = 1e4*eps(eltype(s1))

    @assert stepsize(s1) ≈ stepsize(s2)
    h = stepsize(s1)

    r = abs(offset(s1)-offset(s2))/h
    i = round(Int,r)
    @assert abs(r-i) < tol

    @assert first(axis(s2)) >= first(axis(s1)) - tol
    @assert last(axis(s1)) + tol >= last(axis(s2))

    t0 = first(axis(s1))
    for i in eachindex(s2)
        t = offset(s2) + (i-1)*h
        j = round(Int, (t-t0)/h) + 1
        s1.samples[j] += s2.samples[i]
    end

    return s1
end

Base.:-(s1::SampledSignal, s2::SampledSignal) = (s1 + (-1.0)*s2)


#struct SignalBCS <: Broadcast.BroadcastStyle end
Base.BroadcastStyle(::Type{<:SampledSignal}) = Broadcast.ArrayStyle{SampledSignal}()
function Base.similar(bc::Broadcast.Broadcasted{Broadcast.ArrayStyle{SampledSignal}}, ::Type{ElType}) where ElType
    s = find_first_signal(bc)
    SampledSignal(similar(Array{ElType}, axes(bc)), s.stepsize, s.offset)
end

find_first_signal(bc::Base.Broadcast.Broadcasted) = find_first_signal(bc.args)
find_first_signal(args::Tuple) = find_first_signal(find_first_signal(args[1]), Base.tail(args))
find_first_signal(x) = x
find_first_signal(a::SampledSignal, rest) = a
find_first_signal(::Any, rest) = find_first_signal(rest)


function differentiate(s::SampledSignal)
    ax1 = axis(s)
    Δx = stepsize(ax1)
    x0 = offset(ax1)
    n = length(ax1)
    ax2 = range(x0 + 0.5Δx, step=Δx, length=n-1)
    samples1 = samples(s)
    samples2 = (samples1[2:end] - samples1[1:end-1])/Δx
    sampledsignal(ax2, samples2)
end

function differentiate2(s::SampledSignal)
    h = step(axis(s))
    a = samples(s)
    b = similar(a)
    b[1] = (a[2])/(2h)
    b[end] = (-a[end-1])/(2h)
    for i in eachindex(a)[2:end-1]
        b[i] = (a[i+1]-a[i-1])/(2h)
    end
    return sampledsignal(axis(s), b)
end


function restrict(s::SampledSignal, ax::AbstractRange)
    ax1 = axis(s)
    x0 = first(ax1)
    #@assert first(ax1) <= first(ax)
    #@assert last(ax) <= last(ax1)
    @assert stepsize(ax) ≈ stepsize(ax1)
    Δx = stepsize(ax)
    i0 = max(1, round(Int, (first(ax)-first(ax1))/Δx) + 1)
    i0 = min(i0, length(ax1))
    i1 = min(length(samples(s)), round(Int, (last(ax)-first(ax1))/Δx) + 1)
    i1 = max(i1, 1)
    # @show round(Int, (first(ax)-first(ax1))/Δx) + 1
    # @show round(Int, (last(ax)-first(ax1))/Δx) + 1
    # @show i0 i1
    @assert i0 <= i1
    ax2 = range(x0+(i0-1)*Δx, step=Δx, length=i1-i0+1)
    @assert length(ax2) == (i1-i0+1)
    sampledsignal(ax2, samples(s)[i0:i1])
end


const SomeFunction = Union{TimeDomainFunction, FrequencyDomainFunction, Function}
function mul!(f::SomeFunction, s::SampledSignal)
    for (i,x) in enumerate(axis(s))
        samples(s)[i] *= f(x)
    end
    return s
end

function Base.:*(f::SomeFunction, s::SampledSignal)
    s2 = deepcopy(s)
    mul!(f,s2)
end

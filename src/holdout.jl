"""
    holdout([rng], N, T, λvals, ρvals, [weights,] xDistsTest, xDistsTrain,
            noiseDist, signalModels, kernelgenerator; showprogress)
    holdout([rng], N, T, λvals, ρvals, [weights,] xDistsTest, νDistsTest,
            xDistsTrain, νDistsTrain, noiseDist, signalModels, kernelgenerator;
            showprogress)

Select λ and ρ via a holdout process.

# Arguments
- `rng::AbstractRNG = Random.GLOBAL_RNG`: Random number generator to use
- `N::Integer`: Number of test points
- `T::Integer`: Number of training points
- `λvals::AbstractVector{<:Real}`: Values of λ to search over \\[nλ\\]
- `ρvals::AbstractVector{<:Real}`: Values of ρ to search over \\[nρ\\]
- `weights::AbstractVector{<:Real}`: Weights for calculating holdout cost
  \\[L\\]; omit if L = 1
- `xDistsTest`: Distributions of latent parameters \\[L\\] or scalar (if L = 1);
  `xDists` can be any object such that `rand(xDists, ::Integer)` is defined (or
  a collection of such objects)
- `νDistsTest`: Distributions of known parameters \\[K\\] or scalar (if K = 1);
  `νDists` can be any object such that `rand(νDists, ::Integer)` is defined (or
  a collection of such objects); omit this parameter if K = 0
- `xDistsTrain`: Distributions of latent parameters \\[L\\] or scalar
  (if L = 1); `xDists` can be any object such that `rand(xDists, ::Integer)` is
  defined (or a collection of such objects)
- `νDistsTrain`: Distributions of known parameters \\[K\\] or scalar (if K = 1);
  `νDists` can be any object such that `rand(νDists, ::Integer)` is defined (or
  a collection of such objects); omit this parameter if K = 0
- `noiseDist`: Distribution of noise (assumes same noise distribution for both
  real and imaginary channels in complex case); `noiseDist` can be any object
  such that `rand(noiseDist, ::Integer)` is defined
- `signalModels::Union{<:Function,<:AbstractVector{<:Function}}`: Signal models
  used to generate noiseless data \\[numSignalModels\\]; each signal model
  accepts as inputs L latent parameters (scalars) first, then K known parameters
  (scalars); user-defined parameters (e.g., scan parameters in MRI) should be
  built into the signal model
- `kernelgenerator::Function`: Function that creates a `Kernel` object given a
  vector `Λ` of lengthscales
- `showprogress::Bool = false`: Whether to show progress

## Note
- L is the number of unknown or latent parameters to be estimated
- K is the number of known parameters
- nλ is the number of λ values to try
- nρ is the number of ρ values to try

# Return
- `λ::Real`: Bandwidth scaling parameter
- `ρ::Real`: Tikhonov regularization parameter
- `Ψ::AbstractMatrix{<:Real}`: Holdout costs for λvals and ρvals [nλ,nρ]
"""
function holdout(
    rng::AbstractRNG,
    N::Integer,
    T::Integer,
    λvals::AbstractVector{<:Real},
    ρvals::AbstractVector{<:Real},
    weights::AbstractVector{<:Real},
    xDistsTest::AbstractVector,
    xDistsTrain::AbstractVector,
    noiseDist,
    signalModels::Union{<:Function,<:AbstractArray{<:Function,1}},
    kernelgenerator::Function;
    showprogress::Bool = false
)

    # Make sure length of weights matches xDistsTest and xDistsTrain
    length(weights) == length(xDistsTest) == length(xDistsTrain) ||
        throw(DimensionMismatch("lengths of weights, xDistsTest, and " *
                                "xDistsTrain should be the same"))

    # Generate synthetic test data
    (y, x) = generatenoisydata(rng, N, xDistsTest, noiseDist, signalModels)
    (ytrain, xtrain) = generatenoisydata(rng, T, xDistsTrain, noiseDist,
                                         signalModels)

    # Loop through each value of λ and ρ
    nλ = length(λvals)
    nρ = length(ρvals)
    Ψ  = zeros(nλ, nρ)
    for idxλ = 1:nλ

        showprogress && println("idxλ = $idxλ/$nλ")

        λ = λvals[idxλ]

        # Generate length scales
        if ndims(y) == 1 || size(y, 1) == 1
            Λ = λ * max(mean(abs.(y)), eps()) # scalar (D = 1)
        else
            Λ = λ * max.(dropdims(mean(abs.(y), dims = 2), dims = 2), eps()) # [D]
        end

        # Create the kernel
        kernel = kernelgenerator(Λ)

        for idxρ = 1:nρ

            showprogress && println("    idxρ = $idxρ/$nρ")

            ρ = ρvals[idxρ]

            # Train PERK
            trainData = PERK.krr_train(rng, xtrain, ytrain, kernel, ρ)

            # Run PERK
            xhat = perk(y, trainData, kernel) # [L,N]

            # Calculate Ψ(λ,ρ), the holdout cost
            werr = ((xhat - x) ./ x) .* sqrt.(weights) # [L,N]
            Ψ[idxλ,idxρ] = sqrt(norm(werr) / N)

        end

    end

    # Return values of λ and ρ that minimize Ψ
    (idxλ, idxρ) = Tuple(argmin(Ψ))
    λ = λvals[idxλ]
    ρ = ρvals[idxρ]

    return (λ, ρ, Ψ)

end

function holdout(
    rng::AbstractRNG,
    N::Integer,
    T::Integer,
    λvals::AbstractVector{<:Real},
    ρvals::AbstractVector{<:Real},
    weights::AbstractVector{<:Real},
    xDistsTest::AbstractVector,
    νDistsTest,
    xDistsTrain::AbstractVector,
    νDistsTrain,
    noiseDist,
    signalModels::Union{<:Function,<:AbstractArray{<:Function,1}},
    kernelgenerator::Function;
    showprogress::Bool = false
)

    # Make sure length of weights matches xDistsTest and xDistsTrain
    length(weights) == length(xDistsTest) == length(xDistsTrain) ||
        throw(DimensionMismatch("lengths of weights, xDistsTest, and " *
                                "xDistsTrain should be the same"))

    # Make sure lengths of νDistsTest and νDistsTrain match
    length(νDistsTest) == length(νDistsTrain) ||
        throw(DimensionMismatch("lengths of νDistsTest and νDistsTrain " *
                                "should be the same"))

    # Generate synthetic test data and training data
    (y, x, ν) = generatenoisydata(rng, N, xDistsTest, νDistsTest, noiseDist,
                                  signalModels)
    (ytrain, xtrain, νtrain) = generatenoisydata(rng, T, xDistsTrain,
                                           νDistsTrain, noiseDist, signalModels)

    # Combine y and ν
    q = combine(y, ν) # [D+K,N]
    qtrain = combine(ytrain, νtrain) # [D+K,T]

    # Loop through each value of λ and ρ
    nλ = length(λvals)
    nρ = length(ρvals)
    Ψ  = zeros(nλ, nρ)
    for idxλ = 1:nλ

        showprogress && println("idxλ = $idxλ/$nλ")

        λ = λvals[idxλ]

        # Generate length scales
        Λ = λ * max.(dropdims(mean(abs.(q), dims = 2), dims = 2), eps()) # [D+K]

        # Create the kernel
        kernel = kernelgenerator(Λ)

        for idxρ = 1:nρ

            showprogress && println("    idxρ = $idxρ/$nρ")

            ρ = ρvals[idxρ]

            # Train PERK
            trainData = PERK.krr_train(rng, xtrain, qtrain, kernel, ρ)

            # Run PERK
            xhat = perk(y, ν, trainData, kernel) # [L,N]

            # Calculate Ψ(λ,ρ), the holdout cost
            werr = ((xhat - x) ./ x) .* sqrt.(weights) # [L,N]
            Ψ[idxλ,idxρ] = sqrt(norm(werr) / N)

        end

    end

    # Return values of λ and ρ that minimize Ψ
    (idxλ, idxρ) = Tuple(argmin(Ψ))
    λ = λvals[idxλ]
    ρ = ρvals[idxρ]

    return (λ, ρ, Ψ)

end

function holdout(
    rng::AbstractRNG,
    N::Integer,
    T::Integer,
    λvals::AbstractVector{<:Real},
    ρvals::AbstractVector{<:Real},
    xDistsTest,
    xDistsTrain,
    noiseDist,
    signalModels::Union{<:Function,<:AbstractArray{<:Function,1}},
    kernelgenerator::Function;
    showprogress::Bool = false
)

    weights = [1]
    holdout(rng, N, T, λvals, ρvals, weights, [xDistsTest], [xDistsTrain],
            noiseDist, signalModels, kernelgenerator,
            showprogress = showprogress)

end

function holdout(
    rng::AbstractRNG,
    N::Integer,
    T::Integer,
    λvals::AbstractVector{<:Real},
    ρvals::AbstractVector{<:Real},
    xDistsTest,
    νDistsTest,
    xDistsTrain,
    νDistsTrain,
    noiseDist,
    signalModels::Union{<:Function,<:AbstractArray{<:Function,1}},
    kernelgenerator::Function;
    showprogress::Bool = false
)

    weights = [1]
    holdout(rng, N, T, λvals, ρvals, weights, [xDistsTest], νDistsTest,
            [xDistsTrain], νDistsTrain, noiseDist, signalModels,
            kernelgenerator, showprogress = showprogress)

end

holdout(N::Integer, args...) = holdout(Random.GLOBAL_RNG, N, args...)

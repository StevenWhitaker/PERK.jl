"""
    krr_train(xtrain, ytrain, kernel, ρ, [f, phase])

Train kernel ridge regression.

# Arguments
- `xtrain::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}}`: Latent
  parameters for training data [L,T] or \\[T\\] (if L = 1)
- `ytrain::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}}`: Features
  for training data [Q,T] or \\[T\\] (if Q = 1)
- `kernel::Kernel`: Kernel to use
- `ρ::Real`: Tikhonov regularization parameter
- `f::Union{<:AbstractVector{<:Real},AbstractMatrix{<:Real}} = randn(kernel.H, Q)`:
  Unscaled random frequency values [H,Q] or \\[H\\] (if Q = 1) (used when
  `kernel isa RFFKernel`)
- `phase::AbstractVector{<:Real} = rand(kernel.H)`: Random phase values \\[H\\]
  (used when `kernel isa RFFKernel`)

## Note
- L is the number of unknown or latent parameters to be predicted
- Q is the number of observed features per training sample
- T is the number of training samples
- H is approximation order for kernels that use random Fourier features

# Return
- `trainData::TrainingData`: `TrainingData` object to be passed to `krr`
"""
function krr_train(
    xtrain::AbstractVector{<:Real},
    ytrain::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    kernel::ExactKernel,
    ρ::Real
)

    T = promote_type(Float64, eltype(xtrain), eltype(ytrain))
    Ty = typeof(ytrain)
    if Ty <: AbstractVector
        trainingdata = ExactTrainingData(Ty, T, length(ytrain))
    else
        trainingdata = ExactTrainingData(Ty, T, size(ytrain)...)
    end
    krr_train!(trainingdata, xtrain, ytrain, kernel, ρ)
    return trainingdata

end

function krr_train!(
    trainingdata::ExactTrainingData,
    xtrain::AbstractVector{<:Real},
    ytrain::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    kernel!::ExactKernel,
    ρ::Real
)

    # Grab the number of training points
    T = length(xtrain)

    # Evaluate the kernel on the training features
    kernel!(trainingdata.K, ytrain, ytrain) # [T,T]

    # Calculate the sample mean and de-mean the latent parameters
    trainingdata.xm[] = mean(xtrain) # scalar (L = 1)
    trainingdata.x .= xtrain .- trainingdata.xm[] # [T]

    # De-mean the rows and columns of the kernel output
    for t = 1:T
        trainingdata.Km[t] = mean(trainingdata.K[t,i] for i = 1:T)
    end
    for t1 = 1:T
        tmp = trainingdata.Km[t1]
        for t2 = 1:T
            trainingdata.K[t1,t2] -= tmp
        end
    end
    for t2 = 1:T
        m = mean(trainingdata.K[i,t2] for i = 1:T)
        for t1 = 1:T
            trainingdata.K[t1,t2] -= m
        end
    end

    # Compute the (regularized) inverse of K and multiply by xtrain
    F = lu(transpose(trainingdata.K + T * ρ * I))
    copyto!(trainingdata.xKinv, trainingdata.x)
    ldiv!(F, trainingdata.xKinv) # [T]

    # Copy ytrain
    copyto!(trainingdata.y, ytrain)

    return nothing

end

function krr_train(
    xtrain::AbstractMatrix{<:Real},
    ytrain::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    kernel::ExactKernel,
    ρ::Real
)

    T = promote_type(Float64, eltype(xtrain), eltype(ytrain))
    Ty = typeof(ytrain)
    if Ty <: AbstractVector
        trainingdata = ExactTrainingData(Ty, T, size(xtrain)...)
    else
        trainingdata = ExactTrainingData(Ty, T, size(xtrain, 1), size(ytrain)...)
    end
    krr_train!(trainingdata, xtrain, ytrain, kernel, ρ)
    return trainingdata

end

function krr_train!(
    trainingdata::ExactTrainingData,
    xtrain::AbstractMatrix{<:Real},
    ytrain::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    kernel!::ExactKernel,
    ρ::Real
)

    # Grab the number of latent parameters and training points
    (L, T) = size(xtrain)

    # Evaluate the kernel on the training features
    kernel!(trainingdata.K, ytrain, ytrain) # [T,T]

    # Calculate the sample mean and de-mean the latent parameters
    for l = 1:L
        m = mean(xtrain[l,t] for t = 1:T)
        trainingdata.xm[l] = m
        for t = 1:T
            trainingdata.x[l,t] = xtrain[l,t] - m
        end
    end

    # De-mean the rows and columns of the kernel output
    for t = 1:T
        trainingdata.Km[t] = mean(trainingdata.K[t,i] for i = 1:T)
    end
    for t1 = 1:T
        tmp = trainingdata.Km[t1]
        for t2 = 1:T
            trainingdata.K[t1,t2] -= tmp
        end
    end
    for t2 = 1:T
        m = mean(trainingdata.K[i,t2] for i = 1:T)
        for t1 = 1:T
            trainingdata.K[t1,t2] -= m
        end
    end

    # Compute the (regularized) inverse of K and multiply by xtrain
    F = lu(trainingdata.K + T * ρ * I)
    copyto!(trainingdata.xKinv, trainingdata.x)
    rdiv!(trainingdata.xKinv, F) # [L,T]

    # Copy ytrain
    copyto!(trainingdata.y, ytrain)

    return nothing

end

function krr_train(
    xtrain::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    ytrain::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    kernel::RFFKernel,
    ρ::Real
)

    # Use random Fourier features to approximate the kernel
    (z, freq, phase) = kernel(ytrain)

    return _krr_train(xtrain, z, ρ, freq, phase)

end

function krr_train(
    xtrain::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    ytrain::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    kernel::RFFKernel,
    ρ::Real,
    f::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    phase::AbstractVector{<:Real}
)

    # Use random Fourier features to approximate the kernel
    (z, freq, phase) = kernel(ytrain, f, phase)

    return _krr_train(xtrain, z, ρ, freq, phase)

end

function _krr_train(
    xtrain::AbstractVector{<:Real}, # [T]
    z::AbstractMatrix{<:Real}, # [H,T]
    ρ::Real,
    freq::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}}, # [H,Q] or [H]
    phase::AbstractVector{<:Real} # [H]
)

    # Grab the number of training points
    T = size(z, 2)

    # Calculate sample means
    xm = mean(xtrain) # scalar (L = 1)
    zm = dropdims(mean(z, dims = 2), dims = 2) # [H]

    # Calculate sample covariances
    xtrain = xtrain .- xm # [T]
    z = z .- zm # [H,T]
    Czz = div0.(z * z', T) # [H,H]
    Cxz = div0.(z * xtrain, T) # [H]

    # Calculate the (regularized) inverse of Czz and multiply by Cxz
    CxzCzzinv = transpose(Czz + ρ * I) \ Cxz # [H]

    return RFFTrainingData(freq, phase, zm, xm, Czz, Cxz, CxzCzzinv)

end

function _krr_train(
    xtrain::AbstractMatrix{<:Real}, # [L,T]
    z::AbstractMatrix{<:Real}, # [H,T]
    ρ::Real,
    freq::Union{<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}}, # [H,Q] or [H]
    phase::AbstractVector{<:Real} # [H]
)

    # Grab the number of training points
    T = size(z, 2)

    # Calculate sample means
    xm = dropdims(mean(xtrain, dims = 2), dims = 2) # [L]
    zm = dropdims(mean(z, dims = 2), dims = 2) # [H]

    # Calculate sample covariances
    xtrain = xtrain .- xm # [L,T]
    z = z .- zm # [H,T]
    Czz = div0.(z * z', T) # [H,H]
    Cxz = div0.(xtrain * z', T) # [L,H]

    # Calculate the (regularized) inverse of Czz and multiply by Cxz
    CxzCzzinv = Cxz / (Czz + ρ * I) # [L,H]

    return RFFTrainingData(freq, phase, zm, xm, Czz, Cxz, CxzCzzinv)

end

"""
    krr(ytest, trainData, kernel)

Predict latent parameters that generated `ytest` using kernel ridge regression.

# Arguments
- `ytest::Union{<:Real,<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}}`:
  Observed test data [Q,N] or \\[N\\] (if Q = 1) or scalar (if Q = N = 1)
- `trainData::TrainingData`: Training data
- `kernel::Kernel`: Kernel to use

## Notes
- Q is the number of observed features per test sample
- N is the number of test samples

# Return
- `xhat::Union{<:Real,<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}}`:
  Estimated latent parameters [L,N] or \\[N\\] (if L = 1) or \\[L\\] (if N = 1) or
  scalar (if L = N = 1)
"""
function krr(
    ytest::Union{<:Real,<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    trainData::ExactTrainingData,
    kernel::ExactKernel
)

    k = kernel(trainData.y, ytest) # [T,N] or [T]
    k = k .- trainData.Km # [T,N] or [T]

    # Check if L = 1
    if trainData isa ExactTrainingData{<:Any,<:AbstractVector,<:Any,<:Any,<:Any,<:Any}
        xhat = trainData.xm .+ transpose(k) * trainData.xKinv # [N] or scalar
    else
        xhat = trainData.xm .+ trainData.xKinv * k # [L,N] or [L]
    end

    return xhat

end

function krr(
    ytest::Union{<:Real,<:AbstractVector{<:Real},<:AbstractMatrix{<:Real}},
    trainData::RFFTrainingData,
    ::RFFKernel
)

    z = rffmap(ytest, trainData.freq, trainData.phase) # [H,N] or [H]
    z = z .- trainData.zm # [H,N] or [H]

    # Check if L = 1
    if trainData isa RFFTrainingData{<:Any,<:Any,<:Any,<:Any,<:Any,<:AbstractVector,<:Any}
        xhat = trainData.xm .+ transpose(z) * trainData.CxzCzzinv # [N] or scalar
    else
        xhat = trainData.xm .+ trainData.CxzCzzinv * z # [L,N] or [L]
    end

    return xhat

end

"""
    perk(y, ν, T, xDists, νDists, noiseDist, signalModels, kernel, ρ)

Train PERK and then estimate latent parameters.

# Arguments
- `y::AbstractArray{<:Real,2}`: Test data points [D,N]
- `ν::AbstractArray{<:AbstractArray{<:Real,1},1}`: Known parameters [K][N]
- `T::Integer`: Number of training points
- `xDists::AbstractArray{<:Any,1}`: Distributions of latent parameters [L]
- `νDists::AbstractArray{<:Any,1}`: Distributions of known parameters [K]
- `noiseDist`: Distribution of noise (assumes same noise distribution for both
    real and imaginary channels in complex case)
- `signalModels::AbstractArray{<:Function,1}`: Signal models used to generate
	noiseless data [numSignalModels]; each signal model accepts as inputs L
	latent parameters (scalars) first, then K known parameters (scalars);
	user-defined parameters (e.g., scan parameters in MRI) should be built into
	the signal model
- `kernel::Kernel`: Kernel to use
- `ρ::Real`: Regularization parameter

# Return
- `xhat::Array{<:Real,2}`: Estimated latent parameters [L,N]
- `trainData::TrainingData`: Training data
- `ttrain::Real`: Duration of training (s)
- `ttest::Real`: Duration of testing (s)
"""
function perk(
    y::AbstractArray{<:Real,2},
    ν::AbstractArray{<:AbstractArray{<:Real,1},1},
    T::Integer,
	xDists::AbstractArray{<:Any,1},
	νDists::AbstractArray{<:Any,1},
	noiseDist,
	signalModels::AbstractArray{<:Function,1},
	kernel::Kernel,
    ρ::Real
)

    ttrain = @elapsed begin
        trainData = train(T, xDists, νDists, noiseDist, signalModels, kernel)
    end

    (xhat, ttest) = perk(y, ν, trainData, kernel, ρ) # [L,N]

    return (xhat, trainData, ttrain, ttest)

end

function perk(
	y::AbstractArray{<:Real,2},
	ν::AbstractArray{<:AbstractArray{<:Real,1},1},
	trainData::TrainingData,
	kernel::Kernel,
	ρ::Real
)

	# Concatenate the data and the known parameters
	if isempty(ν)
		q = y # [D+K,N], K = 0 0 allocations
	else
		q = [y; transpose(reduce(hcat, ν))] # [D+K,N]
	end

	(xhat, t) = perk(q, trainData, kernel, ρ) # [L,N]

	return (xhat, t)

end

"""
    perk(q, trainData, kernel, ρ)

Estimate latent parameters using the provided training data.

# Arguments
- `q::AbstractArray{<:Real,2}`: Test data points concatenated with known
    parameters [D+K,N]
- `trainData::TrainingData`: Training data
- `kernel::Kernel`: Kernel to use
- `ρ::Real`: Regularization parameter

# Return
- `xhat::Array{<:Real,2}`: Estimated latent parameters [L,N]
- `t::Real`: Duration of testing (s)
"""
function perk(
    q::AbstractArray{<:Real,2},
    trainData::ExactTrainingData,
    kernel::ExactKernel,
    ρ::Real
)

    t = @elapsed begin
        k = kernel(trainData.q, q) # [T,N]
        k .-= trainData.Km # [T,N]
		# Add trainData.T * ρ to diagonal of trainData.K
		for i = 1:size(trainData.K,1)+1:length(trainData.K)
			trainData.K[i] += trainData.T * ρ
		end
		k .= trainData.K \ k # [T,N]
        xhat = trainData.xm .+ trainData.x * k # [L,N]

		# Undo modification of trainData
		for i = 1:size(trainData.K,1)+1:length(trainData.K)
			trainData.K[i] -= trainData.T * ρ
		end
    end

    return (xhat, t)

end

function perk(
    q::AbstractArray{<:Real,2},
    trainData::RFFTrainingData,
    ::RFFKernel,
    ρ::Real
)

    t = @elapsed begin
        z = rffmap(q, trainData.freq, trainData.phase) # [H,N]
        z .-= trainData.zm # [H,N]
		# Add ρ to diagonal of trainData.Czz
		for i = 1:size(trainData.Czz,1)+1:length(trainData.Czz)
			trainData.Czz[i] += ρ
		end
		z .= trainData.Czz \ z # [H,N]
        xhat = trainData.xm .+ trainData.Cxz * z # [L,N]

		# Undo modification of trainData
		for i = 1:size(trainData.Czz,1)+1:length(trainData.Czz)
			trainData.Czz[i] -= ρ
		end
    end

    return (xhat, t)

end
function test_holdout_1()

    rng = StableRNG(0)
    N = 10
    T = 200
    λvals = [1, 2]
    ρvals = [1, 2]
    weights = [1]
    xDistsTest = [Uniform(100, 100.000000001)]
    νDistsTest = [Uniform(30, 30.000000001)]
    xDistsTrain = [Uniform(10, 500)]
    νDistsTrain = νDistsTest
    noiseDist = Normal(0, 0.01)
    signalModels = [(x, ν) -> exp(-ν / x)]
    kernelgenerator = Λ -> GaussianKernel(Λ)
    (λ, ρ, Ψ) = PERK.holdout(rng, N, T, λvals, ρvals, weights, xDistsTest,
                             νDistsTest, xDistsTrain, νDistsTrain, noiseDist,
                             signalModels, kernelgenerator, showprogress = false)

    return λ == 1 && ρ == 1

end

function test_holdout_2()

    rng = StableRNG(0)
    N = 10
    T = 200
    λvals = [1, 2]
    ρvals = [1, 2]
    weights = [1]
    xDistsTest = [Uniform(100, 100.000000001)]
    xDistsTrain = [Uniform(10, 500)]
    noiseDist = Normal(0, 0.01)
    signalModels = [x -> exp(-30 / x)]
    kernelgenerator = Λ -> GaussianKernel(Λ)
    (λ, ρ, Ψ) = PERK.holdout(rng, N, T, λvals, ρvals, weights, xDistsTest,
                             xDistsTrain, noiseDist, signalModels,
                             kernelgenerator, showprogress = false)

    return λ == 1 && ρ == 1

end

function test_holdout_3()

    rng = StableRNG(0)
    N = 10
    T = 200
    λvals = [1, 2]
    ρvals = [1, 2]
    xDistsTest = Uniform(100, 100.000000001)
    νDistsTest = Uniform(30, 30.000000001)
    xDistsTrain = Uniform(10, 500)
    νDistsTrain = νDistsTest
    noiseDist = Normal(0, 0.01)
    signalModels = [(x, ν) -> exp(-ν / x)]
    kernelgenerator = Λ -> GaussianKernel(Λ)
    (λ, ρ, Ψ) = PERK.holdout(rng, N, T, λvals, ρvals, xDistsTest,
                             νDistsTest, xDistsTrain, νDistsTrain, noiseDist,
                             signalModels, kernelgenerator, showprogress = false)

    return λ == 1 && ρ == 1

end

function test_holdout_4()

    rng = StableRNG(0)
    N = 10
    T = 200
    λvals = [1, 2]
    ρvals = [1, 2]
    xDistsTest = Uniform(100, 100.000000001)
    xDistsTrain = Uniform(10, 500)
    noiseDist = Normal(0, 0.01)
    signalModels = x -> [exp(-30 / x), x]
    kernelgenerator = Λ -> GaussianKernel(Λ)
    (λ, ρ, Ψ) = PERK.holdout(rng, N, T, λvals, ρvals, xDistsTest,
                             xDistsTrain, noiseDist, signalModels,
                             kernelgenerator, showprogress = false)

    return λ == 1 && ρ == 1

end

@testset "Holdout" begin

    @test test_holdout_1()
    @test test_holdout_2()
    @test test_holdout_3()
    @test test_holdout_4()

end

tests = [
    "krr",
    "estimation",
    "holdout"
]
for t in tests
    include("$(t).jl")
end

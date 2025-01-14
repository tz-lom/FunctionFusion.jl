using Test, FunctionFusion

@testset "" verbose = true begin
    include("artifact_and_provider_definitions_test.jl")

    include("context_test.jl")
    include("substitute_test.jl")
    include("provider.jl")

    include("usecases.jl")
    # include("visualization.jl")

end

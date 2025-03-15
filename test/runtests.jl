using Test
using FunctionFusion

@testset "" verbose = true begin
    include("artifact_and_provider_definitions_test.jl")

    include("context_test.jl")
    include("substitute_test.jl")
    include("provider.jl")
    include("audit.jl")

    include("usecases.jl")

end

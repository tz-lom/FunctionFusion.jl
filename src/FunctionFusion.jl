module FunctionFusion

export @artifact,
    @provider,
    @conditional,
    @promote,
    @algorithm,
    @template,
    @implement,
    @group,
    @unimplemented,
    @invoke_with,
    @callback_provider,
    @switch_provider,
    substitute,
    visualize,
    @audit_provider

import Base
using Match
using OrderedCollections

include("artifact.jl")
include("providers/abstract.jl")
include("providers/callable.jl")

include("execution_plan.jl")

include("context.jl")
include("providers/conditional.jl")
# include("composed.jl")
include("providers/promote.jl")
include("providers/unimplemented.jl")

include("providers/group.jl")

include("providers/algorithm.jl")
include("providers/invoke_with.jl")
include("providers/callback.jl")
include("providers/switch.jl")


include("substitute.jl")

include("implement.jl")


include("visualization.jl")

include("audit.jl")

end # module FunctionFusion

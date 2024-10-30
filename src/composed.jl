
struct ComposedProvider <: AbstractProvider
    call::Function
    plan::ExecutionPlan
    container::Type
    remaps::Any
    inputs::Any
    outputs::Any

    function ComposedProvider(call, plan, ctx_name, remaps)
        remaps = Dict(remaps)
        rremaps = Dict(values(remaps) .=> keys(remaps))

        input_diff = setdiff(plan.inputs, values(remaps))
        if length(input_diff) > 0
            error("For compose $name inputs $input_diff are not described")
        end
        output_diff = setdiff(plan.outputs, keys(remaps))
        if length(output_diff) > 0
            error("For compose $name outputs $output_diff are not described")
        end

        inputs = Dict(map(i -> i => rremaps[i], collect(plan.inputs)))
        outputs = Dict(map(i -> remaps[i] => i, collect(plan.outputs)))

        # artifacts = union(plan.artifacts, keys(outputs))

        return new(call, plan, ctx_name, remaps, inputs, outputs)

    end
end

inputs(p::ComposedProvider) = values(p.inputs)
outputs(p::ComposedProvider) = keys(p.outputs)
storage(p::ComposedProvider) = Set((p.container, keys(p.outputs)...))

function provide(p::ComposedProvider, result::Type, context, source)
    function inner_source(artifact)
        if artifact in p.plan.inputs
            return provide(p, artifact, context, source)
        else
            provider = p.plan.provider_for_artifact[artifact]
            return provide(provider, artifact, :($context[$(p.container)]), inner_source)
        end
    end

    if result in p.plan.inputs
        return quote
            if isnothing($context[$(p.container)][$result])
                $context[$(p.container)][$result] = $(source(p.inputs[result]))
            end
            something($context[$(p.container)][$result])
        end
    elseif result in keys(p.outputs)
        return quote
            if isnothing($context[$result])
                $context[$result] = $(inner_source(p.outputs[result]))
            end
            something($context[$result])
        end
    elseif result in p.plan.artifacts
        return inner_source(result)
    else
        error("Can't provide $result")
    end
end

function define_compose(name, providers)

    providers = map(describe_provider, providers)

    ctx_name = Symbol(name, "Context")

    plan = ExecutionPlan(providers)




    return quote
        $Glue.@context($ctx_name, $(plan.artifacts...))

        function $name(remaps...)
            $ComposedProvider($name, $plan, $ctx_name, remaps)
        end

        # const $provider =
        # $ComposedProvider($name, $plan, $ctx_name, $remaps, $inputs, $outputs)

        # $Glue.describe_provider($name) = $provider
    end
end

"""
    @compose name(providers...) where (ExternalInput=>InternalInput, InternalOutput=>ExternalOutput)

Encapsulates algorithm for the re-use in many places
@todo: write better documentation when functionality is stable
"""
macro compose(name, providers...)
    return quote
        Base.eval(
            $__module__,
            $Glue.define_compose($(QuoteNode(name)), ($(map(esc, providers)...),)),
        )
    end
    # @match expr begin
    #     Expr(:where, [Expr(:ref, [name, providers...]), Expr(:tuple, [remaps...])]) => begin
    #         return quote
    #             Base.eval(
    #                 $__module__,
    #                 define_compose(
    #                     $(QuoteNode(name)),
    #                     ($(map(esc, providers)...),),
    #                     ($(map(esc, remaps)...),),
    #                 ),
    #             )
    #         end
    #     end
    #     Expr(:where, [Expr(:ref, [name, providers...]), remap]) => begin
    #         return quote
    #             Base.eval(
    #                 $__module__,
    #                 define_compose(
    #                     $(QuoteNode(name)),
    #                     ($(map(esc, providers)...),),
    #                     ($(map(esc, remap)),),
    #                 ),
    #             )
    #         end
    #     end
    #     _ => error("Unsupported syntax: $(expr)")
    # end
end
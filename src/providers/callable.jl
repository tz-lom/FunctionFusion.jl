

struct CallableProvider <: AbstractProvider
    call::Function
    inputs::Tuple{Vararg{DataType}}
    output::Type{<:Artifact}
    mutables::Tuple{Vararg{DataType}}

    function CallableProvider(call, inputs, output, mutables)
        name = Symbol(call)
        unique_inputs = Set(inputs)
        if length(unique_inputs) != length(inputs)
            error("Inputs must be unique for provider $name")
        end
        if output in unique_inputs
            error("Output type $output should not be an input for provider $name")
        end
        new(call, inputs, output, mutables)
    end
end

inputs(p::CallableProvider) = p.inputs
outputs(p::CallableProvider) = (p.output,)
storage(p::CallableProvider) = p.output
mutables(p::CallableProvider) = p.mutables
# short_description(p::CallableProvider) = extract_short_description(p.doc)

Base.show(io::IO, p::CallableProvider) =
    print(io, "CallableProvider $(nameof(p.call))$(p.inputs)::$(p.output)")

function provide(p::CallableProvider, result::Type, context, resolve)
    if (p.output != result)
        error("$p can't provide $result")
    end
    return quote
        if isnothing($context[$result])
            $context[$result] = $(p.call)($([resolve(i) for i in p.inputs]...))
        end
        something($context[$result])
    end
end



"""
    read_function_signature(func::Expr)::NamedTuple{(:name,:result,:arguments)}

Read the signature of a provider function and return a named tuple with the function's name, result type, and argument types.
"""
function read_function_signature(signature::Expr)

    # Ensure the expression represents a function definition with an explicit return type
    if signature.head != :(::)
        throw(DomainError(signature, "Function must have an explicit return type"))
    end

    artifacts = []
    name = signature.args[1].args[1]
    result = make_artifact(artifacts, signature.args[2])


    # Extract the argument expressions
    arg_exprs = signature.args[1].args[2:end]
    # Preallocate the array for argument types
    arguments = Vector{Tuple{Symbol,Union{Symbol,Expr}}}(undef, length(arg_exprs))
    mutables = []

    for (i, arg) in enumerate(arg_exprs)
        # Ensure each argument is a type-annotated expression
        if typeof(arg) != Expr || arg.head != :(::)
            throw(
                DomainError(signature, "Argument #$i must be a type-annotated expression"),
            )
        end
        # Extract the argument name and type
        arg_name = arg.args[1]
        arg_type, mutable = make_artifact(artifacts, arg.args[2]; support_mutable = true)
        arguments[i] = (arg_name, arg_type)
        if mutable
            push!(mutables, arg_name)
        end
    end

    return (; name, result, arguments, artifacts, mutables)
end

"""
    # 1 
    @provider function name(arg::Artifact, ...)::Artifact
              ...
    end

    # 2
    @provider name(arg::Artifact, ...)::Artifact = x

    # 2
    @provider name(Artifact,...)::Artifact

    # 3
    @provider alias = name(Artifact, ...)::Artifact

Declares a provider with given inputs and output.
All inputs + output must be unique artifacts.

3 versions of the syntax are supported:
1 and 2 - function definitions
3 - declare existing function as provider
4 - make an alias to existing function and declare it as a provider

"""
macro provider(func::Expr)
    # Helper function to extract the artifact type
    extract_type = (type) -> :($artifact_type($type))

    expr = @match func begin
        # Match the expression format of a function definition
        Expr(:function, [signature, body]) => begin
            # Read the function signature
            sig = read_function_signature(signature)

            # Create a new function signature with artifact types
            new_signature = Expr(
                :(::),
                Expr(
                    :call,
                    sig.name,
                    map(
                        (args,) -> Expr(:(::), args[1], extract_type(args[2])),
                        sig.arguments,
                    )...,
                ),
                extract_type(sig.result),
            )

            # Copy the original function definition and replace the signature
            new_function = func
            new_function.args[1] = new_signature

            # Extract and escape inputs, name, and output
            inputs = map((arg) -> esc(arg[2]), sig.arguments)
            name = esc(sig.name)
            output = esc(sig.result)
            mutables = map(esc, sig.mutables)

            quote
                $(sig.artifacts...)

                Core.@__doc__ $(esc(new_function))

                local definition = $FunctionFusion.CallableProvider(
                    $name,
                    ($(inputs...),),
                    $output,
                    ($(mutables...),),
                )

                function $FunctionFusion.describe_provider(::typeof($name))
                    return definition
                end

                $FunctionFusion.is_provider(::typeof($name)) = true
            end
        end
        # Match the expression format of a short function definition

        Expr(:(=), [Expr(:(::), [Expr(:call, [name, args...]), result]), body]) => begin
            signature = func.args[1]
            sig = read_function_signature(signature)

            artifacts = []
            new_args = map(
                (arg,) -> Expr(:(::), arg[1], extract_type(arg[2])),
                sig.arguments,
            )
            inputs = map((arg) -> esc(arg[2]), sig.arguments)
            output = extract_type(sig.result)

            esc_name = esc(sig.name)
            mutables = map(esc, sig.mutables)

            new_function = Expr(
                :(=),
                Expr(:(::), Expr(:call, sig.name, new_args...), output),
                body,
            )

            quote
                $(sig.artifacts...)

                Core.@__doc__ $(esc(new_function))

                local definition = $FunctionFusion.CallableProvider(
                    $esc_name,
                    ($(inputs...),),
                    $(esc(sig.result)),
                    ($(mutables...),),
                )

                function $FunctionFusion.describe_provider(::typeof($esc_name))
                    return definition
                end

                $FunctionFusion.is_provider(::typeof($esc_name)) = true
            end
        end

        # Match the expression format of a pre-defined function with inputs and output
        Expr(:(::), [Expr(:call, [name, inputs...]), output]) => begin
            name = esc(name)
            artifacts = []
            mutables = []
            inputs = map(inputs) do x
                type, is_mutable = make_artifact(artifacts, x; support_mutable = true)
                e = esc(type)
                if is_mutable
                    push!(mutables, e)
                end
                return e
            end
            output = esc(make_artifact(artifacts, output))
            docname = gensym(:doc)
            quote
                $(artifacts...)

                Core.@__doc__ $(esc(docname))() = nothing
                local definition = $FunctionFusion.CallableProvider(
                    $name,
                    ($(inputs...),),
                    $output,
                    ($(mutables...),),
                )
                Base.delete_method(Base.which($(esc(docname)), ()))

                function $FunctionFusion.describe_provider(::typeof($name))
                    return definition
                end

                $FunctionFusion.is_provider(::typeof($name)) = true
            end
        end
        # Match the expression format of a provider alias
        Expr(:(=), [name, Expr(:(::), [Expr(:call, [alias, inputs...]), output])]) =>
            begin
                qname = QuoteNode(name)
                name = esc(name)
                alias = esc(alias)
                artifacts = []
                mutables = []
                inputs = map(inputs) do x
                    type, is_mutable = make_artifact(artifacts, x; support_mutable = true)
                    e = esc(type)
                    if is_mutable
                        push!(mutables, e)
                    end
                    return e
                end
                output = esc(make_artifact(artifacts, output))
                def = gensym(:definition)
                quote
                    $(artifacts...)

                    Core.@__doc__ $name(args...) = $alias(args...)

                    local definition = $FunctionFusion.CallableProvider(
                        $name,
                        ($(inputs...),),
                        $output,
                        ($(mutables...),),
                    )

                    function $FunctionFusion.describe_provider(::typeof($name))
                        return definition
                    end

                    $FunctionFusion.is_provider(::typeof($name)) = true
                end
            end
        _ => throw(DomainError(func, "Can't make provider with given definition"))
    end
    Base.replace_linenums!(expr, __source__)
end




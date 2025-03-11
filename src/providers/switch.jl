struct SwitchProvider <: AbstractProvider
    call::Any
    input::Type{<:Artifact}
    output::Type{<:Artifact}
    options::Vector{Type{<:Artifact}}
end

inputs(p::SwitchProvider) = (p.input,)
outputs(p::SwitchProvider) = (p.output,)
storage(p::SwitchProvider) = p.output

function provide(p::SwitchProvider, result::Type, context, resolve)
    if p.output != result
        error("$p can't provide $result")
    end
    options = p.options

    generate_result = Expr(
        :if,
        :(input == $(options[1])),  # condition for 1st option
        resolve(options[1]), # then generate 1st artifact
        # else
        foldr(
            options[2:end], # for all other options
            init = :(error("Unsupported option")), # else block shall throw error
        ) do opt, other
            Expr(
                :elseif,
                :(input == $opt), # condition for n-th option
                resolve(opt),  # producer for n-th option
                other,
            ) # elseif block
        end,
    )

    output_type = artifact_type(p.output)
    gen = if output_type <: AbstractVector || output_type <: Tuple
        :($(p.output)(map($(resolve(p.input))) do input
            $generate_result
        end))
    else
        :(((input) -> $generate_result)($(resolve(p.input))))
    end

    return quote
        if isnothing($context[$result])
            $context[$result] = $gen
        end
        something($context[$result])
    end
end

function define_switch_provider(name, input, output, options)
    descr = gensym(:descr)
    return quote
        Core.@__doc__ function $name()
            error($("Can't call Switch Provider $name directly"))
        end

        local $descr = $FunctionFusion.SwitchProvider($name, $input, $output, $options)

        $FunctionFusion.describe_provider(::typeof($name)) = $descr
        $FunctionFusion.is_provider(::typeof($name)) = true
    end
end

"""
    @switch_provider Name(Input)::Output = [Options...]

Creates switch provider that will map `Input` to switch which of `Options` include in the `Output`
If `Output` is a `AbstractVector` or `Tuple` then `Input` had to be iteratable and it will construct it for as many `Input` elements as it has
otherwise only one Artifact would be returned

"""
macro switch_provider(expr)
    @match expr begin
        Expr(
            :(=),
            [
                Expr(:(::), [Expr(:call, [name, input]), output]),
                Expr(:block, [_, Expr(:vect, options)]),
            ],
        ) => begin

            artifacts = []
            input = make_artifact(artifacts, input)
            output = make_artifact(artifacts, output)
            options = map(x -> esc(make_artifact(artifacts, x)), options)


            quote
                $(artifacts...)

                Base.eval(
                    $__module__,
                    define_switch_provider(
                        $(QuoteNode(name)),
                        $(esc(input)),
                        $(esc(output)),
                        [$(options...)],
                    ),
                )
            end
        end
        _ => throw(DomainError(expr, "Unsupported syntax"))
    end
end
"""
    AbstractProvider

Type common for all providers.
Shall implement interface with methods
* `is_provider`
* `inputs`
* `outputs`
* `short_description`
* `provide`
"""
abstract type AbstractProvider end

abstract type ProviderModifier end


"""
    inputs(A::AbstractProvider)

Return all artifacts required by provider `A`
"""
function inputs end


"""
    outputs(A::AbstractProvider)

Returns all artifacts provided by provider `A`
"""
function outputs end

"""
    storage(A::AbstractProvider)

Returns storage container necessary for provider `A`
"""
function storage end

"""
    provide(A::AbstractProvider, artifact::AbstractArtifact, context, parent::Union{AbstractProvider, Nothing})

Returns Expr which computes requested `artifact` using values from `context` for source
"""
function provide end

"""
    describe_provider(x)::AbstractProvider

Returns Provider object describing the provider
This function is only defined for providers, use `is_provider(x)` to check if `x` is a provider
"""
describe_provider(p::T) where {T<:AbstractProvider} = p


"""
    is_provider(x)::Boolean

Returns `true` if `x` is declared as a provider and `false` otherwise.
"""
is_provider(::AbstractProvider) = true
is_provider(f::Function) = hasmethod(describe_provider, (typeof(f),))

is_modifier(_) = false
is_modifier(::ProviderModifier) = true

storage(p::AbstractProvider, _) = storage(p)

apply_modification_iteratively(mod::ProviderModifier, p::AbstractProvider) =
    apply_modification(mod, p)

function collect_providers(lst)

    function super_flatten(arr)
        rst = Any[]
        grep(v) =
            for x in v
                if isa(x, Tuple) || isa(x, Array)
                    grep(x)
                else
                    push!(rst, x)
                end
            end
        grep(arr)
        rst
    end

    # flatten all elements of lst

    lst = super_flatten(lst)

    modifiers = filter(is_modifier, lst)

    providers = collect(map(describe_provider, filter(!is_modifier, lst)))

    for mod in modifiers
        providers = map(p -> apply_modification_iteratively(mod, p), providers)
    end

    unique!(providers)

    return providers
end

# function extract_short_description(doc::Markdown.MD)
#     descr = string(Markdown.MD(doc.content[1]))
#     if startswith(descr, "No documentation found")
#         return nothing
#     else
#         return descr
#     end
# end

function short_description(p::AbstractProvider)
    return nothing
    # docstring = @doc p

    # descr = string(Markdown.MD(docstring.content[1]))
    # if descr == "No documentation found.\n"
    #     return nothing
    # else
    #     return descr
    # end
end


function make_artifact(artifacts, expr; support_mutable = false)
    return @match expr begin
        Expr(:braces, [Expr(:call, [:(=>), name::Symbol, type])]) => begin
            push!(artifacts, define_artifact(name, type))
            if support_mutable
                return name, false
            else
                return name
            end
        end
        s::Symbol => begin # Just symbol name
            if support_mutable
                return s, false
            else
                return s
            end
        end
        Expr(:(.), _) => if support_mutable # e.g. A.B.C
            return expr, false
        else
            return expr
        end
        Expr(:braces, [Expr(:call, [:!, s::Symbol])]), if support_mutable
        end => return s, true
        Expr(:braces, [Expr(:call, [:!, (ex && Expr(:(.), _))])]),
        if support_mutable
        end => return ex, true
        Expr(:braces, [Expr(:call, [:(=>), Expr(:call, [:!, name::Symbol]), type])]),
        if support_mutable
        end => begin
            push!(artifacts, define_artifact(name, type))
            return name, true
        end

        _ => error("Unknown artifact type definition $expr")
    end
end
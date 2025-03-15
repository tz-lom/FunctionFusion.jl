abstract type Artifact{T} end

real_type(::Type{Artifact{T}}) where {T} = T

function define_artifact(iname, itype; doc = false)
    name = esc(iname)
    type = esc(itype)
    expr = quote
        struct $name <: Artifact{$type}
            $name(args...) = $type(args...)
        end
    end

    if doc
        return quote
            Core.@__doc__ $expr
        end
    else
        return expr
    end
end


"""
    @artifact name[,name...] = Type

Declares `Artifact` associated with `Type`

# Example
```
@artifact A = Int
@artifact B,C = Bool
```
"""
macro artifact(expr::Expr)
    expr = @match expr begin
        Expr(:(=), [Expr(:tuple, inames), itype]) => begin
            exprs = map(inames) do iname
                define_artifact(iname, itype; doc = true)
            end
            Expr(:block, exprs...)
        end
        Expr(:(=), [iname::Symbol, itype]) => begin
            define_artifact(iname, itype; doc = true)
        end
        _ => error("Unsupported syntax: $(dump(expr))")
    end
    Base.replace_linenums!(expr, __source__)
end

macro artifact(name, type, doc = false)
    Base.replace_linenums!(define_artifact(name, type; doc), __source__)
end

"""
    artifact_type(Artifact)::Type

Get the `Type` associated with an `Artifact`

# Example
```julia
@artifact A = Int
artifact_type(A) == Int
```
"""
artifact_type(::Type{<:Artifact{T}}) where {T} = T



"""
    is_artifact(::Type)

Check if a given type is an `Artifact`.
"""
is_artifact(::Type{<:Artifact}) = true
is_artifact(_) = false

function Base.show(io::IO, ::MIME"text/plain", ::Type{T}) where {T<:Artifact}
    print(io, "Artifact $T=$(artifact_type(T))")
end

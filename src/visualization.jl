struct NameShortener
    values::IdDict
    mod::Module
    function NameShortener(mod::Module = Main)
        if VERSION >= v"1.12"
            all_names = names(mod, all = true, imported = true, usings = true)
        else
            all_names = names(mod, all = true, imported = true)
        end

        return new(IdDict(getproperty(mod, name) => name for name in all_names), mod)
    end
end

function Base.show(io::IO, x::NameShortener)
    print(io, "NameShortener($(x.mod))")
end

function short_name(ctx::NameShortener, @nospecialize(x))
    postfix = ""
    while true
        if haskey(ctx.values, x)
            return "$(ctx.values[x])$postfix"
        end
        postfix = ".$(nameof(x))$postfix"
        y = parentmodule(x)
        if y === x
            error("Unreachable symbol $x")
        end
        x = y
    end
end

mutable struct GraphBuilder
    connections::Vector{String}
    added_entities::Dict{Any,Symbol}
    shortener::NameShortener
    clusters::Vector{String}
    current_place::Int
    id_incr::Int
    primary::Union{Nothing,Missing,Any}
    context::String

    GraphBuilder(; mod = Main) =
        new([], IdDict(), NameShortener(mod), [], 1, 0, missing, "")
end

function as_dot(ctx::GraphBuilder)
    return """
    digraph { layout=dot; compound=true;
    $(join(ctx.clusters, '\n'))

    $(join(ctx.connections, '\n'))
    }
    """
end

function add_to_cluster!(ctx::GraphBuilder, s::String)
    insert!(ctx.clusters, ctx.current_place, s)
    ctx.current_place += 1
    return ctx.current_place
end

function create_subcluster!(f, ctx::GraphBuilder, name; props...)
    str_props = ["$name=\"$(escape_string(value))\"" for (name, value) in props]
    add_to_cluster!(ctx, "subgraph cluster_$name {")
    add_to_cluster!(ctx, join(str_props, ";"))
    result = f()
    add_to_cluster!(ctx, "} // cluster_$name")
    return result
end

function create_cluster!(f, ctx::GraphBuilder, name; props...)
    str_props = ["$name=\"$(escape_string(value))\"" for (name, value) in props]
    old_place = ctx.current_place
    ctx.current_place = length(ctx.clusters) + 1
    add_to_cluster!(ctx, "subgraph cluster_$name {")
    add_to_cluster!(ctx, join(str_props, ";"))
    result = f()
    add_to_cluster!(ctx, "} // cluster_$name")
    ctx.current_place = old_place
    return result
end

function in_context!(f, ctx::GraphBuilder, suffix)
    old_context = ctx.context
    ctx.context *= String(suffix)
    result = f()
    ctx.context = old_context
    return result
end

function connect!(ctx::GraphBuilder, left, right; props...)
    local edge = node("$left -> $right"; props...)
    push!(ctx.connections, edge)
    return ctx
end

function node(name; props...)
    str_props = ["$name=\"$(escape_string(value,keep="\\"))\"" for (name, value) in props]

    if length(str_props) > 0
        return "$name [$(join(str_props, ','))]"
    else
        return "$name"
    end
end

# function new_get_id(ctx::GraphBuilder, prefix::Symbol)
#     return Symbol(prefix, "_", ctx.id_incr += 1)
# end

function get_id(ctx::GraphBuilder, object, prefix::Symbol, context)
    x = context => object
    if !haskey(ctx.added_entities, x)
        if context == ""
            new_id = Symbol(prefix, "_", ctx.id_incr += 1)
        else
            new_id = Symbol(context, "__", prefix, "_", ctx.id_incr += 1)
        end
        ctx.added_entities[x] = new_id
        return new_id, true
    else
        return ctx.added_entities[x], false
    end
end

function need_id(ctx::GraphBuilder, object)
    return ctx.added_entities[ctx.context=>object]
end

function need_id(ctx::GraphBuilder, object, context)
    return ctx.added_entities[context=>object]
end

function get_id(ctx::GraphBuilder, object, prefix::Symbol)
    get_id(ctx, object, prefix, ctx.context)
end

function render!(ctx::GraphBuilder, a::Type{T}; primary = true) where {T<:Artifact}
    id, new = get_id(ctx, a, :artifact)
    if new
        name = short_name(ctx.shortener, a)
        label = "$name\n$(artifact_type(a))"
        add_to_cluster!(
            ctx,
            node(
                id;
                label,
                shape = "ellipse",
                style = primary ? "filled" : "",
                color = "#4a7c59",
                fillcolor = "#8fc0a9",
            ),
        )
    end
    return id
end

function render!(ctx::GraphBuilder, x)
    render!(ctx, describe_provider(x))
end


function render!(
    ctx::GraphBuilder,
    p::AlgorithmProvider;
    part_of_invoke = false,
    subalgorithm = false,
)
    id, new = get_id(ctx, p, :provider)
    if new
        name = short_name(ctx.shortener, p.call)
        is_primary = ctx.primary == p


        heads = Dict()
        tails = Dict()

        delayed_connections = []

        if !is_primary && !part_of_invoke
            for a in inputs(p)
                heads[a] = render!(ctx, a)
            end
            for a in outputs(p)
                if subalgorithm
                    tails[a] = render!(ctx, a, primary = false)
                else
                    tails[a] = render!(ctx, a)
                end
            end
        end


        create = if is_primary || part_of_invoke
            create_cluster!
        else
            create_subcluster!
        end

        create(ctx, id, label = "Algorithm $name") do
            in_context!(ctx, id) do
                create_subcluster!(ctx, "$(id)_inputs", label = "Inputs") do
                    for a in inputs(p)
                        to = render!(ctx, a; primary = is_primary)
                        if haskey(heads, a)
                            connect!(ctx, heads[a], to)
                        end
                    end
                end

                own_artifacts = filter(is_artifact, keys(p.context_outputs))

                for a in own_artifacts
                    if a ∉ outputs(p)
                        render!(ctx, a)
                    end
                end

                create_subcluster!(ctx, "$(id)_outputs", label = "Outputs") do
                    for a in outputs(p)
                        from = if a in own_artifacts
                            render!(ctx, a)
                        else
                            in_context!(ctx, "outputs") do
                                term = render!(ctx, a, primary = false)
                                push!(delayed_connections, a => term)
                                term
                            end
                        end
                        if haskey(tails, a)
                            connect!(
                                ctx,
                                from,
                                tails[a];
                                arrowhead = "none",
                                color = "#4a7c59",
                            )
                        end
                    end
                end

                add_to_cluster!(ctx, " // before providers")

                for x in p.plan.providers
                    render!(ctx, x; subalgorithm = true)
                end

                for (a, to) in delayed_connections
                    existing = need_id(ctx, a)
                    connect!(ctx, existing, to; arrowhead = "none", color = "#4a7c59")
                end
            end
        end
    end
    return id
end

function render!(ctx::GraphBuilder, p::CallableProvider; _...)
    id, new = get_id(ctx, p, :provider)
    if new
        name = short_name(ctx.shortener, p.call)

        descr = short_description(p)
        if isnothing(descr)
            descr = ""
        else
            descr = "\n$descr"
        end
        add_to_cluster!(
            ctx,
            node(
                id;
                shape = "rectangle",
                label = "$name$descr",
                style = "filled",
                color = "#ff8c61",
                fillcolor = "#faa275",
            ),
        )
        # for a in p.output
        other = render!(ctx, p.output)
        connect!(ctx, id, other)
        # end
        for a in p.inputs
            other = render!(ctx, a)
            connect!(ctx, other, id)
        end
    end
    return id
end

function render!(ctx::GraphBuilder, p::CallbackProvider; _...)
    id, new = get_id(ctx, p, :callback_provider)
    if new
        name = short_name(ctx.shortener, p.call)

        descr = short_description(p)
        if isnothing(descr)
            descr = ""
        else
            descr = "\n$descr"
        end
        add_to_cluster!(
            ctx,
            node(
                id;
                shape = "insulator",
                label = "$name$descr",
                style = "filled",
                color = "#ff8c61",
                fillcolor = "#faa275",
            ),
        )
        for a in outputs(p)
            other = render!(ctx, a)
            connect!(ctx, id, other)
        end
        origin = render!(ctx, p.origin)
        connect!(ctx, id, origin; arrowhead = "none")
    end
    return id
end

function render!(ctx::GraphBuilder, p::PromoteProvider; _...)
    id, new = get_id(ctx, p, :promote)
    if new
        name = short_name(ctx.shortener, p.call)

        add_to_cluster!(
            ctx,
            node(
                id;
                shape = "rpromoter",
                label = name,
                style = "filled",
                color = "#ff8c61",
                fillcolor = "#faa275",
            ),
        )

        connect!(ctx, id, render!(ctx, p.output))
        connect!(ctx, render!(ctx, p.input), id)
    end
    return id
end

function render!(ctx::GraphBuilder, p::ConditionalProvider; _...)
    id, new = get_id(ctx, p, :conditional)
    if new
        name = short_name(ctx.shortener, p.call)

        add_to_cluster!(
            ctx,
            node(
                id;
                shape = "diamond",
                label = name,
                style = "filled",
                color = "#b23a48",
                fillcolor = "#fcb902",
            ),
        )

        connect!(ctx, render!(ctx, p.condition), id; label = "?")
        connect!(ctx, render!(ctx, p.if_true), id; label = "true")
        connect!(ctx, render!(ctx, p.if_false), id; label = "false")
        connect!(ctx, id, render!(ctx, p.output))
    end
    return id
end

function render!(ctx::GraphBuilder, p::GroupProvider; _...)
    id, new = get_id(ctx, p, :group)
    if new
        name = short_name(ctx.shortener, p.call)

        create_subcluster!(ctx, id, label = "Group $name") do
            for a in filter(is_artifact, keys(p.context))
                render!(ctx, a)
            end

            for p in p.plan.providers
                render!(ctx, p)
            end
        end
    end
    return id
end


function render!(ctx::GraphBuilder, p::UnimplementedProvider; _...)
    id, new = get_id(ctx, p, :unimplemented)
    if new
        name = short_name(ctx.shortener, p.call)

        descr = short_description(p)
        if isnothing(descr)
            descr = ""
        else
            descr = "\n$descr"
        end
        add_to_cluster!(
            ctx,
            node(
                id;
                shape = "rectangle",
                label = "Unimplemented $name$descr",
                # style = "filled",
                color = "#ff8c61",
                # fillcolor = "#faa275",
            ),
        )
        # for a in p.output
        other = render!(ctx, p.output)
        connect!(ctx, id, other)
        # end
        for a in p.inputs
            other = render!(ctx, a)
            connect!(ctx, other, id)
        end
    end
    return id
end

function render!(ctx::GraphBuilder, p::InvokeProvider; _...)
    id, new = get_id(ctx, p, :invoke)
    if new
        name = short_name(ctx.shortener, p.call)

        descr = short_description(p)
        if isnothing(descr)
            descr = name
        else
            descr = "$name\n$descr"
        end

        descr = replace(
            descr,
            "{" => "\\{",
            "}" => "\\}",
            ">" => "\\>",
            "<" => "\\<",
            "|" => "\\|",
        )

        inputs_label = []
        inputs_maps = []
        for a in inputs(p.algorithm)
            a_id, _ = get_id(ctx, :invokeIn => a, :invokeIn)
            # a_id = render!(ctx, a)
            a_replace = get(p.backward_substitutions, a, a)
            push!(inputs_maps, (a_id, a, a_replace))
            if a !== a_replace
                push!(
                    inputs_label,
                    "<$a_id>$(short_name(ctx.shortener, a_replace))⇥$(short_name(ctx.shortener, a))",
                )
            else
                push!(inputs_label, "<$a_id>$(short_name(ctx.shortener, a))")
            end
        end

        outputs_label = []
        outputs_maps = []
        for a in outputs(p.algorithm)
            a_id, _ = get_id(ctx, :invokeOut => a, :invokeOut)
            # a_id = need_id(ctx, a)
            # a_id = render!(ctx, a)
            a_replace = get(p.backward_substitutions, a, a)
            push!(outputs_maps, (a_id, a, a_replace))
            if a !== a_replace
                push!(
                    outputs_label,
                    "<$a_id>$(short_name(ctx.shortener, a_replace))⇥$(short_name(ctx.shortener, a))",
                )
            else
                push!(outputs_label, "<$a_id>$(short_name(ctx.shortener, a))")
            end
        end

        add_to_cluster!(
            ctx,
            node(
                id;
                shape = "record",
                label = "{{$(join(inputs_label, "|"))}|<body>$descr|{$(join(outputs_label,"|"))}}",
                # style = "filled",
                # color = "#ff8c61",
                # fillcolor = "#faa275",
            ),
        )

        alg_id = render!(ctx, p.algorithm, part_of_invoke = true)
        target_id = need_id(ctx, inputs(p.algorithm)[1], "$(ctx.context)$alg_id")
        connect!(ctx, "$id:body", target_id, lhead = "cluster_$alg_id")

        for (gate_id, a, a_replace) in outputs_maps
            # other = render!(ctx, a)
            # connect!(ctx, other, "$id:$gate_id")
            if a !== a_replace
                other = render!(ctx, a_replace)
                connect!(ctx, "$id:$gate_id", other)
            end
        end
        for (gate_id, a, a_replace) in inputs_maps
            # other = render!(ctx, a)
            # connect!(ctx, "$id:$gate_id", other)
            if a !== a_replace
                other = render!(ctx, a_replace)
                connect!(ctx, other, "$id:$gate_id")
            end
        end
    end
    return id
end


function render!(ctx::GraphBuilder, p::SwitchProvider; _...)
    id, new = get_id(ctx, p, :switch_provider)
    if new
        name = short_name(ctx.shortener, p.call)

        descr = short_description(p)
        if isnothing(descr)
            descr = ""
        else
            descr = "\n$descr"
        end
        add_to_cluster!(
            ctx,
            node(
                id;
                shape = "folder",
                label = "$name$descr",
                style = "filled",
                color = "#ff8c61",
                fillcolor = "#faa275",
            ),
        )
        for a in outputs(p)
            other = render!(ctx, a)
            connect!(ctx, id, other)
        end
        for a in inputs(p)
            other = render!(ctx, a)
            connect!(ctx, other, id)
        end
        for a in p.options
            other = render!(ctx, a)
            connect!(ctx, other, id; style = "dashed")
        end
    end
    return id
end

function visualize(p, format::MIME"text/vnd.graphviz"; kvargs...)
    g = GraphBuilder(; kvargs...)
    p = describe_provider(p)
    g.primary = p
    render!(g, p)
    as_dot(g)
end

function visualize(providers::Vector, format::MIME"text/vnd.graphviz"; kvargs...)
    g = GraphBuilder(; kvargs...)
    g.primary = nothing
    for p in providers
        render!(g, p)
    end
    as_dot(g)
end

visualize(mod::Module, format::MIME"text/vnd.graphviz"; kvargs...) =
    visualize([mod], format; kvargs...)

function visualize(mods::Vector{Module}, format::MIME"text/vnd.graphviz"; kvargs...)
    # collect all providers that belong to mods
    providers = map(methods(is_provider)) do m
        m.sig.parameters[2]
    end

    # providers = providers[providers.∉Ref([Function, FunctionFusion.AbstractProvider])]
    filter!(providers) do p
        parentmodule(p) ∈ mods
    end
    sort!(providers; by = Symbol)

    return visualize(map(p -> p.instance, providers), format; kvargs...)
end

default_format::MIME = MIME("text/vnd.graphviz")

"""
    visualize(what, [format]; parameters...)

Provides visualization in MIME `format` for `what`.
`what` can be either provider or vector of providers
If `format` is not specified then it is chosen automatically:
* If `GrahpViz` package is not loaded then it is `MIME"text/vnd.graphviz"` which is a graphviz document.
* If `GraphViz` package is loaded then it would be `MIME"image/svg+xml"` which is a .svg image.

Load GraphViz in your REPL to have visualization as picture (automatically displayed in VScode).

`parameters`:

* `mod=Main` display names relative to that module
* `depth=Inf` display only `depth` nesting of the graph
* `hide_types=False` hide types of the artifacts
"""
visualize(p; kvargs...) = visualize(p, default_format; kvargs...)

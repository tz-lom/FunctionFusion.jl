using GraphvizDotLang: GraphvizDotLang, Graph, digraph, edge, attr, subgraph
import GraphViz

const Grph = Union{GraphvizDotLang.Graph,GraphvizDotLang.Subgraph}

# GraphViz.

as_id(f::Function) = String(Symbol(parentmodule(f), '.', f))
as_id(t::Type) = String(Symbol(t))
as_id(s::Symbol) = String(s)

function node(id::String, port::Union{String,Nothing} = nothing; kwargs...)
    g -> begin

        nid = GraphvizDotLang.NodeId(id, port)
        nd = findfirst(
            el -> typeof(el) === GraphvizDotLang.NodeStmt && el.id == nid,
            g.stmt_list,
        )

        if nd === nothing
            g |> GraphvizDotLang.node(id, port; kwargs...)
        end
        g
    end
end


function visualize!(g::Grph, a::Type{<:Artifact}, _)
    id = as_id(a)
    g |> node(
        as_id(a),
        ;
        shape = "ellipse",
        label = "$id\n$(artifact_type(a))",
        style = "filled",
        color = "#4a7c59",
        fillcolor = "#8fc0a9",
    )
end

function visualize!(g::Grph, p::CallableProvider, root::Graph)
    id = as_id(p.call)
    descr = short_description(p)
    if isnothing(descr)
        descr = ""
    else
        descr = "\n$descr"
    end
    g |> node(
        id;
        shape = "rectangle",
        label = "$id$descr",
        style = "filled",
        color = "#ff8c61",
        fillcolor = "#faa275",
    )

    for inp in p.inputs
        visualize!(g, inp, root)
        g |> edge(as_id(inp), id)
    end

    visualize!(g, p.output, root)
    g |> edge(id, as_id(p.output))
end


function visualize!(g::Grph, p::UnimplementedProvider, root::Graph)
    id = as_id(p.call)
    descr = short_description(p)
    if isnothing(descr)
        descr = ""
    else
        descr = "\n$descr"
    end
    g |> node(
        id;
        shape = "hexagon",
        label = "$id$descr",
        style = "filled",
        color = "#ff8c61",
        fillcolor = "#faa275",
    )

    for inp in p.inputs
        visualize!(g, inp, root)
        g |> edge(as_id(inp), id)
    end

    visualize!(g, p.output, root)
    g |> edge(id, as_id(p.output))
end

function visualize!(g::Grph, p::ConditionalProvider, root::Graph)
    id = as_id(p.name)
    g |> node(
        id;
        shape = "diamond",
        label = "$id",
        style = "filled",
        color = "#b23a48",
        fillcolor = "#fcb902",
    )


    visualize!(g, p.condition, root)
    g |> edge(as_id(p.condition), id; label = "?")

    visualize!(g, p.if_true, root)
    g |> edge(as_id(p.if_true), id; label = "true")

    visualize!(g, p.if_false, root)
    g |> edge(as_id(p.if_false), id; label = "false")

    visualize!(g, p.output, root)
    g |> edge(id, as_id(p.output))
end

function visualize!(g::Grph, p::AlgorithmProvider, root::Graph)
    id = as_id(p.call)

    sub = g #subgraph(g, "cluster_" * id; label = id)

    sub_inputs =
        subgraph(sub, "cluster_" * id * "inputs"; label = "Inputs", style = "dashed")

    for inp in p.inputs
        visualize!(sub_inputs, inp, root)
    end

    sub_outputs =
        subgraph(sub, "cluster_$(id)_outputs", label = "Outputs", style = "dashed")

    visualize!(sub_outputs, p.output, root)

    for provider in p.plan.providers
        visualize!(sub, provider, root)
    end
end

function visualize!(g::Grph, p::InvokeProvider, root::Graph)
    visualize!(g, p.algorithm, root)
end

# function visualize!(g::Grph, p::ComposedProvider, root::Graph)
#     id = as_id(p.call)

#     sub_id = "cluster_composed_$(id)"

#     nd = findfirst(
#         el -> typeof(el) === GraphvizDotLang.NodeStmt && el.id == sub_id,
#         root.stmt_list,
#     )
#     if nd === nothing

#         sub = subgraph(root, sub_id; label = "$id implementation")

#         for inp in p.inputs
#             sub |> node(
#                 as_id(inp[1]);
#                 shape = "ellipse",
#                 label = "$(as_id(inp[1]))\n⇤ $(as_id(inp[2]))\n$(artifact_type(inp[1]))",
#                 style = "filled",
#                 color = "#5c374c",
#                 fillcolor = "#985277",
#             )
#         end

#         for inp in p.outputs
#             sub |> node(
#                 as_id(inp[2]);
#                 shape = "ellipse",
#                 label = "$(as_id(inp[2]))\n⇥ $(as_id(inp[1]))\n$(artifact_type(inp[2]))",
#                 style = "filled",
#                 color = "#5c374c",
#                 fillcolor = "#985277",
#             )
#         end

#         for provider in p.plan.providers
#             visualize!(sub, provider, root)
#         end
#     end

#     g |> node(
#         id;
#         label = id,
#         shape = "component",
#         style = "filled",
#         color = "#5c374c",
#         fillcolor = "#985277",
#     )

#     g |> edge(
#         id,
#         as_id(first(p.plan.inputs)),
#         lhead = sub_id,
#         arrowhead = "none",
#         style = "dotted",
#         constraint = "false",
#     )

#     for inp in inputs(p)
#         visualize!(g, inp, root)
#         g |> edge(as_id(inp), id)
#     end
#     for out in outputs(p)
#         visualize!(g, out, root)
#         g |> edge(id, as_id(out))
#     end
# end

function visualize!(g::Grph, p::PromoteProvider, root::Graph)
    id = as_id(p.call)

    visualize!(g, p.input, root)
    visualize!(g, p.output, root)

    g |> node(
        id;
        shape = "rpromoter",
        label = id,
        style = "filled",
        color = "#e6b89c",
        fillcolor = "#ead2ac",
    )
    g |> edge(as_id(p.input), id)
    g |> edge(id, as_id(p.output))
end

function visualize!(g::Grph, p::GroupProvider, root::Graph)
    id = as_id(p.call)

    sub = subgraph(g, "cluster_group_$id#aside"; label = "Group $id")
    for provider in p.plan.providers
        visualize!(sub, provider, root)
    end

    # g |> node(id; label = id)

    # for inp in inputs(p)
    #     visualize!(g, inp)
    #     g |> edge(as_id(inp), id)
    # end
    # for out in outputs(p)
    #     visualize!(g, out)
    #     g |> edge(id, as_id(out))
    # end

end

function visualize(p::AbstractProvider)
    g = digraph(compound = "true")
    visualize!(g, p, g)
    return g
end

function visualize(lst::Vector)
    providers = collect_providers(lst)
    g = digraph(compound = "true")
    foreach(p -> visualize!(g, p, g), providers)
    return g
end

function visualize(p)
    visualize(describe_provider(p))
end

function render(g::Graph)
    io = IOBuffer()
    print(io, g)
    return GraphViz.Graph(String(take!(io)))
end
module FunctionFusion_GraphVis

import FunctionFusion
using GraphViz: GraphViz


function FunctionFusion.visualize(p, format::MIME"image/svg+xml"; kvargs...)
    dot = FunctionFusion.visualize(p, MIME("text/vnd.graphviz"); kvargs...)
    grph = GraphViz.Graph(dot)
    grph
end

# FunctionFusion.visualize(p; kvargs...) =
#     visualize(p; format = MIME()"image/svg+xml"), kvargs...)

function __init__()
    FunctionFusion.default_format = MIME("image/svg+xml")
end

end
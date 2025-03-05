module UsecaseTests

using Test

module Utils

export verifyEquals, @verifyVisualization

using InteractiveUtils: code_native
using Test
using FunctionFusion
using DeepDiffs

function signature(f)
    m = methods(f)

    if length(m) != 1
        error("Function $f have multiple signatures")
    end
    return Tuple(m[1].sig.types[2:end])
end

function return_type(f, args...)
    type = Core.Compiler.return_type(f, Base.typesof(args...))
    if type == Union{}
        error("Function $f is not defined for $args")
    end
    return type
end


function verifyEquals(generated, expected, arguments...)

    # Verify signature
    @test signature(generated) == signature(expected)
    # Verify return type                   
    @test return_type(generated, arguments...) == return_type(expected, arguments...)


    @test generated(arguments...) == expected(arguments...)

    io = IOBuffer()

    code_native(
        io,
        expected,
        Base.typesof(arguments...),
        debuginfo = :none,
        dump_module = false,
    )
    expected_native = String(take!(io))

    code_native(
        io,
        generated,
        Base.typesof(arguments...),
        debuginfo = :none,
        dump_module = false,
    )
    generated_native = String(take!(io))

    if expected_native != generated_native
        println(deepdiff(expected_native, generated_native))
        @test true == false
    end

end


function verifyVisualization(mod, to_visualize, expected, update)
    update = update || haskey(ENV, "UPDATE_VISUAL_TESTS")
    dot = FunctionFusion.visualize(to_visualize, MIME("text/vnd.graphviz"); mod)

    expected_dot = joinpath(@__DIR__, "visualized", expected * ".dot")

    if update
        write(expected_dot, dot)

        expected_png = joinpath(@__DIR__, "visualized", expected * ".png")
        # png_io = IOBuffer()
        # run(pipeline(`dot -Tpng`; stdin = IOBuffer(dot), stdout = png_io))
        # png = String(take!(png_io))
        # write(expected_png, png)
        run(`dot -Tpng $expected_dot -o$expected_png`)
    end

    expected_str = read(expected_dot, String)
    # is_same_dot = result == expected_str
    if dot != expected_str
        println(deepdiff(expected_str, dot))
        @test false == true
    end

end

macro verifyVisualization(to_visualize, expected, update_visualization = false)
    return esc(
        :($verifyVisualization(
            $__module__,
            $to_visualize,
            $expected,
            $update_visualization,
        )),
    )
end

end

function test()

    usecases() = filter(endswith(".jl"), readdir(joinpath(@__DIR__, "usecases")))

    @testset for file in usecases()
        include(joinpath(@__DIR__, "usecases", file))
    end

    # include(joinpath(@__DIR__, "usecases", "0003.jl"))
end

end

@testset "Usecases" verbose = true UsecaseTests.test()
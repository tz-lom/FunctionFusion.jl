module TestCase0017
using ..Utils
using Test
using FunctionFusion




@artifact A1 = Int

struct Foo end

struct Bar
    a::Int
    b::Foo
    c::Core.SimpleVector
    value::String
    z::Any
end



@artifact A2 = Bar

@provider function P1(a::A1)::A2
    return Bar(a, Foo(), [1, 2, 3], "hello", nothing)
end

@verifyVisualization(P1, "0017")


end

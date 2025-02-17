module TestCase0004

using ..Utils

# using Test

using FunctionFusion

@artifact A1 = Int
@artifact A2 = Int

@promote P1(A1)::A2


@algorithm generated(A1)::A2 = [P1]

function expected(a::Int)::Int
    return a
end

verifyEquals(generated, expected, 42)

@verifyVisualization(generated, "0004")

end



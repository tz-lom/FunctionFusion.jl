module TestCase0015

using ..Utils
using Test
using FunctionFusion

const X = String

@provider P1(x::{A1 => X})::{A2 => X} = x

@provider function P2(x::{A3 => X})::{A4 => X}
    return x
end

P3(x) = x

@provider P3({A5 => X})::{A6 => X}


# @switch_provider Switch1(I1)::O1 = [A1, A2, A3]
# @algorithm Alg1(I1)::O1 = [P1, P2, P3, Switch1]

# @switch_provider Switch2(I2)::O2 = [A1, A2, A3]
# @algorithm Alg1(A1)::A2 = [P1, P2, P3]

# @test Alg1(A1) == 1
# @test Alg1(A3) == 3

# @test Alg([A]) == [2, 1, 3]

@verifyVisualization([P1, P2, P3], "0015", true)


end
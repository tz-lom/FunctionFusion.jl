module TestCase0016

using ..Utils
using Test
using FunctionFusion

# Test: Provider returning a tuple of artifacts (multiple outputs)

@artifact Input = Int
@artifact OutputA = Int
@artifact OutputB = String

# Variant 1: full function definition with tuple return
@provider function multi_output(x::Input)::(OutputA, OutputB)
	return (x * 2, string(x))
end

# Single-output provider consuming one of the multi-outputs
@provider function use_a(a::OutputA)::{Result1 => Int}
	return a + 100
end

@algorithm generated(Input)::Result1 = [multi_output, use_a]

function expected(x::Int)::Int
	tmp = (x*2, string(x))
	return tmp[1] + 100
end

verifyEquals(generated, expected, 5)

end

module TestCase0016b

using ..Utils
using Test
using FunctionFusion

# Test: Algorithm with tuple output

@artifact In1 = Int
@artifact Mid = Int
@artifact OutX = Int
@artifact OutY = String

@provider function step1(a::In1)::Mid
	return a + 1
end

@provider function step2(a::Mid)::(OutX, OutY)
	return (a * 10, string(a))
end

@algorithm generated(In1)::(OutX, OutY) = [step1, step2]

function expected(a::Int)::Tuple{Int,String}
	mid = a + 1
	return (mid * 10, string(mid))
end

@test generated(3) == expected(3)
@test generated(3) == (40, "4")

@verifyVisualization([generated], "0016_B")


end

module TestCase0016c

using ..Utils
using Test
using FunctionFusion

# Test: Variant 2 (short function def) with tuple return

@artifact SA = Int
@artifact SB = Int
@artifact SC = Float64

@provider short_multi(a::SA, b::SB)::(SC, {SD => String}) = (Float64(a + b), string(a - b))

@provider function use_both(c::SC, d::SD)::{SResult => String}
	return "$(c) and $(d)"
end

@algorithm short_generated(SA, SB)::SResult = [short_multi, use_both]

@test short_generated(10, 3) == "13.0 and 7"

@verifyVisualization([short_generated], "0016_C")

end

module TestCase0016e

using ..Utils
using Test
using FunctionFusion

# Test: Predefined function variant with tuple return using named artifacts

@artifact QA = Int
@artifact QB = Int
@artifact QC = Int
@artifact QD = String

function my_func(a, b)
	return (a * b, string(a + b))
end

@provider my_func(QA, QB)::(QC, QD)

@provider function consume_both(c::QC, d::QD)::{QResult => String}
	return "$c: $d"
end

@algorithm q_generated(QA, QB)::QResult = [my_func, consume_both]

@test q_generated(3, 4) == "12: 7"

@verifyVisualization([q_generated], "0016_D")

end

module TestCase0016f

using ..Utils
using Test
using FunctionFusion

# Test: Alias variant with tuple return

@artifact RA = Int
@artifact RB = Int
@artifact RC = Int
@artifact RD = String

function original_func(a, b)
	return (a - b, string(a + b))
end

@provider aliased = original_func(RA, RB)::(RC, RD)

@provider function use_rd(d::RD)::{RResult => String}
	return "result: $d"
end

@algorithm r_generated(RA, RB)::RResult = [aliased, use_rd]

@test r_generated(10, 3) == "result: 13"

end

module TestCase0016g

using ..Utils
using Test
using FunctionFusion

# Test: Single-element tuple return (backward compat edge case)

@artifact TA = Int
@artifact TB = Int

@provider function single_tuple(a::TA)::(TB,)
	return a + 42
end

@algorithm t_generated(TA)::TB = [single_tuple]

@test t_generated(0) == 42
@test t_generated(8) == 50

end

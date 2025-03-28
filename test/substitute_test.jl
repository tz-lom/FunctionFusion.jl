
module Test_substitute
using Test, FunctionFusion
using FunctionFusion: collect_providers, describe_provider

@artifact A1, A2, A3, AA1, AA2 = Int

@provider function P1(x::A1)::A2
    x
end

@provider function P2(x::A2)::A3
    x
end

@provider function PP1(x::AA1)::AA2
    x
end

@unimplemented U1(A1)::A2

@unimplemented U2(AA1)::AA2

@algorithm C1(AA1)::AA2 = [U2] implement = false

@invoke_with C1_impl = C1{A1 => AA1,AA2 => A2}

@group G1 = [U1]


@testset "substitute" begin

    @testset "simple" begin
        @test collect_providers([substitute(U1, P1), U1]) == [describe_provider(P1)]
    end

    @testset "order and other providers are irrelevant" begin
        @test collect_providers([U1, substitute(U1, P1), P2]) ==
              [describe_provider(P1), describe_provider(P2)]
    end

    @testset "groups are handled correctly" begin
        p1 = describe_provider(P1)
        g1 = describe_provider(G1)

        new_group = FunctionFusion.GroupProvider(
            g1.call,
            g1.context,
            FunctionFusion.ExecutionPlan([p1]),
        )

        @test collect_providers([G1, substitute(U1, P1), P2]) ==
              [new_group, describe_provider(P2)]
    end

    @testset "composed is handled correctly" begin
        pp1 = describe_provider(PP1)
        c1 = describe_provider(C1)

        new_algorithm = FunctionFusion.AlgorithmProvider(
            c1.call,
            c1.context,
            c1.context_outputs,
            c1.inputs,
            c1.output,
            FunctionFusion.ExecutionPlan([pp1]),
        )

        i1 = describe_provider(C1_impl)

        new_invoke = FunctionFusion.InvokeProvider(
            i1.call,
            i1.context,
            new_algorithm,
            i1.backward_substitutions,
        )

        @test collect_providers([C1_impl, substitute(U2, PP1), P2]) ==
              [new_invoke, describe_provider(P2)]
    end


    @testset "duplicates are elliminated is expanded correctly" begin
        expected = [describe_provider(P1), describe_provider(P2)]

        @test collect_providers([P1, P2, P1]) == expected

    end

    @testset "array is expanded correctly" begin
        a = [[[P1], P2]]
        expected = [describe_provider(P1), describe_provider(P2)]

        @test collect_providers([a]) == expected
    end
end

end
module Test_actifact_and_provider
using Test, FunctionFusion
using FunctionFusion: is_artifact, artifact_type, is_provider, describe_provider

@testset "Declare artifact" begin
    @artifact A1 = Int
    @test is_artifact(A1) == true
    @test is_artifact(Int) == false
    @test artifact_type(A1) == Int
end

@testset "Declare provider as function" begin
    @artifact A2 = Int
    @artifact B2 = Int
    @artifact C2 = Int

    @provider function foo(a::A2, b::B2)::C2
        return a + b
    end

    a = A2(1)
    b = B2(3)
    expected = C2(4)
    @test foo(a, b) == expected

    @test is_provider(foo) == true

    descr = describe_provider(foo)
    @test descr.call == foo
    @test descr.inputs == (A2, B2)
    @test descr.output == C2
end

@testset "Declare existing function as provider" begin
    @artifact A3 = Int
    @artifact B3 = Int

    @test is_provider(abs) == false
    @provider abs(A3)::B3
    @test is_provider(abs) == true

    expected = B3(3)
    @test abs(A3(-3)) == expected

    descr = describe_provider(abs)
    @test descr.call == abs
    @test descr.inputs == (A3,)
    @test descr.output == B3
end

@testset "Declare alias to existing function as provider" begin
    @artifact A4 = Int
    @artifact B4 = Int
    @artifact C4 = Int

    @test is_provider(max) == false
    @provider foo = max(A4, B4)::C4
    @test is_provider(max) == false
    @test is_provider(foo) == true

    expected = C4(3)
    @test foo(A4(-1), B4(3)) == expected

    descr = describe_provider(foo)
    @test descr.call == foo
    @test descr.inputs == (A4, B4)
    @test descr.output == C4
end

@testset "Reject unsupported syntax of @provider" begin
    @artifact A5 = Int
    @artifact B5 = Int

    @test_throws LoadError eval(:(@provider function foo(x) end))
    @test_throws LoadError eval(:(@provider function foo(x)::Int end))

    @test_throws ErrorException eval(:(@provider function foo(x::A5, y::A5)::B5 end))
    @test_throws ErrorException eval(:(@provider function foo(x::A5)::A5 end))

    @test_throws ErrorException eval(:(@provider max(A5, A5)::B5))
    @test_throws ErrorException eval(:(@provider abs(A5)::A5))

    @test_throws LoadError eval(:(@provider 2 + 2))
end

end
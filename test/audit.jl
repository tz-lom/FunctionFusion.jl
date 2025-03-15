@testset "Audit" verbose = true begin
    @provider P1(x::{In1 => Vector})::{Out1 => Vector} = x .+ 1

    @provider function P2(x::{In2 => Vector})::{Out2 => Vector}
        ret = x .+ 1
        x .+= 2
        return ret
    end

    @provider function P3(x::{In3 => Vector})::{Out3 => Vector}
        x .+= 1
    end

    @provider function P4(x::{In4 => Vector})::{Out4 => Vector}
        x
    end

    in1 = [1, 2]

    @audit_provider(P1, in1)

    @test FunctionFusion.do_audit_provider(P2, in1; call = :P2, arg_names = (:in1,)) ==
          ["Provider P2 modified argument in1"]

    @test FunctionFusion.do_audit_provider(P3, in1; call = :P3, arg_names = (:in1,)) == [
        "Provider P3 returned input argument in1 as result",
        "Provider P3 modified argument in1",
    ]

    @test FunctionFusion.do_audit_provider(P4, in1; call = :P4, arg_names = (:in1,)) ==
          ["Provider P4 returned input argument in1 as result"]

end
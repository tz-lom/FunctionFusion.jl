module FunctionFusion_Test

export visualize

import FunctionFusion
using Test: Pass, Fail, trigger_test_failure_break, record, get_testset

function FunctionFusion.do_audit_provider(provider, args...; call, arg_names)
    args_copy = deepcopy(args)
    result = provider(args...)

    errors = []
    # check that:
    # result shall not be copy of input
    for (arg, name) in zip(args, arg_names)
        # @todo: this is not very reliable - ideally compound types shall be matched with recursive descend
        if objectid(arg) == objectid(result)
            push!(errors, "Provider $call returned input argument $name as result")
        end
    end

    # call shall not modify inputs
    for (old, new, name) in zip(args_copy, args, arg_names)
        # @todo: this is not very reliable
        if old != new
            push!(errors, "Provider $call modified argument $name")
        end
    end

    isempty(errors) || errors
end

end
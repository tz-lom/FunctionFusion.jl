module FunctionFusion_Test

import FunctionFusion: FunctionFusion.Audit
using Test: do_test, Returned

using .Audit: audit_provider

macro Audit.audit_provider(call, args...)
    expr = "audit call to $call($(args...))"
    return Base.remove_linenums!(
        quote
            outcome = $audit_provider($(esc(call)), $(esc.(args)...))
            outcome_str = "\n" * mapreduce(x -> "\t∘ $x\n", *, outcome, init = "")
            $do_test(
                $Returned(
                    isempty(outcome),
                    outcome_str,
                    LineNumberNode($(__source__.line), $(QuoteNode(__source__.file))),
                ),
                $(QuoteNode(expr)),
            )
        end,
    )
end


end
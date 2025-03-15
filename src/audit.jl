
function do_audit_provider end

macro audit_provider(call, args...)
    return Base.remove_linenums!(
        esc(
            :(@test $do_audit_provider(
                $call,
                $(args...);
                call = $(QuoteNode(call)),
                arg_names = $(QuoteNode(args)),
            )),
        ),
    )
end

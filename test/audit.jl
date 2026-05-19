
@testset "SnapshotTaker" begin

    using FunctionFusion.Audit: SnapshotTaker, snapshot, perform_walk, verify_snapshot

    # Test that SnapshotTaker correctly traverses a self-referential structure without infinite loop.
    v_cycle = Any[[1, 2], "hello"]
    push!(v_cycle, v_cycle)

    st = SnapshotTaker(snapshot)
    sn = perform_walk(st, v_cycle)
    @test verify_snapshot(sn, v_cycle)
    v_cycle[2] = "world"
    @test !verify_snapshot(sn, v_cycle)

    struct AuditContainer
        items::Vector{Int}
    end

    st = SnapshotTaker(snapshot)
    data = AuditContainer([1, 2, 3])
    sn = perform_walk(st, data)
    @test verify_snapshot(sn, data)
    data.items[1] = 42
    @test !verify_snapshot(sn, data)
end

@testset "Collect pointers" begin
    using FunctionFusion.Audit: collect_pointers

    data = AuditContainer([1, 2, 3])
    ptrs = collect_pointers(data)
    @test length(ptrs) > 0
    #@test pointer_from_objref(data) ∉ ptrs # is immutable
    @test pointer_from_objref(data.items) ∈ ptrs

    v_cycle = Any[[1, 2], "hello"]
    push!(v_cycle, v_cycle)
    ptrs_cycle = collect_pointers(v_cycle)
    @test length(ptrs_cycle) > 0
    @test pointer_from_objref(v_cycle) ∈ ptrs_cycle
    @test pointer_from_objref(v_cycle[1]) ∈ ptrs_cycle
    @test pointer_from_objref(v_cycle[2]) ∉ ptrs_cycle
    @test pointer_from_objref(v_cycle[3]) ∈ ptrs_cycle
end

@testset "Audit" verbose = true begin

    # Mutable struct with no `==` implementation
    mutable struct AuditBox
        value::Int
    end

    P1(x) = x .+ 1

    function P2(_, x)
        ret = x .+ 1
        x .+= 2
        return ret
    end

    function P3(x)
        x .+= 1
    end

    function P4(_, _, x)
        x
    end

    in1 = [1, 2]

    @audit_provider(P1, in1)

    @test FunctionFusion.audit_provider(P2, 1, in1) == ["Provider modified argument 2"]

    @test FunctionFusion.audit_provider(P3, in1) == [
        "Provider returned part of input argument 1 in result",
        "Provider modified argument 1",
    ]

    @test FunctionFusion.audit_provider(P4, 1, 2, in1) ==
          ["Provider returned part of input argument 3 in result"]

    function P_nested_ret(v)
        v[1]
    end

    in_nested = [[1, 2], [3, 4]]
    @test FunctionFusion.audit_provider(P_nested_ret, in_nested) ==
          ["Provider returned part of input argument 1 in result"]

    function P_field_ret(c)
        c.items
    end

    in_container = AuditContainer([1, 2, 3])
    @test FunctionFusion.audit_provider(P_field_ret, in_container) ==
          ["Provider returned part of input argument 1 in result"]

    # Corner case 3: provider creates a *new* mutable struct from the input without
    # modifying it. Must NOT report mutation.
    # Bug: mutable structs without a custom == fall back to === (object identity), so
    # deepcopy(b) != b is always true, producing a false-positive "modified" error.
    function P_box_ok(b)
        AuditBox(b.value + 1)   # creates new box, does NOT touch b
    end


    in_box = AuditBox(5)
    @audit_provider(P_box_ok, in_box)

    # Corner case 4: provider *does* mutate a mutable struct field — must be detected.
    function P_box_mut(b)
        b.value += 1
        AuditBox(b.value)
    end

    in_box2 = AuditBox(5)
    @test FunctionFusion.audit_provider(P_box_mut, in_box2) ==
          ["Provider modified argument 1"]


    # --- Dict corner cases ---

    # Provider returns a mutable value stored in a dict (aliasing through dict)
    function P_dict_val_ret(d)
        d["key"]
    end

    d_with_vec = Dict("key" => [1, 2, 3])
    @test FunctionFusion.audit_provider(P_dict_val_ret, d_with_vec) ==
          ["Provider returned part of input argument 1 in result"]

    # Provider adds a key to the dict (mutation)
    function P_dict_add_key(d)
        d["new"] = 100
        Dict("new" => 100)
    end

    d_mutated = Dict("a" => 1)
    @test FunctionFusion.audit_provider(P_dict_add_key, d_mutated) ==
          ["Provider modified argument 1"]

    # Provider modifies a dict value in place (mutation)
    function P_dict_mutate_val(d)
        d["key"] .+= 1
        [0]
    end

    d_val_mutated = Dict("key" => [1, 2, 3])
    @test FunctionFusion.audit_provider(P_dict_mutate_val, d_val_mutated) ==
          ["Provider modified argument 1"]

    # Provider builds a new dict from input — correct, must NOT report errors
    function P_dict_copy(d)
        Dict(k => copy(v) for (k, v) in d)
    end

    d_ok = Dict("a" => [1, 2], "b" => [3, 4])
    @audit_provider(P_dict_copy, d_ok)

    # Provider returns a mutable-struct value from a dict (aliasing)
    function P_dict_box_ret(d)
        d["key"]
    end


    d_with_box = Dict("key" => AuditBox(42))
    @test FunctionFusion.audit_provider(P_dict_box_ret, d_with_box) ==
          ["Provider returned part of input argument 1 in result"]

    # Provider builds a new dict with new mutable-struct values — must NOT report errors
    function P_dict_box_copy(d)
        Dict(k => AuditBox(v.value) for (k, v) in d)
    end

    d_with_box2 = Dict("key" => AuditBox(42))
    @audit_provider(P_dict_box_copy, d_with_box2)

    # --- Tuple corner cases ---

    # Provider returns a mutable element of a tuple (aliasing)
    function P_tup_elem_ret(t)
        t[1]
    end

    t_with_vecs = ([1, 2, 3], [4, 5, 6])
    @test FunctionFusion.audit_provider(P_tup_elem_ret, t_with_vecs) ==
          ["Provider returned part of input argument 1 in result"]

    # Provider mutates an element inside a received tuple (mutation)
    function P_tup_mut_elem(t)
        t[1] .+= 1
        [0]
    end

    t_mutated = ([1, 2, 3], [4, 5, 6])
    @test FunctionFusion.audit_provider(P_tup_mut_elem, t_mutated) ==
          ["Provider modified argument 1"]

    # Provider creates a new tuple with copies — correct, must NOT report errors
    function P_tup_copy(t)
        (copy(t[1]), copy(t[2]))
    end

    t_ok = ([1, 2, 3], [4, 5, 6])
    @audit_provider(P_tup_copy, t_ok)

    # Provider receives a tuple with a mutable struct and creates a new one — no false positive
    function P_tup_box_ok(t)
        (AuditBox(t[1].value + 1),)
    end

    t_with_box = (AuditBox(5),)
    @audit_provider(P_tup_box_ok, t_with_box)

    # --- Sparse array (Vector with #undef elements) ---

    v_sparse = Vector{Vector{Int}}(undef, 4)
    v_sparse[1] = [10, 20]
    v_sparse[3] = [30, 40]
    # slots 2 and 4 are #undef

    # Provider returns a defined element — aliasing must be detected
    function P_undef_vec_alias(v)
        v[1]
    end
    @test FunctionFusion.audit_provider(P_undef_vec_alias, v_sparse) ==
          ["Provider returned part of input argument 1 in result"]

    # Provider returns a copy of a defined element — must NOT report errors;
    # traversal of undef slots must not crash
    function P_undef_vec_copy(v)
        copy(v[1])
    end
    @audit_provider(P_undef_vec_copy, v_sparse)

    # Provider fills an undef slot — mutation must be detected
    function P_undef_vec_fill(v)
        v[2] = [99]
        [0]
    end
    v_sparse2 = Vector{Vector{Int}}(undef, 4)
    v_sparse2[1] = [10, 20]
    @test FunctionFusion.audit_provider(P_undef_vec_fill, v_sparse2) ==
          ["Provider modified argument 1"]

    # Provider clears a defined slot — mutation must be detected
    function P_undef_vec_clear(v)
        ccall(:jl_array_del_end, Cvoid, (Any, UInt), v, 0)  # won't help; use unsafe approach
        # simpler: overwrite with a different value
        v[1] = [999]
        [0]
    end
    v_sparse3 = Vector{Vector{Int}}(undef, 4)
    v_sparse3[1] = [10, 20]
    @test FunctionFusion.audit_provider(P_undef_vec_clear, v_sparse3) ==
          ["Provider modified argument 1"]

    # --- Circular / self-referential structures ---

    # Self-referential vector: v_cycle[end] === v_cycle
    # Traversal must terminate without infinite loop.
    v_cycle = Any[[1, 2], AuditBox(7)]
    push!(v_cycle, v_cycle)   # v_cycle[3] === v_cycle

    # Provider returns self without touching anything — aliasing detected
    function P_cycle_alias(v)
        v
    end
    @test FunctionFusion.audit_provider(P_cycle_alias, v_cycle) ==
          ["Provider returned part of input argument 1 in result"]

    # Provider returns a fresh value — no aliasing, no mutation
    function P_cycle_clean(v)
        [42]
    end
    @audit_provider(P_cycle_clean, v_cycle)

    # Provider mutates an element inside the cyclic container
    function P_cycle_mut(v)
        (v[2]::AuditBox).value += 1
        [0]
    end
    v_cycle2 = Any[[1, 2], AuditBox(7)]
    push!(v_cycle2, v_cycle2)
    @test FunctionFusion.audit_provider(P_cycle_mut, v_cycle2) ==
          ["Provider modified argument 1"]
end

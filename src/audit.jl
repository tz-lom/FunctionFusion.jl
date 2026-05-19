module Audit

using Base: datatype_npointers, nth_pointer_isdefined, get_nth_pointer
using Core: SimpleVector, GenericMemory

const PtrList = Set{Ptr{Nothing}}
struct ObjectSnapshot
    type::DataType
    ptr::Ptr{Nothing}
    memory::Memory
    children::Vector{Any}
end

struct VectorSnapshot
    type::DataType
    ptr::Ptr{Nothing}
    elements::Vector{Any}
end

struct CopySnapshot
    data::Any
end

struct UndefinedSnapshot end

const undefined = UndefinedSnapshot()

verify_snapshot(snapshot, obj) = verify_snapshot(snapshot, obj, IdSet{Any}())

verify_snapshot(snapshot::CopySnapshot, obj, _) = snapshot.data === obj


function verify_snapshot(snapshot::ObjectSnapshot, obj, visited)
    if obj in visited
        return true
    end
    push!(visited, obj)
    typeof(obj) !== snapshot.type && return false
    ismutable(obj) && (object_ptr(obj) != snapshot.ptr) && return false

    memory = Memory{UInt8}(undef, sizeof(obj))
    unsafe_copyto!(pointer(memory), Ptr{UInt8}(object_ptr(obj)), sizeof(obj))
    if !isequal(memory, snapshot.memory)
        return false
    end

    for (i, child) in enumerate(snapshot.children)
        if child === undefined
            if nth_pointer_isdefined(obj, i)
                return false
            end
        elseif !nth_pointer_isdefined(obj, i)
            return false
        else
            !verify_snapshot(child[], get_nth_pointer(obj, i), visited) && return false
        end
    end
    return true
end

function verify_snapshot(snapshot::VectorSnapshot, obj, visited)
    if obj in visited
        return true
    end
    push!(visited, obj)
    typeof(obj) !== snapshot.type && return false
    object_ptr(obj) != snapshot.ptr && return false
    for (i, element) in enumerate(snapshot.elements)
        if element === undefined
            if isassigned(obj, i)
                return false
            end
        elseif !isassigned(obj, i)
            return false
        else
            !verify_snapshot(element[], obj[i], visited) && return false
        end
    end
    return true
end

struct SnapshotTaker
    visitor::Function
    visited::IdDict{Any,Ref{Any}}
    to_process::Vector{Any}

    SnapshotTaker(visitor) = new(visitor, IdDict(), Vector{Any}())
end

function request_walk(st::SnapshotTaker, x)::Ref
    if !haskey(st.visited, x)
        push!(st.to_process, x)
        st.visited[x] = Ref{Any}()
    end
    return st.visited[x]
end

object_ptr(@nospecialize obj) = ccall(:jl_value_ptr, Ptr{Cvoid}, (Any,), obj)

function perform_walk(st::SnapshotTaker)
    while !isempty(st.to_process) # process all pending objects
        next = pop!(st.to_process)
        st.visited[next][] = st.visitor(st, next) # Call visitor, it may schedule more objects
    end
    return nothing
end

function perform_walk(st::SnapshotTaker, @nospecialize x)
    result = request_walk(st, x)
    perform_walk(st)
    if !isassigned(result)
        error("Visitor did not assign a result for object")
    end
    return result[]
end

function snapshot(st::SnapshotTaker, @nospecialize x)
    isbitstype(typeof(x)) && return CopySnapshot(x) # always a copy

    memory = Memory{UInt8}(undef, sizeof(x))
    ptr = object_ptr(x)
    unsafe_copyto!(pointer(memory), Ptr{UInt8}(ptr), sizeof(x))

    children = Vector{Any}(undef, Base.datatype_npointers(typeof(x)))
    for i = 1:datatype_npointers(typeof(x))
        if nth_pointer_isdefined(x, i)
            children[i] = request_walk(st, get_nth_pointer(x, i))
        else
            children[i] = undefined
        end
    end
    return ObjectSnapshot(typeof(x), ptr, memory, children)
end

function snapshot(st::SnapshotTaker, x::Union{SimpleVector,GenericMemory})
    ptr = object_ptr(x)

    elements = Vector{Any}(undef, length(x))
    for i in eachindex(x)
        if isassigned(x, i)
            elements[i] = request_walk(st, x[i])
        else
            elements[i] = undefined
        end
    end
    return VectorSnapshot(typeof(x), ptr, elements)
end


snapshot(
    st::SnapshotTaker,
    x::Union{
        Symbol,
        Core.MethodInstance,
        Method,
        GlobalRef,
        DataType,
        Union,
        UnionAll,
        Task,
        Regex,
        String,
    },
) = CopySnapshot(x)

snapshot(st::SnapshotTaker, x::Module) = error("snapshot of Modules not supported")

collect_objects!(ids::PtrList, x::String) = ids # default for isbits types

function add_self!(ids::PtrList, @nospecialize x)
    try
        id = pointer_from_objref(x)
        push!(ids, id)
        return id
    catch
    end
    return Ptr{Nothing}()
end

function collect_pointers!(ids::PtrList, x::Union{Core.SimpleVector,GenericMemory})
    # Check before pushing so ids doubles as the visited set for cycle detection.
    ptr = try
        pointer_from_objref(x)
    catch
        return ids
    end
    ptr ∈ ids && return ids
    push!(ids, ptr)
    for i in eachindex(x)
        if isassigned(x, i)
            collect_pointers!(ids, x[i])
        end
    end
    return ids
end

function collect_pointers!(ids::PtrList, x)
    isbits(x) && return ids
    if ismutable(x)
        # Only mutable objects have stable pointers that can participate in cycles.
        # Immutable structs are value-typed — skip the ptr guard but still recurse
        # into their pointer children so reachable mutable objects are collected.
        ptr = try
            pointer_from_objref(x)
        catch
            return ids
        end
        ptr ∈ ids && return ids
        push!(ids, ptr)
    end
    for i = 1:Base.datatype_npointers(typeof(x))
        if Base.nth_pointer_isdefined(x, i)
            collect_pointers!(ids, Base.get_nth_pointer(x, i))
        end
    end
    return ids
end

# Skip strings as they are immutable, so it is ok to point to the same string
collect_pointers!(ids::PtrList, ::String) = ids
# Symbols are immutable
collect_pointers!(ids::PtrList, ::Symbol) = ids
# DataTypes are immutable
collect_pointers!(ids::PtrList, ::DataType) = ids
# Type name is safe to share too
collect_pointers!(ids::PtrList, ::Core.TypeName) = ids

function collect_pointers!(ids::PtrList, ::Module)
    @error "not implemented"
end

function collect_pointers!(ids::PtrList, ::Task)
    @error "not implemented"
end


"""
    collect_objects(x)

Collect the set of 
"""
collect_pointers(x) = collect_pointers!(PtrList(), x)

"""
    _structural_equal(a, b, visited)

Deep structural equality for any Julia value — including mutable structs without
a custom `==`, containers with uninitialized slots, and cyclic references.

The same two universal rules used in `_collect_mutable_ids!` apply here:
  1. `AbstractArray` — compare element-by-element with `isassigned` on both
     sides, so sparse arrays and internal `Memory` backing stores are handled
     correctly.
  2. `fieldcount > 0` — compare field-by-field with `isdefined` on both sides.
     This covers mutable structs, tuples, and container internals (e.g. `Dict`
     fields that include `Memory` backing stores) uniformly.
"""
function _structural_equal(a, b, visited::Set{Tuple{UInt,UInt}} = Set{Tuple{UInt,UInt}}())
    typeof(a) !== typeof(b) && return false
    isbits(a) && return isequal(a, b)
    a === b && return true
    id_pair = (objectid(a), objectid(b))
    id_pair in visited && return true   # already comparing this pair — assume equal (cycle)
    push!(visited, id_pair)
    if a isa AbstractArray
        size(a) != size(b) && return false
        for i in eachindex(a)
            assigned = isassigned(a, i)
            assigned == isassigned(b, i) || return false
            assigned && !_structural_equal(a[i], b[i], visited) && return false
        end
        return true
    elseif fieldcount(typeof(a)) > 0
        for i = 1:fieldcount(typeof(a))
            def = isdefined(a, i)
            def == isdefined(b, i) || return false
            def &&
                !_structural_equal(getfield(a, i), getfield(b, i), visited) &&
                return false
        end
        return true
    else
        return isequal(a, b)
    end
end

function audit_provider(provider, args...; snaphotter = snapshot)
    errors = []
    camera = SnapshotTaker(snaphotter)
    args_copy = [perform_walk(camera, arg) for arg in args]

    for (arg_id, (old, new)) in enumerate(zip(args_copy, args))
        if !verify_snapshot(old, new)
            push!(errors, "Immutability check is not working properly for argument $arg_id")
        end
    end

    result = provider(args...)

    # Collect all mutable object IDs reachable from the result.
    result_ids = collect_pointers(result)

    # result shall not alias any part of an input argument
    for (arg_id, arg) in enumerate(args)
        arg_ids = collect_pointers(arg)
        if !isempty(intersect(result_ids, arg_ids))
            push!(errors, "Provider returned part of input argument $arg_id in result")
        end
    end

    # call shall not modify inputs
    for (arg_id, (old, new)) in enumerate(zip(args_copy, args))
        if !verify_snapshot(old, new)
            push!(errors, "Provider modified argument $arg_id")
        end
    end

    errors
end

macro audit_provider(_...)
    error("@audit_provider macro requires Test module")
end

end

using .Audit: audit_provider, @audit_provider
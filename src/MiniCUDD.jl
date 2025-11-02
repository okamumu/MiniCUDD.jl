"""
MiniCUDD

A lightweight thin Julia wrapper around the CUDD BDD library.

This module provides minimal bindings to create and manipulate Binary Decision
Diagrams (BDDs) via the CUDD C API. It exposes a `Manager` type that owns a
CUDD manager, and `BDDNode` values representing BDD nodes. The API focuses on
fundamental operations (variable creation, boolean operators, ITE) and a few
utility helpers (minterm counting, DAG size, probability evaluation helpers
are not included here but can be implemented on top of the exposed primitives).

Basic usage:

```
using MiniCUDD

mgr = Manager(nvars=4)
v0 = var(mgr, 0)
v1 = var(mgr, 1)
f = bdd_and(mgr, v0, v1)
println("nodes: ", dag_size(f))
quit(mgr)
```

Notes:
- This wrapper calls into `libcudd` via `ccall`. Ensure CUDD is installed and
    `libcudd` is available on `LD_LIBRARY_PATH` (or platform equivalent).
- Objects returned from functions are `BDDNode` which manage CUDD references
    using finalizers. Use `close!` to explicitly release a node if desired.
"""
module MiniCUDD
using Libdl

include(joinpath(@__DIR__, "..", "deps", "deps.jl"))
const libcudd = libcudd_path

export Manager, BDDNode, var, const1, const0,
       bdd_and, bdd_or, bdd_xor, bdd_implies, bdd_ite,
       minterms, dag_size, close!, quit
export then_ptr, else_ptr, bdd_then, bdd_else
export node_index, isconstant

mutable struct DdManager end
mutable struct DdNode    end

const Cuint   = Base.Cuint
const Csize_t = Base.Csize_t

"""A handle that owns a CUDD manager pointer.

`Manager` wraps a `Ptr{DdManager}` and tracks whether the manager has been
closed. Finalizers will call `Cudd_Quit` when the manager is garbage-collected
unless `quit` was called explicitly.
"""
mutable struct Manager
    ptr::Ptr{DdManager}
    alive::Bool
end

"""Manager(; nvars=0, slots=256, cachesize=262144)

Create a new CUDD manager wrapped in a `Manager` object.

Arguments
- `nvars::Int`: initial number of BDD variables.
- `slots::Int`: unique table size parameter passed to CUDD.
- `cachesize::Int`: cache size parameter passed to CUDD.

Returns a `Manager` instance. Call `quit(mgr)` to free resources explicitly.
"""
function Manager(; nvars::Int=0, slots::Int=256, cachesize::Int=262144)
    mgr = ccall((:Cudd_Init, libcudd), Ptr{DdManager},
                (Cuint,Cuint,Cuint,Cuint,Csize_t),
                nvars, 0, slots, cachesize, Csize_t(0))
    mgr == C_NULL && error("Cudd_Init failed")
    m = Manager(mgr, true)
    finalizer(m) do mm
        if mm.alive && mm.ptr != C_NULL
            ccall((:Cudd_Quit, libcudd), Cvoid, (Ptr{DdManager},), mm.ptr)
            mm.alive = false
            mm.ptr = C_NULL
        end
    end
    return m
end

function quit(m::Manager)
    if m.alive && m.ptr != C_NULL
        ccall((:Cudd_Quit, libcudd), Cvoid, (Ptr{DdManager},), m.ptr)
        m.alive = false
        m.ptr = C_NULL
    end
    nothing
end

"""A managed BDD node.

`BDDNode` holds a pointer to a CUDD `DdNode` together with the owning
`Manager`. Nodes increment CUDD reference counts on creation and decrement
them when garbage-collected. Use `close!(node)` to release a node early.
"""
mutable struct BDDNode
    m::Manager
    ptr::Ptr{DdNode}
    alive::Bool
end

function _wrap_node(m::Manager, p::Ptr{DdNode}; ref::Bool=true, manage::Bool=true)
    p == C_NULL && error("CUDD returned NULL node")
    if ref
        ccall((:Cudd_Ref, libcudd), Cvoid, (Ptr{DdNode},), p)
    end
    n = BDDNode(m, p, manage)
    if manage
        finalizer(n) do nn
            if nn.alive && nn.ptr != C_NULL && nn.m.alive
                ccall((:Cudd_RecursiveDeref, libcudd), Cvoid,
                      (Ptr{DdManager}, Ptr{DdNode}), nn.m.ptr, nn.ptr)
                nn.alive = false
                nn.ptr = C_NULL
            end
        end
    end
    return n
end

"""close!(node)

Explicitly release the CUDD reference held by `node`. After calling
`close!` the node becomes invalid and should not be used.
"""
function close!(n::BDDNode)
    if n.alive && n.ptr != C_NULL && n.m.alive
        ccall((:Cudd_RecursiveDeref, libcudd), Cvoid,
              (Ptr{DdManager}, Ptr{DdNode}), n.m.ptr, n.ptr)
    end
    n.alive = false
    n.ptr = C_NULL
    nothing
end

"""var(mgr, i)

Return the BDD variable `i` from the manager `mgr` as a `BDDNode`.
"""
function var(m::Manager, i::Integer)::BDDNode
    p = ccall((:Cudd_bddIthVar, libcudd), Ptr{DdNode}, (Ptr{DdManager}, Cint), m.ptr, i)
    return _wrap_node(m, p)
end

"""const1(mgr; take_ref=false)

Return the logical constant 1 node for the manager `mgr`.
If `take_ref=true` the wrapper will take an additional reference and manage
the node; otherwise a non-managed thin wrapper is returned.
"""
function const1(m::Manager; take_ref::Bool=false)::BDDNode
    p = ccall((:Cudd_ReadOne, libcudd), Ptr{DdNode}, (Ptr{DdManager},), m.ptr)
    return take_ref ? _wrap_node(m, p; ref=true,  manage=true) :
                      _wrap_node(m, p; ref=false, manage=false)
end

"""const0(mgr; take_ref=false)

Return the logical constant 0 node for the manager `mgr`.
If `take_ref=true` the wrapper will take an additional reference and manage
the node; otherwise a non-managed thin wrapper is returned.
"""
function const0(m::Manager; take_ref::Bool=false)::BDDNode
    p = ccall((:Cudd_ReadLogicZero, libcudd), Ptr{DdNode}, (Ptr{DdManager},), m.ptr)
    return take_ref ? _wrap_node(m, p; ref=true,  manage=true) :
                      _wrap_node(m, p; ref=false, manage=false)
end

"""bdd_and(mgr, a, b)

Return the BDD representing logical AND of `a` and `b`.
"""
function bdd_and(m::Manager, a::BDDNode, b::BDDNode)::BDDNode
    p = ccall((:Cudd_bddAnd, libcudd), Ptr{DdNode},
              (Ptr{DdManager}, Ptr{DdNode}, Ptr{DdNode}),
              m.ptr, a.ptr, b.ptr)
    return _wrap_node(m, p)
end

"""bdd_or(mgr, a, b)

Return the BDD representing logical OR of `a` and `b`.
"""
function bdd_or(m::Manager, a::BDDNode, b::BDDNode)::BDDNode
    p = ccall((:Cudd_bddOr, libcudd), Ptr{DdNode},
              (Ptr{DdManager}, Ptr{DdNode}, Ptr{DdNode}),
              m.ptr, a.ptr, b.ptr)
    return _wrap_node(m, p)
end

"""bdd_xor(mgr, a, b)

Return the BDD representing logical XOR of `a` and `b`.
"""
function bdd_xor(m::Manager, a::BDDNode, b::BDDNode)::BDDNode
    p = ccall((:Cudd_bddXor, libcudd), Ptr{DdNode},
              (Ptr{DdManager}, Ptr{DdNode}, Ptr{DdNode}),
              m.ptr, a.ptr, b.ptr)
    return _wrap_node(m, p)
end

"""bdd_implies(mgr, a, b)

Return the BDD representing logical implication `a => b`.
"""
function bdd_implies(m::Manager, a::BDDNode, b::BDDNode)::BDDNode
    onep = ccall((:Cudd_ReadOne, libcudd), Ptr{DdNode}, (Ptr{DdManager},), m.ptr)
    p = ccall((:Cudd_bddIte, libcudd), Ptr{DdNode},
              (Ptr{DdManager}, Ptr{DdNode}, Ptr{DdNode}, Ptr{DdNode}),
              m.ptr, a.ptr, b.ptr, onep)
    return _wrap_node(m, p)
end

"""bdd_ite(mgr, i, t, e)

Return the if-then-else BDD: `i ? t : e`.
"""
function bdd_ite(m::Manager, i::BDDNode, t::BDDNode, e::BDDNode)::BDDNode
    p = ccall((:Cudd_bddIte, libcudd), Ptr{DdNode},
              (Ptr{DdManager}, Ptr{DdNode}, Ptr{DdNode}, Ptr{DdNode}),
              m.ptr, i.ptr, t.ptr, e.ptr)
    return _wrap_node(m, p)
end

@inline iscompl(p::Ptr{DdNode}) = (UInt(p) & 0x1) == 0x1
@inline compl(p::Ptr{DdNode})  = Ptr{DdNode}(UInt(p) ⊻ 0x1)

function then_ptr(n::BDDNode)
    t = ccall((:Cudd_T, libcudd), Ptr{DdNode}, (Ptr{DdNode},), n.ptr)
    return iscompl(n.ptr) ? compl(t) : t
end

"""else_ptr(node)

Return the raw else-pointer (Ptr{DdNode}) of the given `BDDNode`. The
pointer returned respects the complement bit of the node.
"""
function else_ptr(n::BDDNode)
    e = ccall((:Cudd_E, libcudd), Ptr{DdNode}, (Ptr{DdNode},), n.ptr)
    return iscompl(n.ptr) ? compl(e) : e
end

"""bdd_then(mgr, node)

Return the `BDDNode` corresponding to the then-child of `node`.
"""
function bdd_then(m::Manager, n::BDDNode)::BDDNode
    p = then_ptr(n)
    return _wrap_node(m, p; ref=false, manage=false)
end

"""bdd_else(mgr, node)

Return the `BDDNode` corresponding to the else-child of `node`.
"""
function bdd_else(m::Manager, n::BDDNode)::BDDNode
    p = else_ptr(n)
    return _wrap_node(m, p; ref=false, manage=false)
end

"""minterms(mgr, x, nvars)

Return the number of minterms (as a floating-point value) of `x` assuming
`nvars` variables. This is a wrapper around `Cudd_CountMinterm`.
"""
minterms(m::Manager, x::BDDNode, nvars::Integer)::Float64 =
    ccall((:Cudd_CountMinterm, libcudd), Cdouble,
          (Ptr{DdManager}, Ptr{DdNode}, Cint), m.ptr, x.ptr, nvars)

"""dag_size(x)

Return the DAG size (node count) of the given `BDDNode`.
"""
dag_size(x::BDDNode)::Cint =
    ccall((:Cudd_DagSize, libcudd), Cint, (Ptr{DdNode},), x.ptr)

"""node_index(n)

Return the variable index tested at the root of node `n`.
"""
function node_index(n::BDDNode)::Cint
    return ccall((:Cudd_NodeReadIndex, libcudd), Cint, (Ptr{DdNode},), n.ptr)
end

"""isconstant(n)

Return true if `n` is a terminal constant node.
"""
function isconstant(n::BDDNode)::Bool
    return ccall((:Cudd_IsConstant, libcudd), Cint, (Ptr{DdNode},), n.ptr) != 0
end

end
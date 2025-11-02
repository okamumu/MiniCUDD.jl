
using Test
using MiniCUDD

"""Compute probability of a BDD node assuming independent variable probabilities in `ps`.
Memoized traversal over the BDD returned by MiniCUDD.
"""
function bdd_probability(mgr::MiniCUDD.Manager, node::MiniCUDD.BDDNode, ps::Vector{Float64})
    memo = Dict{Ptr{Cvoid}, Float64}()
    oneptr = MiniCUDD.const1(mgr).ptr
    function go(n::MiniCUDD.BDDNode)
        key = Ptr{Cvoid}(n.ptr)
        if haskey(memo, key)
            return memo[key]
        end
        if MiniCUDD.isconstant(n)
            v = (n.ptr == oneptr) ? 1.0 : 0.0
            memo[key] = v
            return v
        end
        i = Int(MiniCUDD.node_index(n)) + 1
        t = MiniCUDD.bdd_then(mgr, n)
        e = MiniCUDD.bdd_else(mgr, n)
        pt = go(t)
        pe = go(e)
        pvar = ps[i]
        val = pvar * pt + (1.0 - pvar) * pe
        memo[key] = val
        return val
    end
    return go(node)
end

@testset "BDD probability basic tests" begin
    mgr = MiniCUDD.Manager(nvars=3)
    vars = [MiniCUDD.var(mgr, i-1) for i in 1:3]
    ps = [0.1, 0.2, 0.3]

    # P(A AND B) = 0.1 * 0.2
    and_ab = MiniCUDD.bdd_and(mgr, vars[1], vars[2])
    @test isapprox(bdd_probability(mgr, and_ab, ps), 0.02; atol=1e-12)

    # P(A OR B OR C) = 1 - (1-0.1)*(1-0.2)*(1-0.3) = 0.496
    or_ab = MiniCUDD.bdd_or(mgr, vars[1], vars[2])
    or_abc = MiniCUDD.bdd_or(mgr, or_ab, vars[3])
    @test isapprox(bdd_probability(mgr, or_abc, ps), 0.496; atol=1e-12)

    # P(at least 2 of {A,B,C}) = 0.098
    ab = MiniCUDD.bdd_and(mgr, vars[1], vars[2])
    ac = MiniCUDD.bdd_and(mgr, vars[1], vars[3])
    bc = MiniCUDD.bdd_and(mgr, vars[2], vars[3])
    k2 = MiniCUDD.bdd_or(mgr, MiniCUDD.bdd_or(mgr, ab, ac), bc)
    @test isapprox(bdd_probability(mgr, k2, ps), 0.098; atol=1e-12)

    # P(A AND (B OR C)) = 0.1 * (1 - (1-0.2)*(1-0.3)) = 0.044
    bor = MiniCUDD.bdd_or(mgr, vars[2], vars[3])
    nested = MiniCUDD.bdd_and(mgr, vars[1], bor)
    @test isapprox(bdd_probability(mgr, nested, ps), 0.044; atol=1e-12)

    MiniCUDD.quit(mgr)
end

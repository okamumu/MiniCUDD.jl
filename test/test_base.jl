using MiniCUDD
using Test

@testset "BDD then/else pointer tests" begin
    m  = Manager()
    x0 = var(m, 0)
    x1 = var(m, 1)

    # construct x0 ∧ x1
    f_and = bdd_and(m, x0, x1)

    # 1) basic minterm verification
    @test minterms(m, f_and, 2) == 1.0  # AND of 2 variables has 1 true assignment

    # 2) then/else pointers (if C shim helpers are available)
    if isdefined(MiniCUDD, :then_ptr) && isdefined(MiniCUDD, :else_ptr)
        t = then_ptr(f_and)
        e = else_ptr(f_and)

        # For x0 ∧ x1 the then-branch (x0=1) should be x1, else (x0=0) should be 0
        @test t == x1.ptr
        @test e == const0(m).ptr

        # Also test a complemented node: ¬(x0 ∧ x1)
        nf = bdd_ite(m, f_and, const0(m), const1(m))

        # Complement pointer detection & inversion helper (kept here for tests)
        iscompl(p::Ptr{MiniCUDD.DdNode}) = (UInt(p) & 0x1) == 0x1
        compl(p::Ptr{MiniCUDD.DdNode})  = Ptr{MiniCUDD.DdNode}(UInt(p) ⊻ 0x1)

        # then should be ¬x1 and else should be 1
        @test then_ptr(nf) == compl(x1.ptr)
        @test else_ptr(nf) == const1(m).ptr
    end

    if isdefined(MiniCUDD, :bdd_then) && isdefined(MiniCUDD, :bdd_else)
        tnode = bdd_then(m, f_and)
        enode = bdd_else(m, f_and)
        @test minterms(m, tnode, 2) == 2.0  # then is x1: 2 assignments over 2 vars (2^1)
        @test minterms(m, enode, 2) == 0.0  # else is 0

        nf = bdd_ite(m, f_and, const0(m), const1(m))
        t2 = bdd_then(m, nf)  # still x1
        e2 = bdd_else(m, nf)  # 1
        @test minterms(m, t2, 2) == 2.0
        @test minterms(m, e2, 2) == 4.0  # constant 1 over 2 vars is 2^2 = 4
    end
end

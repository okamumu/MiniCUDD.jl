# MiniCUDD

[![CI](https://github.com/JuliaReliab/MiniCUDD.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/JuliaReliab/MiniCUDD.jl/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Julia 1.10](https://img.shields.io/badge/Julia-1.10-orange.svg)](https://julialang.org)

MiniCUDD is a lightweight, thin Julia wrapper around the CUDD BDD (Binary
Decision Diagram) library.

This package provides minimal bindings to the CUDD C API, exposing a small
set of primitives for constructing and manipulating BDDs: variable creation,
boolean operators, ITE, basic utilities (minterm counting, DAG size), and
helpers for accessing node children.

Status
------
- Julia compatibility: `julia = "1.10"` (see `Project.toml`)
- Native dependency: CUDD (`libcudd`). You can either use a system-installed
	`libcudd` or build CUDD locally using the included build script.

Repository
----------
https://github.com/JuliaReliab/MiniCUDD.jl

Installation (development/local)
--------------------------------
Add the package in development mode from the package root:

```bash
# From the Julia REPL
import Pkg
Pkg.develop(path=".")
```

Preparing the CUDD library
--------------------------
1) If a system `libcudd` is already installed and discoverable by your OS
	 dynamic loader (e.g. `libcudd.dylib` on macOS, `libcudd.so` on Linux), the
	 package should work as-is.

2) To build CUDD locally (recommended for reproducible builds), run the
	 package build step. The build requires `git`, `autoconf`, `automake`,
	 `libtool`, `make`, and a C compiler.

```bash
# zsh/Bash
julia --project=. -e 'using Pkg; Pkg.build("MiniCUDD")'
```

The build script is `deps/build.jl`. It clones the CUDD repository, builds a
shared library, and installs it into `deps/usr/lib/` under the package tree.
After a successful build the generated `deps/deps.jl` contains the resolved
library path.

Note (macOS): macOS has special rules for dynamic library loading (SIP,
`DYLD_LIBRARY_PATH` behavior). If you run into library loading errors, add the
package's `deps/usr/lib` to your environment for the session:

```bash
export DYLD_LIBRARY_PATH=$(pwd)/deps/usr/lib:$DYLD_LIBRARY_PATH  # macOS
export LD_LIBRARY_PATH=$(pwd)/deps/usr/lib:$LD_LIBRARY_PATH    # Linux
```

Quick example
-------------

```julia
using MiniCUDD

mgr = Manager(nvars=4)
v0 = var(mgr, 0)
v1 = var(mgr, 1)
f = bdd_and(mgr, v0, v1)
println("DAG size: ", dag_size(f))
println("minterms: ", minterms(mgr, f, 2))
quit(mgr)
```

API highlights
--------------
- Types: `Manager`, `BDDNode`
- Create a manager: `Manager(; nvars=0, slots=256, cachesize=262144)`
- Variables: `var(mgr, i)`
- Constants: `const1(mgr)`, `const0(mgr)`
- Boolean ops: `bdd_and`, `bdd_or`, `bdd_xor`, `bdd_implies`, `bdd_ite`
- Utilities: `minterms`, `dag_size`, `node_index`, `isconstant`
- Child accessors: `bdd_then`, `bdd_else`, `then_ptr`, `else_ptr`
- Resource management: `close!(node)`, `quit(mgr)`

Tests
-----
Unit tests live in `test/`. If the native library is available, run the tests
from the project root with:

```bash
julia --project=. -e 'using Pkg; Pkg.test("MiniCUDD")'
```

Contributing
------------
- Issues and pull requests are welcome.
- Building native libraries can differ across environments; consider adding CI
	(GitHub Actions or a Docker-based runner) that sets up and builds CUDD for
	reproducible testing.

License
-------
This package is licensed under the MIT License. See the included `LICENSE`
file for the full text.

Author
------
Hiroyuki Okamura <okamu@hiroshima-u.ac.jp>

Notes
-----
This README was written from the package sources (`deps/build.jl`,
`src/MiniCUDD.jl`, `Project.toml`). Tell me if you want additional sections
such as API reference, examples, or CI configuration snippets.

CI hint
-------
If you want GitHub Actions to run tests, you can either:

- Build CUDD during the workflow (requires autoconf/automake/libtool and a
	C toolchain). This is reproducible but increases CI runtime.
- Provide prebuilt `libcudd` binaries for each runner and download them in
	the workflow. This is faster but requires maintaining binaries.

I can add a starter `.github/workflows/ci.yml` that attempts to build CUDD on
Linux and macOS. Tell me which approach you prefer and I will add the CI file.

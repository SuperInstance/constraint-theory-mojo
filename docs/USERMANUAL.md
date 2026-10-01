# USERMANUAL — constraint-theory-mojo

On-box verified 2026-10-01 against Mojo **1.2.0.dev2026100105** (f262223d), CPU-only, WSL2.

## What this is

A small **INT8-saturated range-constraint engine** ("FLUX") in three layers:

1. **`src/*.mojo`** — the primary Mojo implementation. A `Constraint` is a
   `[lo, hi]` range (both bounds saturated to `[-127, 127]` at construction)
   with a name and severity (0=PASS, 1=CAUTION, 2=WARNING, 3=CRITICAL).
   `check(value)` saturates the value to `[-127, 127]` and range-compares it.
   `ConstraintEngine` holds a `List[Constraint]`, provides single/batch/SIMD
   checking, a micro-benchmark, and two industry presets (see below).
2. **`flux/`** — a **pure-Python fallback with the same API** (active code;
   exercised by CI). NOT related to the MLIR dialect despite the shared name.
3. **`mlir/`** — an **illustrative dialect spec, not code**. `flux_dialect.mlir`
   sketches the FLUX MLIR dialect (`flux.sat8`, `flux.check`, `flux.batch_check`)
   and its intended lowerings. The file says so itself ("In practice, this
   would be a C++ dialect registered with MLIR"). It is **not** valid MLIR as
   committed (unregistered `flux.*` ops, a malformed `vector.maskedload` in
   `batch_check_avx512`), and **no `mlir-opt` exists on this box to verify it
   against** — treat it as a design document. Do not "fix" it without booking
   that as a semantic change.

**Preset drift (booked, not fixed — semantic changes are out of scope for the
port):** the Mojo presets and the Python-fallback presets are NOT identical,
despite CONTRIBUTING.md's "zero mismatches" claim:

| Preset | Mojo (`src/engine.mojo`) | Python (`flux/__init__.py`) | README claims |
|---|---|---|---|
| automotive | 7 constraints | 5 constraints (no `steering_angle`, `brake_pressure`) | 27 |
| aviation | 6 constraints | 4 constraints (no `fuel_flow`, `temperature`) | 28 |

Shared constraints behave **identically** across all layers (verified below).
Also booked: README says "License Apache 2.0" but LICENSE is MIT (commit
"Add MIT license"). The README table's constraint counts (27/28/23/25/25/23)
match neither implementation — they are aspirational.

## Quickstart

Route A (pixi, verified — imports resolve via `-I` because they bind to the
**main file's** directory, not the CWD):

```bash
cd /home/eileen/projects/quilt-mojo-lab
/home/eileen/.pixi/bin/pixi run mojo run \
  -I /home/eileen/projects/constraint-theory-mojo/src \
  /home/eileen/projects/constraint-theory-mojo/examples/demo.mojo
```

Route B (bare `mojo`, verified from the repo root):

```bash
export MODULAR_HOME=/home/eileen/projects/quilt-mojo-lab/.pixi/envs/default/share/max
export PATH=/home/eileen/projects/quilt-mojo-lab/.pixi/envs/default/bin:$PATH
cd /home/eileen/projects/constraint-theory-mojo
mojo run -I src examples/demo.mojo
```

Without `MODULAR_HOME` the compiler reports `unable to locate module 'std'`
(a bare PATH export is not enough — the conda activation script normally sets
it). Expect ~14–15M engine checks/sec from the demo benchmark (7 constraints
per `check`, scalar List loop, debug-free build).

Note: `src/` uses **flat module imports** (`from constraint import ...`), so
always pass `-I src`. The original `from flux.engine import ...` in
examples/demo.mojo was unresolvable — `flux/` is a Python package, not a Mojo
one — and was rewritten to the flat imports above.

## Layout

```
src/constraint.mojo    saturate_i8, Severity (dead code, kept), ConstraintResult, Constraint (+check_batch via raw Pointer)
src/engine.mojo        ConstraintEngine (List-based), check_batch_simd (per-lane fallback, see traps), benchmark, automotive_engine, aviation_engine
examples/demo.mojo     receipt demo (per-constraint verdicts for value 60) + benchmark
tests/test_engine.mojo 48 Counters checks + 66 machine-readable PARITY lines (no tests/ existed before this port)
python/oracle.py       independent spec oracle + parity runner + preset-drift audit
flux/__init__.py       Python fallback (Engine, Constraint, presets) — CI-tested
mlir/flux_dialect.mlir dialect SPEC ONLY (not runnable, unverified)
.github/workflows/ci.yml  tests the Python fallback only
```

## Test contract

```bash
# 1. Build + run the Mojo suite (flags BEFORE filename, always)
pixi run mojo build -I src tests/test_engine.mojo -o /tmp/ctm_test
/tmp/ctm_test            # prints RESULT pass= 48 fail= 0, exit code = fail count

# 2. Parity vs the independent oracle
python3 python/oracle.py /tmp/ctm_test   # 66/66 cases, exits nonzero on mismatch

# 3. Python fallback (CI contract)
python3 -m pytest tests/  # NOT APPLICABLE — no pytest tests exist; CI runs inline asserts:
python3 -c "import sys; sys.path.insert(0,'.'); from flux import automotive, aviation, saturate_i8, Constraint; assert saturate_i8(200)==127; assert saturate_i8(-200)==-127; assert saturate_i8(50)==50; c=Constraint(15,55,'battery_temp',3); r=c.check(60); assert not r.passed and r.severity==3; assert len(automotive().constraints)==5; print('ok')"
```

Covered cases (≥5, incl. degenerate): saturation at Int32 extremes and both
INT8 boundaries; lo/hi boundary equality passes; inverted range `lo > hi`
fails everything (even midpoints); single-point range `lo == hi`; out-of-INT8
bounds `(500, 600)` saturate to a point constraint at 127; engine-level
automotive check(60) (exactly 2 fails) and check(−40) (exactly 6 fails);
aviation check(0) (0 fails); 16-lane SIMD case (exactly 4 lanes pass); raw
Pointer batch API.

**Parity verdict (2026-10-01): 66/66 OK, 0 mismatches** between the Mojo
binary, the independent oracle, and (on shared constraints) the Python
fallback. Hardcoded constants in tests verified against live computation by
the Counters harness (48/48).

## Receipt (this box, 2026-10-01)

- Toolchain: Mojo 1.2.0.dev2026100105 via quilt-mojo-lab pixi env (route A)
  and bare `mojo` with MODULAR_HOME (route B). CPU-only.
- Build: `src/constraint.mojo`, `src/engine.mojo`, `tests/test_engine.mojo`,
  `examples/demo.mojo` — all compile. Remaining diagnostics are **deprecation
  warnings only** (`alloc` without Layout, positional `__getitem__`), accepted
  for API parity; the suggested `unsafe_alloc` is NOT prelude-resolvable here.
- Tests: 48 pass / 0 fail. Parity: 66/66. Python fallback: all CI asserts pass.
- Demo: receipt for automotive check(60) — 7 constraints, 2 failures
  (lateral_speed sev 2, battery_temp sev 3) — then 1M-iteration benchmark at
  ~14.6–15.1M checks/sec.
- `mlir/flux_dialect.mlir`: unverified (no mlir-opt on box); spec-only.

## Troubleshooting — NEW traps banked on this box (Mojo 1.2.0.dev2026100105)

Beyond the fleet traps already banked (flags-before-filename; `-I src` for
src/-layouts; variadic List init banned; List-holding structs not
ImplicitlyCopyable; `math`→`from std import math`):

1. **`fn` is REMOVED** — parse error `use of unknown declaration` →
   `'fn' has been removed; use 'def' instead`. Everything is `def` now.
2. **`@value` decorator is REMOVED** — plain `struct` (the errors point at the
   `@value` lines: "use of unknown declaration 'value'"). Value semantics are
   the default.
3. **Pointer deprecated TWICE the other way**: `UnsafePointer` is now the
   deprecated name; the canonical is `Pointer[T, MutUntrackedOrigin]` (origin
   is the second parameter). `Pointer[Int32, _]` in a signature is rejected
   ("not concrete"); in-body `alloc[T](n)` is prelude-resolved.
4. **`unsafe_alloc` is NOT prelude-resolved** even with a `from std import`
   line, while deprecated `alloc` is. If you want `unsafe_alloc`, find its
   module first (not found on this box; not `std.memory` blindly).
5. **No-self methods need `@staticmethod`** — `def PASS() -> Severity` errors
   "self argument must be present in instance method".
6. **Implicit field-wise ctors require a `move` argument** ("missing required
   argument: 'move'") — write an explicit `def __init__(out self, ...)` when
   constructing a struct from literals.
7. **`StringRef` is gone from the prelude** — use `String`.
8. **`from std import time`** (package import); the callable is
   `time.perf_counter_ns()` (Int nanoseconds). `from std.time import now` and
   `from time import now` both fail; `benchmark.now()` is gone.
9. **SIMD comparisons reduce to scalar `Bool`** (all-lanes AND) — there are no
   per-lane masks from `>=`/`<=` anymore. And **elementwise SIMD `max`/`min`
   are gone in BOTH forms** (free functions errored "function instantiation
   failed"; `.max()`/`.min()` methods "has no attribute") — both still worked
   on the 20260930 nightly (see quilt-mojo-lab/docs/MOJO-NOTES.md wave-69).
   `check_batch_simd` is now an honest per-lane loop with identical results.
10. **`SIMD[DType.bool, N](False)` fails to instantiate** — splat from `0`
    (`SIMD[DType.bool, N](0)`) works, and per-lane `out[lane] = <Bool>` works.
11. **`mut self` for mutating methods** — `self.x += 1` through a plain
    `def`-self errors "expression must be mutable for in-place operator
    destination"; `self.list.append(...)` errors "mutating method on rvalue".
    Mark the method `def add(mut self, ...)`.
12. **No move-out of List subscript**: `results[i]^` errors "expression does
    not designate a value with an origin", and a plain `var r = results[i]`
    errors "cannot be implicitly copied". Read fields by borrow
    (`results[i].field`) or rebuild via an explicit constructor.
13. **`return engine` for a List-holding struct** needs `return engine^`
    (transfer) — ConstraintEngine doesn't conform to ImplicitlyCopyable.
14. **f-string format specs are a parse error** — `f"{rate:.0f}"` →
    "expected ')' in call argument list". Round manually:
    `print("Throughput:", Int(rate + 0.5))`.
15. **Runtime Int → Int32 is not implicit** — `self.check(i % 256 - 128)`
    fails instantiation when the method is first instantiated (may stay hidden
    if no caller triggers it — the test suite didn't, the demo did). Cast:
    `Int32(i % 256 - 128)`.
16. **Prelude-quirk confirmation**: `Pointer`/`alloc` resolve only with ≥1
    `from std import ...` line present (reproduced here; see
    quilt-mojo-lab/docs/MOJO-NOTES.md).

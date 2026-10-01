"""Quick demo of FLUX constraint engine in Mojo.

Prints a per-constraint receipt for the automotive preset, then benchmarks.
Run from the repo root:
    mojo run -I src examples/demo.mojo
"""

from engine import ConstraintEngine, automotive_engine
from constraint import saturate_i8

def main():
    print("=== FLUX Constraint Engine (Mojo) ===")
    print()

    # Single check
    var val: Int32 = 60
    var sat = saturate_i8(val)
    print("saturate_i8(60) =", sat)
    print("saturate_i8(200) =", saturate_i8(200))
    print("saturate_i8(-200) =", saturate_i8(-200))

    # Automotive engine
    var engine = automotive_engine()

    # Check a value and print a receipt
    var value: Int32 = 60
    var results = engine.check(value)
    print()
    print("+----------------------------------------------+")
    print("| FLUX receipt: automotive preset, value =", value, "|")
    print("+----------------------------------------------+")
    var fails: Int = 0
    for i in range(len(results)):
        # List subscript yields an originless ref: no `^` move-out, no copy.
        # Read fields by borrow instead (fleet trap: rebuild-via-ctor or borrow).
        var passed = results[i].passed
        var status: String = "PASS" if passed else "FAIL"
        if not passed:
            fails += 1
        print("| ", results[i].constraint_name, "->", status, "sev =", results[i].severity)
    print("+----------------------------------------------+")
    print("| total constraints:", len(results), " fail:", fails)
    print("+----------------------------------------------+")

    # Benchmark
    print()
    print("Running benchmark (1M iterations)...")
    var rate = engine.benchmark(1_000_000)
    # f-string format specs are a parse error in 1.2; round manually.
    print("Throughput:", Int(rate + 0.5), "checks/sec")

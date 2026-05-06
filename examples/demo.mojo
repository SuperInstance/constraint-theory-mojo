"""Quick demo of FLUX constraint engine in Mojo."""

from flux.engine import ConstraintEngine, automotive_engine
from flux.constraint import saturate_i8

fn main():
    print("=== FLUX Constraint Engine (Mojo) ===")
    print()
    
    # Single check
    let val: Int32 = 60
    let sat = saturate_i8(val)
    print("saturate_i8(60) =", sat)
    
    # Automotive engine
    var engine = automotive_engine()
    
    # Check a value
    let results = engine.check(60)
    print()
    print("Checking value 60 against automotive constraints:")
    for i in range(len(results)):
        let r = results[i]
        if not r.passed:
            print("  FAIL:", r.constraint_name, "(severity:", r.severity, ")")
    
    # Benchmark
    print()
    print("Running benchmark (1M iterations)...")
    let rate = engine.benchmark(1_000_000)
    print(f"Throughput: {rate:.0f} checks/sec")

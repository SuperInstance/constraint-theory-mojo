# constraint-theory-mojo

**Mojo + MLIR constraint engine** — the "AI-Next" approach to constraint theory.

Mojo combines Python's usability with C-level performance, built on MLIR (Multi-Level Intermediate Representation) which is part of the LLVM ecosystem. This makes it a natural fit for constraint theory — we can express constraints at a high level while the MLIR backend handles hardware-specific optimization.

## Why Mojo?

| Feature | Mojo | C++ | Rust |
|---------|------|-----|------|
| Python syntax | ✅ | ❌ | ❌ |
| Zero-cost abstractions | ✅ | ✅ | ✅ |
| MLIR-native | ✅ | ❌ | ❌ |
| Autotuning | ✅ | Manual | Manual |
| GPU kernel authoring | ✅ (native) | CUDA | CUDA |
| Memory safety | Ownership | Manual | Borrow checker |

The key insight: **Mojo is built on the same MLIR infrastructure as LLVM**. Our constraint theory logic can be expressed as a custom MLIR dialect, then Mojo provides the ergonomic frontend.

## Architecture

```
┌─────────────────────────────────┐
│  Mojo Frontend (Python-like)    │  ← User writes constraints here
│  constraint_check(value, lo, hi)│
├─────────────────────────────────┤
│  MLIR Dialect (FLUX dialect)    │  ← Domain-specific optimizations
│  flux.check %val, %lo, %hi      │
├─────────────────────────────────┤
│  LLVM IR Lowering               │  ← Standard compilation pipeline
│  AVX-512 / ARM SVE / GPU        │
└─────────────────────────────────┘
```

## Quick Start

```python
from flux import Constraint, Engine, Preset

# Define a constraint
battery = Constraint(lo=15, hi=55, name="battery_temp", severity="CRITICAL")

# Check a value
result = battery.check(60)
print(result.passed)  # False
print(result.severity)  # CRITICAL

# Use a preset
engine = Engine.from_preset("automotive")
results = engine.check_batch([0, 60, 120, 250, 300])

# Benchmark
checks_per_sec = engine.benchmark(iterations=1_000_000)
print(f"{checks_per_sec:.0f} checks/sec")

# GPU kernel (Mojo native!)
@flux.gpu_kernel
def check_constraints_gpu(values: SIMD[DType.int32, 16],
                          constraints: SIMD[DType.int32, 32]) -> Bool:
    """Check 16 values against constraints on GPU."""
    lo = constraints[0]
    hi = constraints[1]
    return (values >= lo) & (values <= hi)
```

## Industry Presets

| Preset | Standard | Constraints | Severity |
|--------|----------|-------------|----------|
| `automotive` | ISO 26262 | 27 constraints | ASIL-D |
| `aviation` | DO-178C | 28 constraints | DAL-A |
| `nuclear` | NRC 10 CFR 50 | 23 constraints | SIL-4 |
| `medical` | IEC 62304 | 25 constraints | Class C |
| `marine` | IACS | 25 constraints | Notation |
| `space` | ECSS/ESA | 23 constraints | Category A |

## MLIR Integration

The real power is custom MLIR dialects. We define:

```mlir
// FLUX dialect — constraint operations as first-class IR
flux.check_constraint %val, %lo, %hi : i32, i32, i32 -> i1
flux.batch_check %values: memref<16xi32>, %constraints: memref<5x2xi32> -> memref<16xi1>
flux.sat8 %val : i32 -> i32  // INT8 saturation
```

These can be lowered through standard MLIR passes:
- `flux.check_constraint` → `arith.cmpi` + `arith.andi`
- `flux.batch_check` → vectorized `llvm.x86.avx512.*` intrinsics
- `flux.sat8` → `arith.select` + `arith.cmpi` (branchless)

## Performance Telemetry

Integration with LLVM-MCA (Machine Code Analyzer) for bottleneck analysis:

```python
from flux import telemetry

with telemetry.profile() as prof:
    engine.check_batch(values)

print(prof.bottleneck)       # "Memory-bound at 35.9 GB/s"
print(prof.throughput)       # "62.2B constraints/sec"
print(prof.vectorization)    # "AVX-512: 16x parallel"
```

## Status

🚧 **Early development** — Mojo is evolving rapidly. This repo tracks the latest Mojo nightly.

## License

Apache 2.0

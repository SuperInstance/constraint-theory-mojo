"""Constraint engine — orchestrates multiple constraints."""

from constraint import Constraint, ConstraintResult, saturate_i8
from std import time

struct ConstraintEngine:
    """Engine that manages multiple constraints and provides batch checking."""
    var constraints: List[Constraint]

    def __init__(out self):
        self.constraints = List[Constraint]()

    def add(mut self, lo: Int32, hi: Int32, name: String, severity: UInt8 = 0):
        """Add a constraint to the engine."""
        self.constraints.append(Constraint(lo, hi, name, severity))

    def check(self, value: Int32) -> List[ConstraintResult]:
        """Check a value against all constraints."""
        var results = List[ConstraintResult]()
        var sv = saturate_i8(value)
        for i in range(len(self.constraints)):
            results.append(self.constraints[i].check(sv))
        return results^

    def check_batch(self, values: Pointer[Int32, MutUntrackedOrigin], count: Int) -> List[List[ConstraintResult]]:
        """Check a batch of values against all constraints."""
        var results = List[List[ConstraintResult]]()
        for i in range(count):
            results.append(self.check(values[i]))
        return results^

    def check_batch_simd(self, values: SIMD[DType.int32, 16],
                        lo: SIMD[DType.int32, 16],
                        hi: SIMD[DType.int32, 16]) -> SIMD[DType.bool, 16]:
        """SIMD batch check — 16 values at once.

        NOTE (1.2.0.dev2026100105): elementwise SIMD max/min (both free
        functions and .max()/.min() methods) are gone on this nightly, and
        SIMD comparisons now reduce to a scalar Bool instead of producing a
        lane mask. Saturation + compare is therefore computed per lane;
        results are identical to the original vectorized formulation
        (verified by tests + python/oracle.py).
        """
        var out = SIMD[DType.bool, 16](0)
        for lane in range(16):
            var v = values[lane]
            var s: Int32
            if v < -127:
                s = -127
            elif v > 127:
                s = 127
            else:
                s = v
            out[lane] = (s >= lo[lane]) & (s <= hi[lane])
        return out

    def benchmark(self, iterations: Int = 1000000) -> Float64:
        """Run benchmark and return checks/sec."""
        # Simple microbenchmark. `benchmark.now()` is gone in 1.2;
        # std.time.perf_counter_ns() returns Int nanoseconds.
        var counter: Int = 0
        var start = time.perf_counter_ns()
        for i in range(iterations):
            _ = self.check(Int32(i % 256 - 128))
            counter += 1
        var elapsed = Float64(time.perf_counter_ns() - start)
        return Float64(counter) / elapsed * 1e9

# Preset engines
def automotive_engine() -> ConstraintEngine:
    """ISO 26262 automotive preset."""
    var engine = ConstraintEngine()
    engine.add(0, 250, "vehicle_speed", 2)
    engine.add(-15, 15, "lateral_speed", 2)
    engine.add(15, 55, "battery_temp", 3)
    engine.add(-40, 85, "ambient_temp", 1)
    engine.add(0, 100, "charge_rate", 2)
    engine.add(0, 360, "steering_angle", 2)
    engine.add(0, 5000, "brake_pressure", 3)
    return engine^

def aviation_engine() -> ConstraintEngine:
    """DO-178C aviation preset."""
    var engine = ConstraintEngine()
    engine.add(-1000, 45000, "altitude", 3)
    engine.add(0, 350, "airspeed", 3)
    engine.add(-25, 25, "pitch", 3)
    engine.add(-45, 45, "roll", 3)
    engine.add(0, 100, "fuel_flow", 3)
    engine.add(-127, 127, "temperature", 2)
    return engine^

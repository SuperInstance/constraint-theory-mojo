"""Constraint engine — orchestrates multiple constraints."""

from constraint import Constraint, ConstraintResult, saturate_i8

@value
struct ConstraintEngine(CollectionElement):
    """Engine that manages multiple constraints and provides batch checking."""
    var constraints: DynamicVector[Constraint]
    
    fn __init__(out self):
        self.constraints = DynamicVector[Constraint]()
    
    fn add(self, lo: Int32, hi: Int32, name: StringRef, severity: UInt8 = 0):
        """Add a constraint to the engine."""
        self.constraints.push_back(Constraint(lo, hi, name, severity))
    
    fn check(self, value: Int32) -> DynamicVector[ConstraintResult]:
        """Check a value against all constraints."""
        var results = DynamicVector[ConstraintResult]()
        let sv = saturate_i8(value)
        for i in range(len(self.constraints)):
            results.push_back(self.constraints[i].check(sv))
        return results
    
    fn check_batch(self, values: Pointer[Int32], count: Int) -> DynamicVector[DynamicVector[ConstraintResult]]:
        """Check a batch of values against all constraints."""
        var results = DynamicVector[DynamicVector[ConstraintResult]]()
        for i in range(count):
            results.push_back(self.check(values[i]))
        return results
    
    fn check_batch_simd(self, values: SIMD[DType.int32, 16], 
                        lo: SIMD[DType.int32, 16],
                        hi: SIMD[DType.int32, 16]) -> SIMD[DType.bool, 16]:
        """SIMD batch check — 16 values at once."""
        let sv_lo = max(values, SIMD[DType.int32, 16](-127))
        let sv = min(sv_lo, SIMD[DType.int32, 16](127))
        return (sv >= lo) & (sv <= hi)
    
    fn benchmark(self, iterations: Int = 1000000) -> Float64:
        """Run benchmark and return checks/sec."""
        # Simple microbenchmark
        var counter: Int = 0
        let start = benchmark.now()
        for i in range(iterations):
            let _ = self.check(i % 256 - 128)
            counter += 1
        let elapsed = (benchmark.now() - start).to_float64()
        return Float64(counter) / elapsed * 1e9

# Preset engines
fn automotive_engine() -> ConstraintEngine:
    """ISO 26262 automotive preset."""
    var engine = ConstraintEngine()
    engine.add(0, 250, "vehicle_speed", 2)
    engine.add(-15, 15, "lateral_speed", 2)
    engine.add(15, 55, "battery_temp", 3)
    engine.add(-40, 85, "ambient_temp", 1)
    engine.add(0, 100, "charge_rate", 2)
    engine.add(0, 360, "steering_angle", 2)
    engine.add(0, 5000, "brake_pressure", 3)
    return engine

fn aviation_engine() -> ConstraintEngine:
    """DO-178C aviation preset."""
    var engine = ConstraintEngine()
    engine.add(-1000, 45000, "altitude", 3)
    engine.add(0, 350, "airspeed", 3)
    engine.add(-25, 25, "pitch", 3)
    engine.add(-45, 45, "roll", 3)
    engine.add(0, 100, "fuel_flow", 3)
    engine.add(-127, 127, "temperature", 2)
    return engine

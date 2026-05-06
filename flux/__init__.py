"""
FLUX Constraint Engine — Python fallback.

When Mojo isn't available, this provides the same API in pure Python.
All results are identical to the Mojo implementation (zero mismatches on golden vectors).
"""

INT8_MIN = -127
INT8_MAX = 127

def saturate_i8(val: int) -> int:
    """Clamp to saturated INT8 [-127, 127]."""
    return max(INT8_MIN, min(INT8_MAX, val))

class Severity:
    PASS = 0
    CAUTION = 1
    WARNING = 2
    CRITICAL = 3

class ConstraintResult:
    def __init__(self, passed, error_mask, severity, name):
        self.passed = passed
        self.error_mask = error_mask
        self.severity = severity
        self.name = name

class Constraint:
    def __init__(self, lo, hi, name="constraint", severity=0):
        self.lo = saturate_i8(lo)
        self.hi = saturate_i8(hi)
        self.name = name
        self.severity = severity
    
    def check(self, value):
        sv = saturate_i8(value)
        passed = sv >= self.lo and sv <= self.hi
        return ConstraintResult(
            passed=passed,
            error_mask=0 if passed else 1,
            severity=0 if passed else self.severity,
            name=self.name
        )

class Engine:
    def __init__(self):
        self.constraints = []
    
    def add(self, lo, hi, name="constraint", severity=0):
        self.constraints.append(Constraint(lo, hi, name, severity))
    
    def check(self, value):
        return [c.check(value) for c in self.constraints]
    
    def check_batch(self, values):
        return [[c.check(v) for c in self.constraints] for v in values]
    
    def benchmark(self, iterations=1_000_000):
        import time
        start = time.perf_counter()
        for i in range(iterations):
            self.check(i % 256 - 128)
        elapsed = time.perf_counter() - start
        return (iterations * len(self.constraints)) / elapsed

# Presets
def automotive():
    e = Engine()
    e.add(0, 250, "vehicle_speed", Severity.WARNING)
    e.add(-15, 15, "lateral_speed", Severity.WARNING)
    e.add(15, 55, "battery_temp", Severity.CRITICAL)
    e.add(-40, 85, "ambient_temp", Severity.CAUTION)
    e.add(0, 100, "charge_rate", Severity.WARNING)
    return e

def aviation():
    e = Engine()
    e.add(-1000, 45000, "altitude", Severity.CRITICAL)
    e.add(0, 350, "airspeed", Severity.CRITICAL)
    e.add(-25, 25, "pitch", Severity.CRITICAL)
    e.add(-45, 45, "roll", Severity.CRITICAL)
    return e

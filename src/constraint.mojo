"""Core constraint types for FLUX constraint engine in Mojo."""

const INT8_MIN: Int32 = -127
const INT8_MAX: Int32 = 127

@value
struct Severity(CollectionElement):
    """Constraint violation severity."""
    var value: UInt8
    
    fn PASS() -> Severity:
        return Severity(0)
    fn CAUTION() -> Severity:
        return Severity(1)
    fn WARNING() -> Severity:
        return Severity(2)
    fn CRITICAL() -> Severity:
        return Severity(3)

fn saturate_i8(val: Int32) -> Int32:
    """Clamp to saturated INT8 [-127, 127]."""
    if val < INT8_MIN:
        return INT8_MIN
    elif val > INT8_MAX:
        return INT8_MAX
    else:
        return val

@value
struct ConstraintResult(CollectionElement):
    """Result of a constraint check."""
    var passed: Bool
    var error_mask: UInt8
    var severity: UInt8
    var constraint_name: StringRef
    
    fn __init__(out self, passed: Bool, error_mask: UInt8, 
                severity: UInt8, name: StringRef):
        self.passed = passed
        self.error_mask = error_mask
        self.severity = severity
        self.constraint_name = name

@value
struct Constraint(CollectionElement):
    """A single INT8-saturated range constraint."""
    var lo: Int32
    var hi: Int32
    var name: StringRef
    var severity: UInt8
    
    fn __init__(out self, lo: Int32, hi: Int32, name: StringRef, 
                severity: UInt8 = 0):
        self.lo = saturate_i8(lo)
        self.hi = saturate_i8(hi)
        self.name = name
        self.severity = severity
    
    fn check(self, value: Int32) -> ConstraintResult:
        """Check a single value against this constraint."""
        let sv = saturate_i8(value)
        let passed = sv >= self.lo and sv <= self.hi
        let mask: UInt8 = 0 if passed else 1
        let sev: UInt8 = 0 if passed else self.severity
        return ConstraintResult(passed, mask, sev, self.name)
    
    fn check_batch(self, values: Pointer[Int32], count: Int) -> Pointer[ConstraintResult]:
        """Check a batch of values. Returns array of results."""
        var results = Pointer[ConstraintResult].alloc(count)
        for i in range(count):
            results[i] = self.check(values[i])
        return results

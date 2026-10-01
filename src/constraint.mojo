"""Core constraint types for FLUX constraint engine in Mojo."""

# Prelude quirk (Mojo 1.2.0-dev): prelude symbols like Pointer and the free
# `alloc` function only resolve when the file has at least one
# `from std import ...` line (quilt-mojo-lab/docs/MOJO-NOTES.md). The `sys`
# import is unused but required.
from std import sys

# INT8 saturation bounds are [-127, 127]; inlined in saturate_i8() below
# (file-scope `const`/`alias`/`var` expressions are rejected in Mojo 1.2).


struct Severity:
    """Constraint violation severity."""
    var value: UInt8

    def __init__(out self, v: UInt8):
        self.value = v

    @staticmethod
    def PASS() -> Severity:
        return Severity(0)
    @staticmethod
    def CAUTION() -> Severity:
        return Severity(1)
    @staticmethod
    def WARNING() -> Severity:
        return Severity(2)
    @staticmethod
    def CRITICAL() -> Severity:
        return Severity(3)

def saturate_i8(val: Int32) -> Int32:
    """Clamp to saturated INT8 [-127, 127]."""
    if val < -127:
        return -127
    elif val > 127:
        return 127
    else:
        return val

struct ConstraintResult:
    """Result of a constraint check."""
    var passed: Bool
    var error_mask: UInt8
    var severity: UInt8
    var constraint_name: String

    def __init__(out self, passed: Bool, error_mask: UInt8,
                severity: UInt8, name: String):
        self.passed = passed
        self.error_mask = error_mask
        self.severity = severity
        self.constraint_name = name

struct Constraint:
    """A single INT8-saturated range constraint."""
    var lo: Int32
    var hi: Int32
    var name: String
    var severity: UInt8

    def __init__(out self, lo: Int32, hi: Int32, name: String,
                severity: UInt8 = 0):
        self.lo = saturate_i8(lo)
        self.hi = saturate_i8(hi)
        self.name = name
        self.severity = severity

    def check(self, value: Int32) -> ConstraintResult:
        """Check a single value against this constraint."""
        var sv = saturate_i8(value)
        var passed = sv >= self.lo and sv <= self.hi
        var mask: UInt8 = 0 if passed else 1
        var sev: UInt8 = 0 if passed else self.severity
        return ConstraintResult(passed, mask, sev, self.name)

    def check_batch(self, values: Pointer[Int32, MutUntrackedOrigin], count: Int) -> Pointer[ConstraintResult, MutUntrackedOrigin]:
        """Check a batch of values. Returns array of results."""
        # `unsafe_alloc` is NOT prelude-resolved on this nightly (unknown
        # declaration even with a `from std import` line); deprecated free
        # `alloc` is. Warnings are accepted for API parity with 24.x call sites.
        var results = alloc[ConstraintResult](count)
        for i in range(count):
            results[i] = self.check(values[i])
        return results

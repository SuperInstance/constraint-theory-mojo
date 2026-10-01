"""FLUX constraint engine — on-box test suite (Mojo 1.2.0-dev).

Run from the repo root (flags BEFORE filename; -I points at src/):
    mojo run -I src tests/test_engine.mojo

No builtin assert (uncallable in 1.2) — fleet Counters pattern instead.
Every Counters.check() verifies a hardcoded expectation against live
computation. PARITY lines are machine-readable and cross-checked by
python/oracle.py (independent oracle): python3 python/oracle.py <binary>
"""

from engine import ConstraintEngine, automotive_engine, aviation_engine
from constraint import Constraint, ConstraintResult, saturate_i8
from std import sys, time


struct Counters:
    var pass_count: Int
    var fail_count: Int

    def __init__(out self):
        self.pass_count = 0
        self.fail_count = 0

    def check(mut self, name: String, cond: Bool):
        if cond:
            self.pass_count += 1
        else:
            self.fail_count += 1
            print("FAIL:", name)


def p01(b: Bool) -> Int:
    return 1 if b else 0


def main():
    var c = Counters()

    # --- 1. saturate_i8: full-domain edges, incl. Int32 extremes ---
    c.check("sat(-2147483648) == -127", saturate_i8(-2147483648) == -127)
    c.check("sat(-200) == -127", saturate_i8(-200) == -127)
    c.check("sat(-128) == -127", saturate_i8(-128) == -127)
    c.check("sat(-127) == -127", saturate_i8(-127) == -127)
    c.check("sat(-126) == -126", saturate_i8(-126) == -126)
    c.check("sat(0) == 0", saturate_i8(0) == 0)
    c.check("sat(126) == 126", saturate_i8(126) == 126)
    c.check("sat(127) == 127", saturate_i8(127) == 127)
    c.check("sat(128) == 127", saturate_i8(128) == 127)
    c.check("sat(200) == 127", saturate_i8(200) == 127)
    c.check("sat(2147483647) == 127", saturate_i8(2147483647) == 127)
    var sat_inputs = List[Int32]()
    sat_inputs.append(-2147483648)
    sat_inputs.append(-200)
    sat_inputs.append(-128)
    sat_inputs.append(-127)
    sat_inputs.append(-126)
    sat_inputs.append(-1)
    sat_inputs.append(0)
    sat_inputs.append(1)
    sat_inputs.append(126)
    sat_inputs.append(127)
    sat_inputs.append(128)
    sat_inputs.append(200)
    sat_inputs.append(2147483647)
    for i in range(len(sat_inputs)):
        var v = sat_inputs[i]
        print("PARITY sat", v, saturate_i8(v))

    # --- 2. battery_temp (15, 55, sev=3): boundary semantics ---
    var battery = Constraint(15, 55, "battery_temp", 3)
    c.check("battery check(15) passes (lo boundary)", battery.check(15).passed)
    c.check("battery check(55) passes (hi boundary)", battery.check(55).passed)
    c.check("battery check(14) fails", not battery.check(14).passed)
    c.check("battery check(56) fails", not battery.check(56).passed)
    c.check("battery fail severity == 3", battery.check(56).severity == 3)
    c.check("battery pass severity == 0", battery.check(55).severity == 0)
    c.check("battery fail error_mask == 1", battery.check(56).error_mask == 1)
    c.check("battery pass error_mask == 0", battery.check(55).error_mask == 0)
    var battery_inputs = List[Int32]()
    battery_inputs.append(-127)
    battery_inputs.append(14)
    battery_inputs.append(15)
    battery_inputs.append(16)
    battery_inputs.append(54)
    battery_inputs.append(55)
    battery_inputs.append(56)
    battery_inputs.append(127)
    for i in range(len(battery_inputs)):
        var v = battery_inputs[i]
        var r = battery.check(v)
        print("PARITY check battery_temp", v, p01(r.passed), r.severity)

    # --- 3. DEGENERATE: inverted range lo > hi (55, 15) must fail everything ---
    var inverted = Constraint(55, 15, "inverted", 2)
    c.check("inverted check(15) fails", not inverted.check(15).passed)
    c.check("inverted check(30) fails (midpoint too)", not inverted.check(30).passed)
    c.check("inverted check(55) fails", not inverted.check(55).passed)
    var inverted_inputs = List[Int32]()
    inverted_inputs.append(15)
    inverted_inputs.append(30)
    inverted_inputs.append(55)
    for i in range(len(inverted_inputs)):
        var v = inverted_inputs[i]
        var r = inverted.check(v)
        print("PARITY check inverted", v, p01(r.passed), r.severity)

    # --- 4. DEGENERATE: single-point range lo == hi (42, 42) passes only 42 ---
    var point = Constraint(42, 42, "point", 1)
    c.check("point check(41) fails", not point.check(41).passed)
    c.check("point check(42) passes", point.check(42).passed)
    c.check("point check(43) fails", not point.check(43).passed)
    var point_inputs = List[Int32]()
    point_inputs.append(41)
    point_inputs.append(42)
    point_inputs.append(43)
    for i in range(len(point_inputs)):
        var v = point_inputs[i]
        var r = point.check(v)
        print("PARITY check point", v, p01(r.passed), r.severity)

    # --- 5. DEGENERATE: out-of-INT8 bounds (500, 600) saturate to point [127, 127] ---
    var clamped = Constraint(500, 600, "clamped", 3)
    c.check("clamped check(126) fails", not clamped.check(126).passed)
    c.check("clamped check(127) passes (bounds saturated)", clamped.check(127).passed)
    c.check("clamped check(-5) fails", not clamped.check(-5).passed)
    var clamped_inputs = List[Int32]()
    clamped_inputs.append(126)
    clamped_inputs.append(127)
    clamped_inputs.append(128)
    for i in range(len(clamped_inputs)):
        var v = clamped_inputs[i]
        var r = clamped.check(v)
        print("PARITY check clamped", v, p01(r.passed), r.severity)

    # --- 6. automotive engine: check(60), all 7 constraints ---
    var auto = automotive_engine()
    var results60 = auto.check(60)
    c.check("automotive has 7 constraints", len(auto.constraints) == 7)
    c.check("check(60) returns 7 results", len(results60) == 7)
    c.check("check(60): vehicle_speed passes", results60[0].passed)
    c.check("check(60): lateral_speed fails", not results60[1].passed)
    c.check("check(60): lateral_speed sev == 2", results60[1].severity == 2)
    c.check("check(60): battery_temp fails", not results60[2].passed)
    c.check("check(60): battery_temp sev == 3", results60[2].severity == 3)
    c.check("check(60): ambient_temp passes", results60[3].passed)
    c.check("check(60): charge_rate passes", results60[4].passed)
    c.check("check(60): steering_angle passes", results60[5].passed)
    c.check("check(60): brake_pressure passes", results60[6].passed)
    var fails60: Int = 0
    for i in range(len(results60)):
        if not results60[i].passed:
            fails60 += 1
    c.check("check(60): exactly 2 failures", fails60 == 2)
    for i in range(len(results60)):
        print("PARITY engine automotive 60", auto.constraints[i].name, p01(results60[i].passed), results60[i].severity)

    # --- 7. automotive engine: check(-40) ---
    var results_neg40 = auto.check(-40)
    var fails_neg40: Int = 0
    for i in range(len(results_neg40)):
        if not results_neg40[i].passed:
            fails_neg40 += 1
    c.check("check(-40): exactly 6 failures (only ambient_temp passes)", fails_neg40 == 6)
    c.check("check(-40): ambient_temp passes", results_neg40[3].passed)
    for i in range(len(results_neg40)):
        print("PARITY engine automotive -40", auto.constraints[i].name, p01(results_neg40[i].passed), results_neg40[i].severity)

    # --- 8. aviation engine: check(0), all 6 pass ---
    var av = aviation_engine()
    c.check("aviation has 6 constraints", len(av.constraints) == 6)
    var results_av = av.check(0)
    var fails_av: Int = 0
    for i in range(len(results_av)):
        if not results_av[i].passed:
            fails_av += 1
    c.check("aviation check(0): 0 failures", fails_av == 0)
    for i in range(len(results_av)):
        print("PARITY engine aviation 0", av.constraints[i].name, p01(results_av[i].passed), results_av[i].severity)

    # --- 9. SIMD batch check: 16 lanes, 4 expected passes ---
    var simd_values = SIMD[DType.int32, 16](0)
    var lane_inputs = List[Int32]()
    lane_inputs.append(-128)
    lane_inputs.append(-100)
    lane_inputs.append(0)
    lane_inputs.append(15)
    lane_inputs.append(16)
    lane_inputs.append(35)
    lane_inputs.append(55)
    lane_inputs.append(56)
    lane_inputs.append(100)
    lane_inputs.append(127)
    lane_inputs.append(-127)
    lane_inputs.append(200)
    lane_inputs.append(-55)
    lane_inputs.append(3)
    lane_inputs.append(66)
    lane_inputs.append(128)
    for lane in range(16):
        simd_values[lane] = lane_inputs[lane]
    var simd_lo = SIMD[DType.int32, 16](15)
    var simd_hi = SIMD[DType.int32, 16](55)
    var sim = ConstraintEngine()
    var simd_result = sim.check_batch_simd(simd_values, simd_lo, simd_hi)
    var simd_passes: Int = 0
    for lane in range(16):
        var hit = simd_result[lane]
        if hit:
            simd_passes += 1
        print("PARITY simd", lane, p01(hit))
    c.check("SIMD: exactly 4 of 16 lanes pass (15,16,35,55)", simd_passes == 4)

    # --- 10. pointer batch API: battery over {10, 15, 60} ---
    var batch = alloc[Int32](3)
    batch[0] = 10
    batch[1] = 15
    batch[2] = 60
    var batch_results = battery.check_batch(batch, 3)
    c.check("batch[0]: 10 fails", not batch_results[0].passed)
    c.check("batch[1]: 15 passes (lo boundary)", batch_results[1].passed)
    c.check("batch[2]: 60 fails", not batch_results[2].passed)
    batch.unsafe_free()

    # --- summary ---
    print("RESULT pass=", c.pass_count, "fail=", c.fail_count)
    if c.fail_count > 0:
        sys.exit(1)

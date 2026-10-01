#!/usr/bin/env python3
"""Independent oracle + parity checker for constraint-theory-mojo.

The oracle below is written from the constraint SPEC (saturate to [-127, 127],
then range-compare against saturated bounds) — deliberately independent of
both src/*.mojo and the flux/ Python fallback.

Usage:
    python3 python/oracle.py <mojo-test-binary>

Runs the compiled Mojo test binary, parses its machine-readable PARITY lines,
recomputes every case independently, and prints a parity table. Exits 1 on
any mismatch. Also reports (as booked drift, not failures) where the flux/
Python fallback presets differ from the Mojo src/engine.mojo presets.
"""

import subprocess
import sys

INT8_MIN, INT8_MAX = -127, 127


def saturate_i8(v):
    return max(INT8_MIN, min(INT8_MAX, v))


def check(lo, hi, sev, value):
    """Spec: value is saturated; bounds are saturated at construction."""
    sv = saturate_i8(value)
    passed = saturate_i8(lo) <= sv <= saturate_i8(hi)
    return 1 if passed else 0, (0 if passed else sev)


# Presets transcribed from src/engine.mojo (Mojo side is the primary source).
AUTOMOTIVE = [
    (0, 250, "vehicle_speed", 2),
    (-15, 15, "lateral_speed", 2),
    (15, 55, "battery_temp", 3),
    (-40, 85, "ambient_temp", 1),
    (0, 100, "charge_rate", 2),
    (0, 360, "steering_angle", 2),
    (0, 5000, "brake_pressure", 3),
]
AVIATION = [
    (-1000, 45000, "altitude", 3),
    (0, 350, "airspeed", 3),
    (-25, 25, "pitch", 3),
    (-45, 45, "roll", 3),
    (0, 100, "fuel_flow", 3),
    (-127, 127, "temperature", 2),
]

SIMD_LANES = [-128, -100, 0, 15, 16, 35, 55, 56, 100, 127, -127, 200, -55, 3, 66, 128]
SIMD_LO, SIMD_HI = 15, 55


def expected(line):
    """Recompute one PARITY line -> (label, tuple-of-expected-fields) or None."""
    parts = line.split()
    kind = parts[1]
    if kind == "sat":
        v, got = int(parts[2]), int(parts[3])
        return ("saturate_i8(%d)" % v, [saturate_i8(v)], got)
    if kind == "check":
        name, v = parts[2], int(parts[3])
        got_list = [int(parts[4]), int(parts[5])]
        lo, hi, sev = CONSTRAINT_TABLES[name]
        ep, es = check(lo, hi, sev, v)
        return ("%s check(%d)" % (name, v), [ep, es], got_list)
    if kind == "engine":
        preset, v, name = parts[2], int(parts[3]), parts[4]
        got_list = [int(parts[5]), int(parts[6])]
        for lo, hi, n, sev in (AUTOMOTIVE if preset == "automotive" else AVIATION):
            if n == name:
                ep, es = check(lo, hi, sev, v)
                return ("%s.check(%d) -> %s" % (preset, v, name), [ep, es], got_list)
        return None
    if kind == "simd":
        lane = int(parts[2])
        got = int(parts[3])
        ep, _ = check(SIMD_LO, SIMD_HI, 0, SIMD_LANES[lane])
        return ("simd lane %d (v=%d)" % (lane, SIMD_LANES[lane]), [ep], got)
    return None


# Degenerate single-constraint parity cases used by tests/test_engine.mojo
CONSTRAINT_TABLES = {
    "battery_temp": (15, 55, 3),
    "inverted": (55, 15, 2),
    "point": (42, 42, 1),
    "clamped": (500, 600, 3),
}


def run_binary(path):
    proc = subprocess.run([path], capture_output=True, text=True, timeout=300)
    return proc


def main():
    if len(sys.argv) != 2:
        print("usage: oracle.py <mojo-test-binary>")
        return 2
    proc = run_binary(sys.argv[1])
    lines = proc.stdout.splitlines()

    result_line = next((l for l in lines if l.startswith("RESULT")), None)
    parity_lines = [l for l in lines if l.startswith("PARITY")]

    print("=== PARITY: oracle vs Mojo binary (%s) ===" % sys.argv[1])
    print("%-42s %-14s %-14s %s" % ("case", "oracle", "mojo", "verdict"))
    mismatches = 0
    unparsed = 0
    for line in parity_lines:
        e = expected(line)
        if e is None:
            unparsed += 1
            continue
        label, exp, got = e
        got_list = got if isinstance(got, list) else [got]
        ok = exp == got_list
        if not ok:
            mismatches += 1
        print("%-42s %-14s %-14s %s" % (label, exp, got_list, "OK" if ok else "MISMATCH"))

    # RESULT contract from the Mojo Counters harness
    print()
    if result_line:
        parts = result_line.split()
        p, f = int(parts[2]), int(parts[4])
        print("Mojo Counters: pass=%d fail=%d -> %s" % (p, f, "OK" if f == 0 else "FAILED"))
        if f != 0:
            mismatches += 1
    else:
        print("No RESULT line found!")
        mismatches += 1
    if proc.returncode != 0:
        print("Binary exit code: %d (nonzero)" % proc.returncode)
        if result_line and "fail=0" in result_line:
            print("NOTE: exit code nonzero but Counters reported fail=0 (sys.exit quirk) — see USERMANUAL")
    if unparsed:
        print("Unparsed PARITY lines: %d" % unparsed)
        mismatches += unparsed
    print("PARITY cases: %d, mismatches: %d" % (len(parity_lines), mismatches))

    # --- Booked drift: flux/ Python fallback vs Mojo presets (informational) ---
    print()
    print("=== Preset drift audit (BOOKED, not fixed — semantic changes are out of scope) ===")
    sys.path.insert(0, ".")
    try:
        from flux import automotive as py_auto, aviation as py_aviation
        for label, mo, py in (("automotive", AUTOMOTIVE, py_auto().constraints),
                              ("aviation", AVIATION, py_aviation().constraints)):
            mo_names = [n for _, _, n, _ in mo]
            py_map = {c.name: (c.lo, c.hi, c.severity) for c in py}
            shared = [n for n in mo_names if n in py_map]
            mo_only = [n for n in mo_names if n not in py_map]
            py_only = [c.name for c in py if c.name not in mo_names]
            print("%s: mojo=%d flux/=%d shared=%d mojo-only=%s flux-only=%s" %
                  (label, len(mo), len(py), len(shared), mo_only or "-", py_only or "-"))
            # Shared constraints must behave identically
            bad = 0
            for lo, hi, n, sev in mo:
                if n in py_map:
                    plo, phi, psev = py_map[n]
                    for v in (-300, -15, 0, 15, 42, 55, 60, 100, 300):
                        ep, es = check(lo, hi, sev, v)
                        r = [c for c in py if c.name == n][0].check(v)
                        gp, gs = (1 if r.passed else 0), r.severity
                        if (ep, es) != (gp, gs):
                            print("  DRIFT %s v=%d oracle=%s flux=%s" % (n, v, (ep, es), (gp, gs)))
                            bad += 1
            print("%s shared-constraint behavior: %s" % (label, "identical" if bad == 0 else "%d DRIFTS" % bad))
    except Exception as e:  # noqa
        print("flux/ audit skipped: %r" % e)

    print()
    print("VERDICT: %s" % ("PARITY OK" if mismatches == 0 else "PARITY FAILED (%d)" % mismatches))
    return 0 if mismatches == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

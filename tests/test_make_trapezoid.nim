## Tests for the make_trapezoid module

import std/[strformat, math]
import nimpulseq

var passed = 0
var failed = 0

template test(name: string, body: untyped) =
  try:
    body
    echo "[PASS] ", name
    inc passed
  except CatchableError, AssertionDefect:
    echo "[FAIL] ", name, ": ", getCurrentExceptionMsg()
    inc failed

template expectError(name: string, body: untyped) =
  try:
    body
    echo "[FAIL] ", name, ": expected error but none raised"
    inc failed
  except CatchableError, AssertionDefect:
    echo "[PASS] ", name
    inc passed

proc compareTrapOut(trap: Event, amplitude, riseTime, flatTime, fallTime: float64) =
  doAssert abs(trap.trapAmplitude - amplitude) < eps,
    &"amplitude: expected {amplitude}, got {trap.trapAmplitude}"
  doAssert abs(trap.trapRiseTime - riseTime) < eps,
    &"rise_time: expected {riseTime}, got {trap.trapRiseTime}"
  doAssert abs(trap.trapFlatTime - flatTime) < eps,
    &"flat_time: expected {flatTime}, got {trap.trapFlatTime}"
  doAssert abs(trap.trapFallTime - fallTime) < eps,
    &"fall_time: expected {fallTime}, got {trap.trapFallTime}"

# Error cases
expectError "channel error":
  discard makeTrapezoid(channel = "p")

expectError "area_flatarea_amplitude error":
  discard makeTrapezoid(channel = "x")

expectError "flat_time without flat_area/amplitude error":
  discard makeTrapezoid(channel = "x", flatTime = 10.0, area = 10.0)

expectError "area too large error":
  discard makeTrapezoid(channel = "x", area = 1e6, duration = 1e-6)

expectError "area too large rise_time error":
  discard makeTrapezoid(channel = "x", area = 1e6, duration = 1e-6, riseTime = 1e-7)

expectError "no area no duration error":
  discard makeTrapezoid(channel = "x", amplitude = 1.0)

expectError "amplitude too large error":
  discard makeTrapezoid(channel = "x", amplitude = 1e10, duration = 1.0)

expectError "duration too short error":
  discard makeTrapezoid(channel = "x", area = 1.0, duration = 0.1, riseTime = 0.1)

expectError "flat_area + duration not implemented":
  discard makeTrapezoid(channel = "x", flatArea = 1.0, duration = 1.0)

expectError "flat_area + amplitude not implemented":
  discard makeTrapezoid(channel = "x", flatArea = 1.0, amplitude = 1.0)

expectError "area + amplitude not implemented":
  discard makeTrapezoid(channel = "x", area = 1.0, amplitude = 1.0)

# Generation methods
let opts = defaultOpts()

test "amplitude + duration":
  let trap = makeTrapezoid(channel = "x", amplitude = 1.0, duration = 1.0)
  compareTrapOut(trap, 1.0, 1e-5, 1.0 - 2e-5, 1e-5)

test "flat_time + amplitude":
  let trap = makeTrapezoid(channel = "x", flatTime = 1.0, amplitude = 1.0)
  compareTrapOut(trap, 1.0, 1e-5, 1.0, 1e-5)

test "flat_area + flat_time":
  let trap = makeTrapezoid(channel = "x", flatTime = 1.0, flatArea = 1.0)
  compareTrapOut(trap, 1.0, 1e-5, 1.0, 1e-5)

test "area triangle":
  let trap = makeTrapezoid(channel = "x", area = 1.0)
  compareTrapOut(trap, 50000.0, 2e-5, 0.0, 2e-5)

test "area trapezoid":
  let trap = makeTrapezoid(channel = "x", area = opts.maxGrad * 2.0)
  let timeToMax = round(opts.maxGrad / opts.maxSlew / 1e-5) * 1e-5
  compareTrapOut(trap, opts.maxGrad, timeToMax,
    (opts.maxGrad * 2.0 - timeToMax * opts.maxGrad) / opts.maxGrad, timeToMax)

test "area + duration":
  let trap = makeTrapezoid(channel = "x", area = 1.0, duration = 1.0)
  compareTrapOut(trap, 1.00002, 2e-5, 1.0 - 4e-5, 2e-5)

test "area + duration + rise_time":
  let trap = makeTrapezoid(channel = "x", area = 1.0, duration = 1.0, riseTime = 0.01)
  compareTrapOut(trap, 1.0 / 0.99, 0.01, 0.98, 0.01)

test "flat_time + area + rise_time":
  let trap = makeTrapezoid(channel = "x", flatTime = 0.5, area = 1.0, riseTime = 0.1)
  compareTrapOut(trap, 1.0 / 0.6, 0.1, 0.5, 0.1)

echo &"\n{passed} passed, {failed} failed"
if failed > 0: quit(1)

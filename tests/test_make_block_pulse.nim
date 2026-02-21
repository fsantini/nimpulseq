## Tests for the make_block_pulse module

import std/[strformat, math, complex]
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

# Error cases
expectError "invalid use error":
  discard makeBlockPulse(flipAngle = PI, duration = 1e-3, use = "foo")

expectError "bandwidth and duration error":
  discard makeBlockPulse(flipAngle = PI, duration = 1e-3, bandwidth = 1000.0)

expectError "invalid bandwidth error":
  discard makeBlockPulse(flipAngle = PI, bandwidth = -1e3)

# Generation methods
test "default duration":
  let pulse = makeBlockPulse(flipAngle = PI, duration = 4e-3)
  doAssert pulse.kind == ekRf
  doAssert pulse.rfShapeDur == 4e-3

test "explicit duration":
  let pulse = makeBlockPulse(flipAngle = PI, duration = 1e-3)
  doAssert pulse.kind == ekRf
  doAssert pulse.rfShapeDur == 1e-3

test "bandwidth":
  let pulse = makeBlockPulse(flipAngle = PI, bandwidth = 1e3)
  doAssert pulse.kind == ekRf
  doAssert pulse.rfShapeDur == 1.0 / (4.0 * 1e3)

test "bandwidth + time_bw_product":
  let pulse = makeBlockPulse(flipAngle = PI, bandwidth = 1e3, timeBwProduct = 5.0)
  doAssert pulse.kind == ekRf
  doAssert pulse.rfShapeDur == 5.0 / 1e3

# Amplitude calculation
test "180 deg 1ms pulse amplitude":
  let pulse = makeBlockPulse(duration = 1e-3, flipAngle = PI)
  let maxSig = abs(pulse.rfSignal[0])
  doAssert abs(maxSig - 500.0) < 1e-6, &"Expected 500 Hz, got {maxSig}"

test "90 deg 1ms pulse amplitude":
  let pulse = makeBlockPulse(duration = 1e-3, flipAngle = PI / 2.0)
  let maxSig = abs(pulse.rfSignal[0])
  doAssert abs(maxSig - 250.0) < 1e-6, &"Expected 250 Hz, got {maxSig}"

test "90 deg 2ms pulse amplitude":
  let pulse = makeBlockPulse(duration = 2e-3, flipAngle = PI / 2.0)
  let maxSig = abs(pulse.rfSignal[0])
  doAssert abs(maxSig - 125.0) < 1e-6, &"Expected 125 Hz, got {maxSig}"

echo &"\n{passed} passed, {failed} failed"
if failed > 0: quit(1)

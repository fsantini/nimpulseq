## Tests for the scale_grad module

import std/[strformat, math]
import ../src/nimpulseq

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
  except CatchableError:
    echo "[PASS] ", name
    inc passed

# Build gradient list - mix of traps and extended traps
# (skip convert_to_arbitrary=True variants; use extended traps which are ekGrad)
let sys1 = newOpts(maxGrad = 40.0, maxSlew = 300.0)
let sys2 = newOpts(maxGrad = 25.0, maxSlew = 150.0)
let sys3 = newOpts(maxGrad = 15.0, maxSlew = 80.0)

let gradList = @[
  makeTrapezoid(channel = "x", amplitude = 10.0, duration = 13.0, maxGrad = 30.0, maxSlew = 200.0),
  makeTrapezoid(channel = "y", amplitude = 10.0, duration = 13.0, maxGrad = 30.0, maxSlew = 200.0),
  makeTrapezoid(channel = "z", amplitude = 10.0, duration = 13.0, maxGrad = 30.0, maxSlew = 200.0),
  makeTrapezoid(channel = "x", amplitude = 20.0, duration = 5.0, maxGrad = 25.0, maxSlew = 150.0),
  makeTrapezoid(channel = "y", amplitude = 20.0, duration = 5.0, maxGrad = 25.0, maxSlew = 150.0),
  makeTrapezoid(channel = "z", amplitude = 20.0, duration = 5.0, maxGrad = 25.0, maxSlew = 150.0),
  makeExtendedTrapezoid("x", amplitudes = @[0.0, 15.0, 5.0, 10.0], times = @[1.0, 3.0, 4.0, 7.0], system = sys1),
  makeExtendedTrapezoid("y", amplitudes = @[0.0, 15.0, 5.0, 10.0], times = @[1.0, 3.0, 4.0, 7.0], system = sys1),
  makeExtendedTrapezoid("z", amplitudes = @[0.0, 15.0, 5.0, 10.0], times = @[1.0, 3.0, 4.0, 7.0], system = sys1),
  makeExtendedTrapezoid("x", amplitudes = @[0.0, 20.0, 10.0, 15.0], times = @[1.0, 3.0, 4.0, 7.0], system = sys2),
  makeExtendedTrapezoid("y", amplitudes = @[0.0, 20.0, 10.0, 15.0], times = @[1.0, 3.0, 4.0, 7.0], system = sys2),
  makeExtendedTrapezoid("z", amplitudes = @[0.0, 20.0, 10.0, 15.0], times = @[1.0, 3.0, 4.0, 7.0], system = sys2),
  makeExtendedTrapezoid("x", amplitudes = @[0.0, 10.0, 5.0, 10.0], times = @[1.0, 2.0, 3.0, 4.0], system = sys3),
  makeExtendedTrapezoid("y", amplitudes = @[0.0, 10.0, 5.0, 10.0], times = @[1.0, 2.0, 3.0, 4.0], system = sys3),
  makeExtendedTrapezoid("z", amplitudes = @[0.0, 10.0, 5.0, 10.0], times = @[1.0, 2.0, 3.0, 4.0], system = sys3),
]

# Test scaling correctness
let safeScale = 0.5
let safeSystem = newOpts(maxGrad = 40.0, maxSlew = 300.0)

for idx, grad in gradList:
  test &"scale_grad correct scaling [{idx}]":
    let scaled = scaleGrad(grad, safeScale, safeSystem)
    if grad.kind == ekTrap:
      doAssert abs(scaled.trapAmplitude - grad.trapAmplitude * safeScale) < 1e-9
      doAssert abs(scaled.trapFlatArea - grad.trapFlatArea * safeScale) < 1e-9
      doAssert abs(scaled.trapArea - grad.trapArea * safeScale) < 1e-9
    elif grad.kind == ekGrad:
      for i in 0 ..< grad.gradWaveform.len:
        doAssert abs(scaled.gradWaveform[i] - grad.gradWaveform[i] * safeScale) < 1e-9
      doAssert abs(scaled.gradFirst - grad.gradFirst * safeScale) < 1e-9
      doAssert abs(scaled.gradLast - grad.gradLast * safeScale) < 1e-9

# Test amplitude violation
test "amplitude violation":
  let ampScale = 100.0
  let ampSystem = newOpts(maxGrad = 40.0, maxSlew = 999999999.0)
  var expectedFailures = 0
  var actualFailures = 0
  for grad in gradList:
    var shouldFail: bool
    if grad.kind == ekTrap:
      shouldFail = abs(grad.trapAmplitude) * ampScale > ampSystem.maxGrad
    else:
      var maxWf = 0.0
      for w in grad.gradWaveform:
        maxWf = max(maxWf, abs(w))
      shouldFail = maxWf * ampScale > ampSystem.maxGrad
    if shouldFail:
      inc expectedFailures
      try:
        discard scaleGrad(grad, ampScale, ampSystem)
        doAssert false, "expected amplitude violation"
      except ValueError:
        inc actualFailures
    else:
      discard scaleGrad(grad, ampScale, ampSystem)
  doAssert expectedFailures == actualFailures,
    &"Expected {expectedFailures} failures, got {actualFailures}"

# Test slew rate violation
test "slew rate violation":
  let slewScale = 100.0
  let slewSystem = newOpts(maxGrad = 999999999.0, maxSlew = 300.0)
  var expectedFailures = 0
  var actualFailures = 0
  for grad in gradList:
    var shouldFail = false
    if grad.kind == ekTrap:
      if abs(grad.trapAmplitude) > 1e-6:
        let approxSlew = abs(grad.trapAmplitude * slewScale) / min(grad.trapRiseTime, grad.trapFallTime)
        shouldFail = approxSlew > slewSystem.maxSlew
    else:
      var maxWf = 0.0
      for w in grad.gradWaveform:
        maxWf = max(maxWf, abs(w))
      if maxWf > 1e-6:
        for i in 0 ..< grad.gradTt.len - 1:
          let sr = abs(grad.gradWaveform[i + 1] * slewScale - grad.gradWaveform[i] * slewScale) /
                   (grad.gradTt[i + 1] - grad.gradTt[i])
          if sr > slewSystem.maxSlew:
            shouldFail = true
            break
    if shouldFail:
      inc expectedFailures
      try:
        discard scaleGrad(grad, slewScale, slewSystem)
        doAssert false, "expected slew violation"
      except ValueError:
        inc actualFailures
    else:
      discard scaleGrad(grad, slewScale, slewSystem)
  doAssert expectedFailures == actualFailures,
    &"Expected {expectedFailures} failures, got {actualFailures}"

echo &"\n{passed} passed, {failed} failed"
if failed > 0: quit(1)

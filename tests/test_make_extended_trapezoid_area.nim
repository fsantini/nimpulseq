## Tests for the make_extended_trapezoid_area module
## Skips convert_to_arbitrary tests (not implemented in NimPulseq).

import std/[strformat, math, random]
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

let system = defaultOpts()

proc computeGradArea(g: Event): float64 =
  ## Compute area of an extended gradient by trapezoidal integration.
  for i in 0 ..< g.gradTt.len - 1:
    result += 0.5 * (g.gradTt[i + 1] - g.gradTt[i]) * (g.gradWaveform[i + 1] + g.gradWaveform[i])

type TestCase = tuple[gradStart, gradEnd, area: float64]

let testZoo: seq[TestCase] = @[
  (0.0, 0.0, 1.0),
  (0.0, 0.0, 10.0),
  (0.0, 0.0, 100.0),
  (0.0, 0.0, 10000.0),
  (0.0, 1000.0, 100.0),
  (-1000.0, 1000.0, 100.0),
  (-1000.0, 0.0, 100.0),
  (0.0, 0.0, -1.0),
  (0.0, 0.0, -10.0),
  (0.0, 0.0, -100.0),
  (0.0, 0.0, -10000.0),
  (0.0, 1000.0, -100.0),
  (-1000.0, 1000.0, -100.0),
  (-1000.0, 0.0, -100.0),
  (0.0, system.maxGrad * 0.99, 10000.0),
  (0.0, system.maxGrad * 0.99, -10000.0),
  (0.0, -system.maxGrad * 0.99, 1000.0),
  (0.0, -system.maxGrad * 0.99, -1000.0),
  (system.maxGrad * 0.99, 0.0, 100.0),
  (system.maxGrad * 0.99, 0.0, -100.0),
  (-system.maxGrad * 0.99, 0.0, 1.0),
  (-system.maxGrad * 0.99, 0.0, -1.0),
  (0.0, 100000.0, 1.0),
  (0.0, 100000.0, -1.0),
  (0.0, -100000.0, 1.0),
  (0.0, -100000.0, -1.0),
  (0.0, 90000.0, 0.45),
  (0.0, 90000.0, -0.45),
  (0.0, -90000.0, 0.45),
  (0.0, -90000.0, -0.45),
  (0.0, 10000.0, 0.5 * (10000.0 * 10000.0) / (system.maxSlew * 0.99)),
  (0.0, system.maxGrad * 0.99, 0.5 * (system.maxGrad * 0.99) * (system.maxGrad * 0.99) / (system.maxSlew * 0.99)),
  (system.maxGrad * 0.99, system.maxGrad * 0.99, 1.0),
  (system.maxGrad * 0.99, system.maxGrad * 0.99, -1.0),
]

# Parametrized test zoo
for idx, tc in testZoo:
  test &"extended_trapezoid_area zoo[{idx}] ({tc.gradStart:.0f},{tc.gradEnd:.0f},{tc.area:.2f})":
    let (g, _, _) = makeExtendedTrapezoidArea(
      channel = "x", gradStart = tc.gradStart, gradEnd = tc.gradEnd,
      area = tc.area, system = system,
    )
    # Check area
    doAssert abs(computeGradArea(g) - tc.area) < abs(tc.area) * 1e-5 + 1e-9,
      &"Area mismatch: expected {tc.area}, got {computeGradArea(g)}"
    # Check gradient amplitude constraint
    for w in g.gradWaveform:
      doAssert abs(w) <= system.maxGrad + eps,
        &"Gradient strength violated: {abs(w)} > {system.maxGrad}"
    # Check slew rate constraint
    for i in 0 ..< g.gradTt.len - 1:
      let slewRate = abs(g.gradWaveform[i + 1] - g.gradWaveform[i]) / (g.gradTt[i + 1] - g.gradTt[i])
      doAssert slewRate <= system.maxSlew + eps,
        &"Slew rate violated: {slewRate} > {system.maxSlew}"

# Random test cases
var rng = initRand(0)
var randomZoo: seq[TestCase] = @[]
for i in 0 ..< 100:
  let gs = (rng.rand(1.0) - 0.5) * 2.0 * system.maxGrad * 0.99
  let ge = (rng.rand(1.0) - 0.5) * 2.0 * system.maxGrad * 0.99
  let a = (rng.rand(1.0) - 0.5) * 10000.0
  randomZoo.add((gs, ge, a))

for idx, tc in randomZoo:
  test &"extended_trapezoid_area random[{idx}]":
    let (g, _, _) = makeExtendedTrapezoidArea(
      channel = "x", gradStart = tc.gradStart, gradEnd = tc.gradEnd,
      area = tc.area, system = system,
    )
    doAssert abs(computeGradArea(g) - tc.area) < abs(tc.area) * 1e-5 + 1e-9,
      &"Area mismatch: expected {tc.area}, got {computeGradArea(g)}"
    for w in g.gradWaveform:
      doAssert abs(w) <= system.maxGrad + eps,
        &"Gradient strength violated: {abs(w)} > {system.maxGrad}"
    for i in 0 ..< g.gradTt.len - 1:
      let slewRate = abs(g.gradWaveform[i + 1] - g.gradWaveform[i]) / (g.gradTt[i + 1] - g.gradTt[i])
      doAssert slewRate <= system.maxSlew + eps,
        &"Slew rate violated: {slewRate} > {system.maxSlew}"

echo "[SKIP] convert_to_arbitrary tests (not implemented)"

echo &"\n{passed} passed, {failed} failed"
if failed > 0: quit(1)

## Tests for the make_adiabatic_pulse module
## Note: only hypsec is implemented in NimPulseq. Wurst tests are skipped.

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
  except CatchableError:
    echo "[PASS] ", name
    inc passed

# Test valid pulse type + use combinations (hypsec only)
for u in supportedRfUses:
  test &"hypsec use='{u}'":
    let (rf, _, _) = makeAdiabaticPulse(pulseType = "hypsec", use = u)
    doAssert rf.kind == ekRf
    doAssert rf.rfUse == u

# Error: invalid pulse type
expectError "invalid pulse type":
  discard makeAdiabaticPulse(pulseType = "not a pulse type")

expectError "empty pulse type":
  discard makeAdiabaticPulse(pulseType = "")

expectError "invalid use":
  discard makeAdiabaticPulse(pulseType = "hypsec", use = "not a use")

# Default use case
test "default use is inversion":
  let (rf, _, _) = makeAdiabaticPulse(pulseType = "hypsec")
  doAssert rf.rfUse == "inversion"

# Require non-zero slice thickness if grad requested
expectError "return_gz without slice thickness":
  discard makeAdiabaticPulse(pulseType = "hypsec", returnGz = true)

test "return_gz with slice thickness":
  let (rf, gz, gzr) = makeAdiabaticPulse(pulseType = "hypsec", returnGz = true, sliceThickness = 1.0)
  doAssert gz.kind == ekTrap
  doAssert gzr.kind == ekTrap

# Hypsec options
test "hypsec custom options":
  let (rf, _, _) = makeAdiabaticPulse(pulseType = "hypsec", beta = 700.0, mu = 6.0, duration = 0.05)
  doAssert abs(rf.rfShapeDur - 0.05) < 1e-9

# Note: wurst tests skipped - wurst pulse type not implemented in NimPulseq
echo "[SKIP] wurst pulse tests (not implemented)"

echo &"\n{passed} passed, {failed} failed"
if failed > 0: quit(1)

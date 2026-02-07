## Tests for the make_gauss_pulse module

import std/strformat
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

expectError "invalid use error":
  discard makeGaussPulse(flipAngle = 1.0, use = "invalid")

for u in supportedRfUses:
  test &"valid use '{u}'":
    let (rf, _, _) = makeGaussPulse(flipAngle = 1.0, use = u)
    doAssert rf.kind == ekRf

echo &"\n{passed} passed, {failed} failed"
if failed > 0: quit(1)

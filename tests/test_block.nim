## Tests for gradient continuity checks in add_block.
## set_block tests are skipped (set_block not fully exposed in NimPulseq API).

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
  except CatchableError, AssertionDefect:
    echo "[PASS] ", name
    inc passed

# Gradient definitions used in tests
let gxTrap = makeTrapezoid("x", area = 1000.0, duration = 1e-3)
let gxExtended = makeExtendedTrapezoid("x", amplitudes = @[0.0, 100000.0, 0.0], times = @[0.0, 1e-4, 2e-4])
let gxExtendedDelay = makeExtendedTrapezoid("x", amplitudes = @[0.0, 100000.0, 0.0], times = @[1e-4, 2e-4, 3e-4])
let gxEndsHigh = makeExtendedTrapezoid("x", amplitudes = @[0.0, 100000.0, 100000.0], times = @[0.0, 1e-4, 2e-4])
let gxStartsHigh = makeExtendedTrapezoid("x", amplitudes = @[100000.0, 100000.0, 0.0], times = @[0.0, 1e-4, 2e-4])
let gxStartsHigh2 = makeExtendedTrapezoid("x", amplitudes = @[200000.0, 100000.0, 0.0], times = @[0.0, 1e-4, 2e-4])
let gxAllHigh = makeExtendedTrapezoid("x", amplitudes = @[100000.0, 100000.0, 100000.0], times = @[0.0, 1e-4, 2e-4])
let delay = makeDelay(1e-3)

# Test gradient continuity checks in add_block

test "continuity1 - trap followed by extended":
  var seqObj = newSequence()
  seqObj.addBlock(gxTrap)
  seqObj.addBlock(gxExtended)
  seqObj.addBlock(gxTrap)

expectError "continuity2 - trap followed by non-zero start":
  var seqObj = newSequence()
  seqObj.addBlock(gxTrap)
  seqObj.addBlock(gxStartsHigh)

expectError "continuity3 - non-zero start in first block":
  var seqObj = newSequence()
  seqObj.addBlock(gxStartsHigh)

expectError "continuity4 - starts and ends non-zero":
  var seqObj = newSequence()
  seqObj.addBlock(delay)
  seqObj.addBlock(gxAllHigh)

test "continuity5 - starts at zero with delay":
  var seqObj = newSequence()
  seqObj.addBlock(gxExtendedDelay)

expectError "continuity6 - non-zero start in other blocks":
  var seqObj = newSequence()
  seqObj.addBlock(delay)
  seqObj.addBlock(gxStartsHigh)

expectError "continuity7 - ends high followed by empty":
  var seqObj = newSequence()
  seqObj.addBlock(gxEndsHigh)
  seqObj.addBlock(delay)

expectError "continuity8 - ends high followed by trap":
  var seqObj = newSequence()
  seqObj.addBlock(gxEndsHigh)
  seqObj.addBlock(gxTrap)

test "continuity9 - ends high followed by connecting":
  var seqObj = newSequence()
  seqObj.addBlock(gxEndsHigh)
  seqObj.addBlock(gxStartsHigh)

test "continuity10 - last block ends high (ok, caught by write)":
  var seqObj = newSequence()
  seqObj.addBlock(gxEndsHigh)

expectError "continuity11 - non-connecting gradients":
  var seqObj = newSequence()
  seqObj.addBlock(gxEndsHigh)
  seqObj.addBlock(gxStartsHigh2)

echo "[SKIP] set_block continuity tests (set_block not fully exposed)"

echo &"\n{passed} passed, {failed} failed"
if failed > 0: quit(1)

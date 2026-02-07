## Tests for check_timing module

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

# System settings
let system = newOpts(
  maxGrad = 28, gradUnit = "mT/m",
  maxSlew = 200, slewUnit = "T/m/s",
  rfRingdownTime = 20e-6,
  rfDeadTime = 100e-6,
  adcDeadTime = 10e-6,
)

# System with ringdown and dead times set to 0 to introduce timing errors
let systemBroken = newOpts(
  maxGrad = 28, gradUnit = "mT/m",
  maxSlew = 200, slewUnit = "T/m/s",
  rfRingdownTime = 0e-6,
  rfDeadTime = 0e-6,
  adcDeadTime = 0e-6,
)

proc blocksNotInErrorReport(errors: seq[TimingError], blocks: seq[int]): bool =
  for e in errors:
    if e.blockIdx in blocks:
      return false
  return true

proc existsInErrorReport(errors: seq[TimingError], blockIdx: int, event, field, errorType: string): bool =
  for e in errors:
    if e.blockIdx == blockIdx and e.event == event and e.field == field and e.errorType == errorType:
      return true
  return false

test "check_timing catches all timing errors":
  var seqObj = newSequence(system)

  # Block 1: No error
  let rf1 = makeSincPulse(flipAngle = 1.0, duration = 1e-3, delay = system.rfDeadTime, system = system)
  seqObj.addBlock(rf1.rf)

  # Block 2: RF_DEAD_TIME, RF_RINGDOWN_TIME, BLOCK_DURATION_MISMATCH
  let rf2 = makeSincPulse(flipAngle = 1.0, duration = 1e-3, system = systemBroken)
  seqObj.addBlock(rf2.rf)

  # Block 3: No error
  let adc3 = makeAdc(numSamples = 100, duration = 1e-3, delay = system.adcDeadTime, system = system)
  seqObj.addBlock(adc3)

  # Block 4: RASTER (dwell)
  let adc4 = makeAdc(numSamples = 123, duration = 1e-3, delay = system.adcDeadTime, system = system)
  seqObj.addBlock(adc4)

  # Block 5: ADC_DEAD_TIME, POST_ADC_DEAD_TIME, BLOCK_DURATION_MISMATCH
  let adc5 = makeAdc(numSamples = 100, duration = 1e-3, system = systemBroken)
  seqObj.addBlock(adc5)

  # Block 6: No error
  let gx6 = makeTrapezoid(channel = "x", area = 1.0, duration = 1.0, system = system)
  seqObj.addBlock(gx6)

  # Block 7: RASTER (block duration + flat_time)
  let gx7 = makeTrapezoid(channel = "x", area = 1.0, duration = 1.00001e-3, system = system)
  seqObj.addBlock(gx7)

  # Block 8: RASTER (block duration + rise_time + fall_time)
  let gx8 = makeTrapezoid(channel = "x", area = 1.0, riseTime = 1e-6, flatTime = 1e-3, fallTime = 3e-6, system = system)
  seqObj.addBlock(gx8)

  # Block 9: NEGATIVE_DELAY
  let gx9 = makeTrapezoid(channel = "x", area = 1.0, duration = 1e-3, delay = -1e-5, system = system)
  seqObj.addBlock(gx9)

  # Check timing errors
  let (_, errorReport) = seqObj.checkTiming()

  # Blocks 1, 3, 6 should have no errors
  doAssert blocksNotInErrorReport(errorReport, @[1, 3, 6]),
    "No timing errors expected on blocks 1, 3, and 6"

  # Block 2: RF errors
  doAssert existsInErrorReport(errorReport, 2, "rf", "delay", "RF_DEAD_TIME"),
    "Expected RF_DEAD_TIME in block 2"
  doAssert existsInErrorReport(errorReport, 2, "rf", "duration", "RF_RINGDOWN_TIME"),
    "Expected RF_RINGDOWN_TIME in block 2"
  doAssert existsInErrorReport(errorReport, 2, "block", "duration", "BLOCK_DURATION_MISMATCH"),
    "Expected BLOCK_DURATION_MISMATCH in block 2"

  # Block 4: ADC dwell raster
  doAssert existsInErrorReport(errorReport, 4, "adc", "dwell", "RASTER"),
    "Expected RASTER for adc.dwell in block 4"

  # Block 5: ADC dead time errors
  doAssert existsInErrorReport(errorReport, 5, "adc", "delay", "ADC_DEAD_TIME"),
    "Expected ADC_DEAD_TIME in block 5"
  doAssert existsInErrorReport(errorReport, 5, "adc", "duration", "POST_ADC_DEAD_TIME"),
    "Expected POST_ADC_DEAD_TIME in block 5"
  doAssert existsInErrorReport(errorReport, 5, "block", "duration", "BLOCK_DURATION_MISMATCH"),
    "Expected BLOCK_DURATION_MISMATCH in block 5"

  # Block 7: Gradient raster errors
  doAssert existsInErrorReport(errorReport, 7, "block", "duration", "RASTER"),
    "Expected block RASTER in block 7"
  doAssert existsInErrorReport(errorReport, 7, "gx", "flat_time", "RASTER"),
    "Expected gx.flat_time RASTER in block 7"

  # Block 8: Gradient raster errors
  doAssert existsInErrorReport(errorReport, 8, "block", "duration", "RASTER"),
    "Expected block RASTER in block 8"
  doAssert existsInErrorReport(errorReport, 8, "gx", "rise_time", "RASTER"),
    "Expected gx.rise_time RASTER in block 8"
  doAssert existsInErrorReport(errorReport, 8, "gx", "fall_time", "RASTER"),
    "Expected gx.fall_time RASTER in block 8"

  # Block 9: Negative delay
  doAssert existsInErrorReport(errorReport, 9, "gx", "delay", "NEGATIVE_DELAY"),
    "Expected NEGATIVE_DELAY in block 9"

  # Total error count
  doAssert errorReport.len == 13,
    &"Expected 13 timing errors, got {errorReport.len}"

echo &"\n{passed} passed, {failed} failed"
if failed > 0: quit(1)

## Simple example demonstrating soft delay functionality in NimPulseq.
##
## Shows how to create and use soft delays for dynamic timing adjustment
## without recompiling the sequence.

import std/[tables, math, strformat]
import nimpulseq

proc main() =
  var seqObj = newSequence()

  echo "=== Simple Soft Delay Example ==="
  echo ""

  # ====================================
  # Example 1: Basic TE soft delay
  # ====================================
  echo "1. Creating a basic TE soft delay..."

  let teDelay = makeSoftDelay("TE", defaultDuration = 5e-3)
  echo &"   - Created TE delay with hint: '{teDelay.sdHint}'"
  echo &"   - Default duration: {teDelay.sdDefaultDuration * 1000:.1f} ms"

  seqObj.addBlock(teDelay)
  echo &"   - Auto-assigned numID: {seqObj.softDelayHints[\"TE\"]}"
  echo &"   - Block duration: {seqObj.blockDurations[1] * 1000:.1f} ms"
  echo ""

  # ====================================
  # Example 2: TR soft delay with scaling
  # ====================================
  echo "2. Creating a TR soft delay with scaling..."

  let trDelay = makeSoftDelay(
    "TR",
    factor = 1000.0,   # Convert ms input to seconds
    offset = -10e-3,   # Subtract 10ms overhead
    defaultDuration = 100e-3,
  )
  echo &"   - Created TR delay with factor: {trDelay.sdFactor}"
  echo &"   - Offset: {trDelay.sdOffset * 1000:.1f} ms"

  seqObj.addBlock(trDelay)
  echo &"   - Auto-assigned numID: {seqObj.softDelayHints[\"TR\"]}"
  echo &"   - Block duration: {seqObj.blockDurations[2] * 1000:.1f} ms"
  echo ""

  # ====================================
  # Example 3: Multiple delays with same hint
  # ====================================
  echo "3. Creating multiple delays with same hint..."

  let teDelay2 = makeSoftDelay("TE", defaultDuration = 8e-3)
  let teDelay3 = makeSoftDelay("TE", defaultDuration = 12e-3)

  seqObj.addBlock(teDelay2)
  seqObj.addBlock(teDelay3)

  echo &"   - TE delay #2 numID: {seqObj.softDelayHints[\"TE\"]} (reuses same ID)"
  echo &"   - TE delay #3 numID: {seqObj.softDelayHints[\"TE\"]} (reuses same ID)"
  echo &"   - Block durations: {seqObj.blockDurations[3] * 1000:.1f} ms, {seqObj.blockDurations[4] * 1000:.1f} ms"
  echo ""

  # ====================================
  # Example 4: Applying soft delays
  # ====================================
  echo "4. Applying soft delay values..."

  echo "   Before applying:"
  for i in 1 .. 4:
    echo &"     Block {i}: {seqObj.blockDurations[i] * 1000:.1f} ms"

  seqObj.applySoftDelay({"TE": 15e-3, "TR": 250.0}.toTable)

  echo ""
  echo "   After applying TE=15ms, TR=250ms:"
  for i in 1 .. 4:
    echo &"     Block {i}: {seqObj.blockDurations[i] * 1000:.1f} ms"

  # ====================================
  # Example 5: Realistic sequence context
  # ====================================
  echo ""
  echo "5. Soft delays in a realistic sequence context..."

  var seqReal = newSequence()

  let rfPulse = makeBlockPulse(flipAngle = 30.0 * PI / 180.0, duration = 1e-3)
  let gxReadout = makeTrapezoid(channel = "x", area = 1000.0, duration = 5e-3)
  let gyPhase = makeTrapezoid(channel = "y", area = 500.0, duration = 2e-3)
  let adc = makeAdc(numSamples = 128, duration = 4e-3)

  let teDelayReal = makeSoftDelay("TE", defaultDuration = 10e-3)
  let trDelayReal = makeSoftDelay("TR", defaultDuration = 50e-3)

  seqReal.addBlock(rfPulse)
  seqReal.addBlock(teDelayReal)
  seqReal.addBlock(gyPhase)
  seqReal.addBlock(gxReadout, adc)
  seqReal.addBlock(trDelayReal)

  var totalDur = 0.0
  for _, d in seqReal.blockDurations:
    totalDur += d
  echo &"   - Created realistic sequence with {seqReal.blockDurations.len} blocks"
  echo &"   - Total sequence duration: {totalDur * 1000:.1f} ms"

  seqReal.applySoftDelay({"TE": 8e-3, "TR": 40e-3}.toTable)

  totalDur = 0.0
  for _, d in seqReal.blockDurations:
    totalDur += d
  echo &"   - After optimization: {totalDur * 1000:.1f} ms"

  echo ""
  echo "=== Example Complete ==="
  echo ""
  echo "Key takeaways:"
  echo "• Soft delays enable runtime timing adjustment without recompiling"
  echo "• Use descriptive hints like 'TE', 'TR', 'TI' for scanner interface"
  echo "• Multiple delays with same hint automatically share numID"
  echo "• Default duration becomes the initial block duration"
  echo "• Apply delays with seqObj.applySoftDelay({\"HINT\": value}.toTable)"
  echo "• Use factor/offset for unit conversion and timing adjustments"

when isMainModule:
  main()

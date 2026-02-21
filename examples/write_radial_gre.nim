import std/math
import nimpulseq

proc writeRadialGreSeq*(): Sequence =
  # ======
  # SETUP
  # ======
  let fov = 260e-3
  let Nx = 64
  let alpha = 10
  let sliceThickness = 3e-3
  let TE = 8e-3
  let TR = 20e-3
  let Nr = 60
  let NDummy = 20
  let delta = PI / float64(Nr)

  let rfSpoilingInc = 117

  let system = newOpts(
    maxGrad = 28, gradUnit = "mT/m",
    maxSlew = 120, slewUnit = "T/m/s",
    rfRingdownTime = 20e-6,
    rfDeadTime = 100e-6,
    adcDeadTime = 10e-6,
  )

  var seqObj = newSequence(system)

  # ======
  # CREATE EVENTS
  # ======
  var (rf, gz, _) = makeSincPulse(
    apodization = 0.5,
    duration = 4e-3,
    flipAngle = float64(alpha) * PI / 180.0,
    sliceThickness = sliceThickness,
    system = system,
    timeBwProduct = 4.0,
    returnGz = true,
    delay = system.rfDeadTime,
    use = "excitation",
  )

  let deltak = 1.0 / fov
  var gx = makeTrapezoid(channel = "x", flatArea = float64(Nx) * deltak, flatTime = 6.4e-3 / 5.0, system = system)
  var adc = makeAdc(numSamples = Nx, duration = gx.trapFlatTime, delay = gx.trapRiseTime, system = system)
  let gxPre = makeTrapezoid(channel = "x", area = -gx.trapArea / 2.0 - deltak / 2.0, duration = 2e-3, system = system)
  let gzReph = makeTrapezoid(channel = "z", area = -gz.trapArea / 2.0, duration = 2e-3, system = system)
  let gxSpoil = makeTrapezoid(channel = "x", area = 0.5 * float64(Nx) * deltak, system = system)
  let gzSpoil = makeTrapezoid(channel = "z", area = 4.0 / sliceThickness, system = system)

  # Calculate timing
  let delayTE =
    ceil(
      (TE - calcDuration(gxPre) - gz.trapFallTime - gz.trapFlatTime / 2.0 - calcDuration(gx) / 2.0) /
      seqObj.gradRasterTime
    ) * seqObj.gradRasterTime
  let delayTR =
    ceil(
      (TR - calcDuration(gxPre) - calcDuration(gz) - calcDuration(gx) - delayTE) /
      seqObj.gradRasterTime
    ) * seqObj.gradRasterTime
  assert delayTR > calcDuration(gxSpoil, gzSpoil)
  var rfPhase = 0.0
  var rfInc = 0.0

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  for i in -NDummy .. Nr:
    rf.rfPhaseOffset = rfPhase / 180.0 * PI
    adc.adcPhaseOffset = rfPhase / 180.0 * PI

    rfInc = (rfInc + float64(rfSpoilingInc)) mod 360.0
    rfPhase = (rfInc + rfPhase) mod 360.0

    seqObj.addBlock(rf, gz)
    let phi = delta * float64(i - 1)
    seqObj.addBlock(rotate(@[gxPre, gzReph], phi, "z", system))
    seqObj.addBlock(makeDelay(delayTE))
    if i > 0:
      seqObj.addBlock(rotate(@[gx, adc], phi, "z", system))
    else:
      seqObj.addBlock(rotate(@[gx], phi, "z", system))
    seqObj.addBlock(rotate(@[gxSpoil, gzSpoil, makeDelay(delayTR)], phi, "z", system))

  let (ok, errorReport) = seqObj.checkTiming()
  if ok:
    echo "Timing check passed successfully"
  else:
    echo "Timing check failed! Error listing follows:"
    echo errorReport

  seqObj.setDefinition("FOV", @[fov, fov, sliceThickness])
  seqObj.setDefinition("Name", "gre_rad")
  result = seqObj

when isMainModule:
  let seqObj = writeRadialGreSeq()
  seqObj.writeSeq("examples/radial_gre_nim.seq", createSignature = true)

import std/math
import ../src/nimpulseq

proc writeGreSeq*(): Sequence =
  # ======
  # SETUP
  # ======
  let fov = 256e-3
  let Nx = 64
  let Ny = 64
  let alpha = 10.0 # flip angle in degrees
  let sliceThickness = 3e-3
  let TR = 12e-3
  let TE = 5e-3
  let rfSpoilingInc = 117.0

  let system = newOpts(
    maxGrad = 28, gradUnit = "mT/m",
    maxSlew = 150, slewUnit = "T/m/s",
    rfRingdownTime = 20e-6,
    rfDeadTime = 100e-6,
    adcDeadTime = 10e-6,
  )

  var seqObj = newSequence(system)

  # ======
  # CREATE EVENTS
  # ======
  var (rf, gz, _) = makeSincPulse(
    flipAngle = alpha * PI / 180.0,
    duration = 3e-3,
    sliceThickness = sliceThickness,
    apodization = 0.42,
    timeBwProduct = 4.0,
    system = system,
    returnGz = true,
    delay = system.rfDeadTime,
    use = "excitation",
  )

  let deltaK = 1.0 / fov
  let gx = makeTrapezoid(channel = "x", flatArea = float64(Nx) * deltaK, flatTime = 3.2e-3, system = system)
  var adc = makeAdc(numSamples = Nx, duration = gx.trapFlatTime, delay = gx.trapRiseTime, system = system)
  let gxPre = makeTrapezoid(channel = "x", area = -gx.trapArea / 2.0, duration = 1e-3, system = system)
  let gzReph = makeTrapezoid(channel = "z", area = -gz.trapArea / 2.0, duration = 1e-3, system = system)

  var phaseAreas = newSeq[float64](Ny)
  for i in 0 ..< Ny:
    phaseAreas[i] = (float64(i) - float64(Ny) / 2.0) * deltaK

  # Gradient spoiling
  let gxSpoil = makeTrapezoid(channel = "x", area = 2.0 * float64(Nx) * deltaK, system = system)
  let gzSpoil = makeTrapezoid(channel = "z", area = 4.0 / sliceThickness, system = system)

  # Calculate timing
  let delayTE = ceil(
    (TE - (calcDuration(gz, rf) - calcRfCenter(rf).timeCenter - rf.rfDelay) -
     calcDuration(gxPre) - calcDuration(gx) / 2.0 - eps) / seqObj.gradRasterTime
  ) * seqObj.gradRasterTime

  let delayTR = ceil(
    (TR - calcDuration(gz, rf) - calcDuration(gxPre) - calcDuration(gx) - delayTE) /
    seqObj.gradRasterTime
  ) * seqObj.gradRasterTime

  assert delayTE >= 0
  assert delayTR >= calcDuration(gxSpoil, gzSpoil)

  var rfPhase = 0.0
  var rfInc = 0.0

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  for i in 0 ..< Ny:
    rf.rfPhaseOffset = rfPhase / 180.0 * PI
    adc.adcPhaseOffset = rfPhase / 180.0 * PI
    rfInc = (rfInc + rfSpoilingInc) mod 360.0
    rfPhase = (rfPhase + rfInc) mod 360.0

    seqObj.addBlock(rf, gz)
    var gyPre = makeTrapezoid(
      channel = "y",
      area = phaseAreas[i],
      duration = calcDuration(gxPre),
      system = system,
    )
    seqObj.addBlock(gxPre, gyPre, gzReph)
    seqObj.addBlock(makeDelay(delayTE))
    seqObj.addBlock(gx, adc)
    gyPre.trapAmplitude = -gyPre.trapAmplitude
    seqObj.addBlock(makeDelay(delayTR), gxSpoil, gyPre, gzSpoil)

  let (ok, errorReport) = seqObj.checkTiming()
  if ok:
    echo "Timing check passed successfully"
  else:
    echo "Timing check failed. Error listing follows:"
    for e in errorReport:
      echo e

  result = seqObj

when isMainModule:
  let seqObj = writeGreSeq()
  seqObj.setDefinition("FOV", @[256e-3, 256e-3, 3e-3])
  seqObj.setDefinition("Name", "gre")
  seqObj.writeSeq("examples/gre_nim.seq", createSignature = true)

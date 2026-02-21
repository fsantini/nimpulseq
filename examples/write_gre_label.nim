import std/math
import nimpulseq

proc writeGreLabelSeq*(): Sequence =
  # ======
  # SETUP
  # ======
  let fov = 224e-3
  let Nx = 64
  let Ny = Nx
  let alpha = 7.0 # flip angle in degrees
  let sliceThickness = 3e-3
  let nSlices = 1
  let TE = 4.3e-3
  let TR = 10e-3
  let rfSpoilingInc = 117.0
  let roDuration = 3.2e-3

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
    apodization = 0.5,
    timeBwProduct = 4.0,
    system = system,
    returnGz = true,
    delay = system.rfDeadTime,
    use = "excitation",
  )

  let deltaK = 1.0 / fov
  let gx = makeTrapezoid(channel = "x", flatArea = float64(Nx) * deltaK, flatTime = roDuration, system = system)
  var adc = makeAdc(numSamples = Nx, duration = gx.trapFlatTime, delay = gx.trapRiseTime, system = system)
  let gxPre = makeTrapezoid(channel = "x", area = -gx.trapArea / 2.0, duration = 1e-3, system = system)
  let gzReph = makeTrapezoid(channel = "z", area = -gz.trapArea / 2.0, duration = 1e-3, system = system)

  var phaseAreas = newSeq[float64](Ny)
  for i in 0 ..< Ny:
    phaseAreas[i] = -(float64(i) - float64(Ny) / 2.0) * deltaK

  # Gradient spoiling
  let gxSpoil = makeTrapezoid(channel = "x", area = 2.0 * float64(Nx) * deltaK, system = system)
  let gzSpoil = makeTrapezoid(channel = "z", area = 4.0 / sliceThickness, system = system)

  # Calculate timing
  let delayTE = ceil(
    (TE - calcDuration(gxPre) - gz.trapFallTime - gz.trapFlatTime / 2.0 -
     calcDuration(gx) / 2.0) / seqObj.gradRasterTime
  ) * seqObj.gradRasterTime

  let delayTR = ceil(
    (TR - calcDuration(gz) - calcDuration(gxPre) - calcDuration(gx) - delayTE) /
    seqObj.gradRasterTime
  ) * seqObj.gradRasterTime

  assert delayTE >= 0
  assert delayTR >= calcDuration(gxSpoil, gzSpoil)

  var rfPhase = 0.0
  var rfInc = 0.0

  seqObj.addBlock(makeLabel("SET", "REV", 1))

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  for s in 0 ..< nSlices:
    rf.rfFreqOffset = gz.trapAmplitude * sliceThickness * (float64(s) - float64(nSlices - 1) / 2.0)
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
      var spoilBlockContents = @[makeDelay(delayTR), gxSpoil, gyPre, gzSpoil]
      if i != Ny - 1:
        spoilBlockContents.add(makeLabel("INC", "LIN", 1))
      else:
        spoilBlockContents.add(makeLabel("SET", "LIN", 0))
        spoilBlockContents.add(makeLabel("INC", "SLC", 1))
      seqObj.addBlock(spoilBlockContents)

  let (ok, errorReport) = seqObj.checkTiming()
  if ok:
    echo "Timing check passed successfully"
  else:
    echo "Timing check failed. Error listing follows:"
    for e in errorReport:
      echo e

  seqObj.setDefinition("FOV", @[224e-3, 224e-3, 3e-3])
  seqObj.setDefinition("Name", "gre_label")
  result = seqObj

when isMainModule:
  let seqObj = writeGreLabelSeq()
  seqObj.writeSeq("examples/gre_label_nim.seq", createSignature = true)

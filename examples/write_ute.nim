import std/math
import ../src/nimpulseq

proc writeUteSeq*(): Sequence =
  # ======
  # SETUP
  # ======
  let fov = 250e-3
  let Nx = 64
  let alpha = 10
  let sliceThickness = 3e-3
  let TR = 10e-3
  let Nr = 32
  let delta = 2.0 * PI / float64(Nr)
  let roDuration = 2.56e-3
  let roOs = 2
  var roAsymmetry = 1.0

  let rfSpoilingInc = 117

  let system = newOpts(
    maxGrad = 28, gradUnit = "mT/m",
    maxSlew = 100, slewUnit = "T/m/s",
    rfRingdownTime = 20e-6,
    rfDeadTime = 100e-6,
    adcDeadTime = 10e-6,
  )

  var seqObj = newSequence(system)

  # ======
  # CREATE EVENTS
  # ======
  var (rf, gz, gzReph) = makeSincPulse(
    flipAngle = float64(alpha) * PI / 180.0,
    duration = 1e-3,
    sliceThickness = sliceThickness,
    apodization = 0.5,
    timeBwProduct = 2.0,
    centerPos = 1.0,
    system = system,
    returnGz = true,
    delay = system.rfDeadTime,
    use = "excitation",
  )

  # Align RO asymmetry to ADC samples
  let Nxo = round(float64(roOs) * float64(Nx))
  roAsymmetry = roundHalfUp(roAsymmetry * Nxo / 2.0) / Nxo * 2.0

  # Define other gradients and ADC events
  let deltaK = 1.0 / fov / (1.0 + roAsymmetry)
  let roArea = float64(Nx) * deltaK
  var gx = makeTrapezoid(channel = "x", flatArea = roArea, flatTime = roDuration, system = system)
  var adc = makeAdc(numSamples = int(Nxo), duration = gx.trapFlatTime, delay = gx.trapRiseTime, system = system)
  let gxPre = makeTrapezoid(
    channel = "x",
    area = -(gx.trapArea - roArea) / 2.0 - gx.trapAmplitude * adc.adcDwell / 2.0 - roArea / 2.0 * (1.0 - roAsymmetry),
    system = system,
  )

  # Gradient spoiling
  let gxSpoil = makeTrapezoid(channel = "x", area = 0.2 * float64(Nx) * deltaK, system = system)

  # Calculate timing
  let TE = gz.trapFallTime + calcDuration(gxPre, gzReph) + gx.trapRiseTime + adc.adcDwell * Nxo / 2.0 * (1.0 - roAsymmetry)
  let delayTR =
    ceil(
      (TR - calcDuration(gxPre, gzReph) - calcDuration(gz) - calcDuration(gx)) /
      seqObj.gradRasterTime
    ) * seqObj.gradRasterTime
  assert delayTR >= calcDuration(gxSpoil)

  echo "TE = ", int(round(TE * 1e6)), " us"

  if calcDuration(gzReph) > calcDuration(gxPre):
    gxPre.trapDelay = calcDuration(gzReph) - calcDuration(gxPre)

  var rfPhase = 0.0
  var rfInc = 0.0

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  for i in 0 ..< Nr:
    for c in 0 ..< 2:
      rf.rfPhaseOffset = rfPhase / 180.0 * PI
      adc.adcPhaseOffset = rfPhase / 180.0 * PI
      rfInc = (rfInc + float64(rfSpoilingInc)) mod 360.0
      rfPhase = (rfPhase + rfInc) mod 360.0

      gz.trapAmplitude = -gz.trapAmplitude
      gzReph.trapAmplitude = -gzReph.trapAmplitude

      seqObj.addBlock(rf, gz)
      let phi = delta * float64(i)

      # gx_pre copies
      var gpc = Event(kind: ekTrap)
      gpc.trapChannel = gxPre.trapChannel
      gpc.trapAmplitude = gxPre.trapAmplitude * cos(phi)
      gpc.trapRiseTime = gxPre.trapRiseTime
      gpc.trapFlatTime = gxPre.trapFlatTime
      gpc.trapFallTime = gxPre.trapFallTime
      gpc.trapArea = gxPre.trapArea * cos(phi)
      gpc.trapFlatArea = gxPre.trapFlatArea * cos(phi)
      gpc.trapDelay = gxPre.trapDelay
      gpc.trapFirst = gxPre.trapFirst
      gpc.trapLast = gxPre.trapLast

      var gps = Event(kind: ekTrap)
      gps.trapChannel = gcY
      gps.trapAmplitude = gxPre.trapAmplitude * sin(phi)
      gps.trapRiseTime = gxPre.trapRiseTime
      gps.trapFlatTime = gxPre.trapFlatTime
      gps.trapFallTime = gxPre.trapFallTime
      gps.trapArea = gxPre.trapArea * sin(phi)
      gps.trapFlatArea = gxPre.trapFlatArea * sin(phi)
      gps.trapDelay = gxPre.trapDelay
      gps.trapFirst = gxPre.trapFirst
      gps.trapLast = gxPre.trapLast

      # gx copies
      var grc = Event(kind: ekTrap)
      grc.trapChannel = gx.trapChannel
      grc.trapAmplitude = gx.trapAmplitude * cos(phi)
      grc.trapRiseTime = gx.trapRiseTime
      grc.trapFlatTime = gx.trapFlatTime
      grc.trapFallTime = gx.trapFallTime
      grc.trapArea = gx.trapArea * cos(phi)
      grc.trapFlatArea = gx.trapFlatArea * cos(phi)
      grc.trapDelay = gx.trapDelay
      grc.trapFirst = gx.trapFirst
      grc.trapLast = gx.trapLast

      var grs = Event(kind: ekTrap)
      grs.trapChannel = gcY
      grs.trapAmplitude = gx.trapAmplitude * sin(phi)
      grs.trapRiseTime = gx.trapRiseTime
      grs.trapFlatTime = gx.trapFlatTime
      grs.trapFallTime = gx.trapFallTime
      grs.trapArea = gx.trapArea * sin(phi)
      grs.trapFlatArea = gx.trapFlatArea * sin(phi)
      grs.trapDelay = gx.trapDelay
      grs.trapFirst = gx.trapFirst
      grs.trapLast = gx.trapLast

      # gx_spoil copies
      var gsc = Event(kind: ekTrap)
      gsc.trapChannel = gxSpoil.trapChannel
      gsc.trapAmplitude = gxSpoil.trapAmplitude * cos(phi)
      gsc.trapRiseTime = gxSpoil.trapRiseTime
      gsc.trapFlatTime = gxSpoil.trapFlatTime
      gsc.trapFallTime = gxSpoil.trapFallTime
      gsc.trapArea = gxSpoil.trapArea * cos(phi)
      gsc.trapFlatArea = gxSpoil.trapFlatArea * cos(phi)
      gsc.trapDelay = gxSpoil.trapDelay
      gsc.trapFirst = gxSpoil.trapFirst
      gsc.trapLast = gxSpoil.trapLast

      var gss = Event(kind: ekTrap)
      gss.trapChannel = gcY
      gss.trapAmplitude = gxSpoil.trapAmplitude * sin(phi)
      gss.trapRiseTime = gxSpoil.trapRiseTime
      gss.trapFlatTime = gxSpoil.trapFlatTime
      gss.trapFallTime = gxSpoil.trapFallTime
      gss.trapArea = gxSpoil.trapArea * sin(phi)
      gss.trapFlatArea = gxSpoil.trapFlatArea * sin(phi)
      gss.trapDelay = gxSpoil.trapDelay
      gss.trapFirst = gxSpoil.trapFirst
      gss.trapLast = gxSpoil.trapLast

      seqObj.addBlock(gpc, gps, gzReph)
      seqObj.addBlock(grc, grs, adc)
      seqObj.addBlock(gsc, gss, makeDelay(delayTR))

  let (ok, errorReport) = seqObj.checkTiming()
  if ok:
    echo "Timing check passed successfully"
  else:
    echo "Timing check failed. Error listing follows:"
    echo errorReport

  result = seqObj

when isMainModule:
  let seqObj = writeUteSeq()
  seqObj.setDefinition("FOV", @[250e-3, 250e-3, 3e-3])
  seqObj.setDefinition("Name", "UTE")
  seqObj.writeSeq("examples/ute_nim.seq", createSignature = true)

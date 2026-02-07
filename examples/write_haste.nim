import std/math
import ../src/nimpulseq

proc main() =
  # ======
  # SETUP
  # ======
  let dG = 250e-6

  let system = newOpts(
    maxGrad = 30, gradUnit = "mT/m",
    maxSlew = 170, slewUnit = "T/m/s",
    rfRingdownTime = 100e-6,
    rfDeadTime = 100e-6,
    adcDeadTime = 10e-6,
  )

  var seqObj = newSequence(system)
  let fov = 256e-3
  let NyPre = 8
  let Nx = 64
  let Ny = 64
  let nEcho = int(Ny div 2 + NyPre)
  let nSlices = 1
  let rfFlip = 180.0  # Will be used as constant for all echoes
  let sliceThickness = 5e-3
  let TE = 12e-3
  let TR = 2000e-3

  let samplingTime = 6.4e-3
  let readoutTime = samplingTime + 2.0 * system.adcDeadTime
  let tEx = 2.5e-3
  let tExWd = tEx + system.rfRingdownTime + system.rfDeadTime
  let tRef = 2e-3
  let tfRefWd = tRef + system.rfRingdownTime + system.rfDeadTime
  let tSp = 0.5 * (TE - readoutTime - tfRefWd)
  let tSpEx = 0.5 * (TE - tExWd - tfRefWd)
  let fspR = 1.0
  let fspS = 0.5

  let rfexPhase = PI / 2.0
  let rfrefPhase = 0.0

  # ======
  # CREATE EVENTS
  # ======
  let flipex = 90.0 * PI / 180.0
  var (rfex, gz, _) = makeSincPulse(
    flipAngle = flipex,
    system = system,
    duration = tEx,
    sliceThickness = sliceThickness,
    apodization = 0.5,
    timeBwProduct = 4.0,
    phaseOffset = rfexPhase,
    returnGz = true,
    delay = system.rfDeadTime,
    use = "excitation",
  )
  let gsEx = makeTrapezoid(
    channel = "z",
    system = system,
    amplitude = gz.trapAmplitude,
    flatTime = tExWd,
    riseTime = dG,
  )

  let flipref = rfFlip * PI / 180.0
  var (rfref, gz2, _) = makeSincPulse(
    flipAngle = flipref,
    system = system,
    duration = tRef,
    sliceThickness = sliceThickness,
    apodization = 0.5,
    timeBwProduct = 4.0,
    phaseOffset = rfrefPhase,
    use = "refocusing",
    returnGz = true,
    delay = system.rfDeadTime,
  )
  let gsRef = makeTrapezoid(
    channel = "z",
    system = system,
    amplitude = gsEx.trapAmplitude,
    flatTime = tfRefWd,
    riseTime = dG,
  )

  let agsEx = gsEx.trapArea / 2.0
  let gsSpr = makeTrapezoid(
    channel = "z",
    system = system,
    area = agsEx * (1.0 + fspS),
    duration = tSp,
    riseTime = dG,
  )
  let gsSpex = makeTrapezoid(channel = "z", system = system, area = agsEx * fspS, duration = tSpEx, riseTime = dG)

  let deltaK = 1.0 / fov
  let kWidth = float64(Nx) * deltaK

  let grAcq = makeTrapezoid(
    channel = "x",
    system = system,
    flatArea = kWidth,
    flatTime = readoutTime,
    riseTime = dG,
  )
  let adc = makeAdc(numSamples = Nx, duration = samplingTime, delay = system.adcDeadTime, system = system)
  let grSpr = makeTrapezoid(channel = "x", system = system, area = grAcq.trapArea * fspR, duration = tSp, riseTime = dG)

  let agrSpr = grSpr.trapArea
  let agrPreph = grAcq.trapArea / 2.0 + agrSpr
  let grPreph = makeTrapezoid(channel = "x", system = system, area = agrPreph, duration = tSpEx, riseTime = dG)

  let nEx = 1
  # PE_order = np.arange(-Ny_pre, Ny + 1).T
  var phaseAreas = newSeq[float64](NyPre + Ny + 1)
  for i in 0 ..< phaseAreas.len:
    phaseAreas[i] = float64(i - NyPre) * deltaK

  # Split gradients and recombine into blocks
  let gs1 = makeExtendedTrapezoid(
    channel = "z",
    times = @[0.0, gsEx.trapRiseTime],
    amplitudes = @[0.0, gsEx.trapAmplitude],
  )

  let gs2 = makeExtendedTrapezoid(
    channel = "z",
    times = @[0.0, gsEx.trapFlatTime],
    amplitudes = @[gsEx.trapAmplitude, gsEx.trapAmplitude],
  )

  let gs3 = makeExtendedTrapezoid(
    channel = "z",
    times = @[
      0.0,
      gsSpex.trapRiseTime,
      gsSpex.trapRiseTime + gsSpex.trapFlatTime,
      gsSpex.trapRiseTime + gsSpex.trapFlatTime + gsSpex.trapFallTime,
    ],
    amplitudes = @[gsEx.trapAmplitude, gsSpex.trapAmplitude, gsSpex.trapAmplitude, gsRef.trapAmplitude],
  )

  let gs4 = makeExtendedTrapezoid(
    channel = "z",
    times = @[0.0, gsRef.trapFlatTime],
    amplitudes = @[gsRef.trapAmplitude, gsRef.trapAmplitude],
  )

  let gs5 = makeExtendedTrapezoid(
    channel = "z",
    times = @[
      0.0,
      gsSpr.trapRiseTime,
      gsSpr.trapRiseTime + gsSpr.trapFlatTime,
      gsSpr.trapRiseTime + gsSpr.trapFlatTime + gsSpr.trapFallTime,
    ],
    amplitudes = @[gsRef.trapAmplitude, gsSpr.trapAmplitude, gsSpr.trapAmplitude, 0.0],
  )

  let gs7 = makeExtendedTrapezoid(
    channel = "z",
    times = @[
      0.0,
      gsSpr.trapRiseTime,
      gsSpr.trapRiseTime + gsSpr.trapFlatTime,
      gsSpr.trapRiseTime + gsSpr.trapFlatTime + gsSpr.trapFallTime,
    ],
    amplitudes = @[0.0, gsSpr.trapAmplitude, gsSpr.trapAmplitude, gsRef.trapAmplitude],
  )

  # Readout gradient
  let gr3 = grPreph

  let gr5 = makeExtendedTrapezoid(
    channel = "x",
    times = @[
      0.0,
      grSpr.trapRiseTime,
      grSpr.trapRiseTime + grSpr.trapFlatTime,
      grSpr.trapRiseTime + grSpr.trapFlatTime + grSpr.trapFallTime,
    ],
    amplitudes = @[0.0, grSpr.trapAmplitude, grSpr.trapAmplitude, grAcq.trapAmplitude],
  )

  let gr6 = makeExtendedTrapezoid(
    channel = "x",
    times = @[0.0, readoutTime],
    amplitudes = @[grAcq.trapAmplitude, grAcq.trapAmplitude],
  )

  let gr7 = makeExtendedTrapezoid(
    channel = "x",
    times = @[
      0.0,
      grSpr.trapRiseTime,
      grSpr.trapRiseTime + grSpr.trapFlatTime,
      grSpr.trapRiseTime + grSpr.trapFlatTime + grSpr.trapFallTime,
    ],
    amplitudes = @[grAcq.trapAmplitude, grSpr.trapAmplitude, grSpr.trapAmplitude, 0.0],
  )

  # Fill-times
  let texDur = gs1.gradShapeDur + gs2.gradShapeDur + gs3.gradShapeDur
  let trefDur = gs4.gradShapeDur + gs5.gradShapeDur + gs7.gradShapeDur + readoutTime
  let tendDur = gs4.gradShapeDur + gs5.gradShapeDur
  let teTrain = texDur + float64(nEcho) * trefDur + tendDur
  var trFill = (TR - float64(nSlices) * teTrain) / float64(nSlices)

  trFill = system.gradRasterTime * round(trFill / system.gradRasterTime)
  if trFill < 0:
    trFill = 1e-3
    echo "TR too short, adapted to include all slices to: ", 1000.0 * float64(nSlices) * (teTrain + trFill), " ms"
  else:
    echo "TR fill: ", 1000.0 * trFill, " ms"
  let delayTR = makeDelay(trFill)
  let delayEnd = makeDelay(5.0)

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  for kEx in 0 ..< nEx:
    for s in 0 ..< nSlices:
      rfex.rfFreqOffset = gsEx.trapAmplitude * sliceThickness * (float64(s) - float64(nSlices - 1) / 2.0)
      rfref.rfFreqOffset = gsRef.trapAmplitude * sliceThickness * (float64(s) - float64(nSlices - 1) / 2.0)
      rfex.rfPhaseOffset = rfexPhase - 2.0 * PI * rfex.rfFreqOffset * calcRfCenter(rfex)[0]
      rfref.rfPhaseOffset = rfrefPhase - 2.0 * PI * rfref.rfFreqOffset * calcRfCenter(rfref)[0]

      seqObj.addBlock(gs1)
      seqObj.addBlock(rfex, gs2)
      seqObj.addBlock(gs3, gr3)

      for kEch in 0 ..< nEcho:
        var phaseArea: float64
        if kEx >= 0:
          phaseArea = phaseAreas[kEch]
        else:
          phaseArea = 0.0

        let gpPre = makeTrapezoid(
          channel = "y",
          system = system,
          area = phaseArea,
          duration = tSp,
          riseTime = dG,
        )
        let gpRew = makeTrapezoid(
          channel = "y",
          system = system,
          area = -phaseArea,
          duration = tSp,
          riseTime = dG,
        )

        seqObj.addBlock(rfref, gs4)
        seqObj.addBlock(gr5, gpPre, gs5)

        if kEx >= 0:
          seqObj.addBlock(gr6, adc)
        else:
          seqObj.addBlock(gr6)

        seqObj.addBlock(gr7, gpRew, gs7)

      seqObj.addBlock(gs4)
      seqObj.addBlock(gs5)
      seqObj.addBlock(delayTR)

  seqObj.addBlock(delayEnd)

  let (ok, errorReport) = seqObj.checkTiming()
  if ok:
    echo "Timing check passed successfully"
  else:
    echo "Timing check failed. Error listing follows:"
    echo errorReport

  seqObj.writeSeq("examples/haste_nim.seq", createSignature = true)

main()

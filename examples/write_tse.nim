import std/math
import ../src/nimpulseq

proc writeTseSeq*(): Sequence =
  # ======
  # SETUP
  # ======
  let dG = 250e-6

  let system = newOpts(
    maxGrad = 32, gradUnit = "mT/m",
    maxSlew = 130, slewUnit = "T/m/s",
    rfRingdownTime = 100e-6,
    rfDeadTime = 100e-6,
    adcDeadTime = 10e-6,
  )

  var seqObj = newSequence(system)
  let fov = 256e-3
  let Nx = 64
  let Ny = 64
  let nEcho = 16
  let nSlices = 1
  let rfFlip = 180.0
  let sliceThickness = 5e-3
  let TE = 12e-3
  let TR = 2000e-3

  let samplingTime = 6.4e-3
  let readoutTime = samplingTime + 2.0 * system.adcDeadTime
  let tEx = 2.5e-3
  let tExwd = tEx + system.rfRingdownTime + system.rfDeadTime
  let tRef = 2e-3
  let tRefwd = tRef + system.rfRingdownTime + system.rfDeadTime
  let tSp = 0.5 * (TE - readoutTime - tRefwd)
  let tSpex = 0.5 * (TE - tExwd - tRefwd)
  let fspR = 1.0
  let fspS = 0.5

  let rfExPhase = PI / 2.0
  let rfRefPhase = 0.0

  # ======
  # CREATE EVENTS
  # ======
  let flipEx = 90.0 * PI / 180.0
  var (rfEx, gz, _) = makeSincPulse(
    flipAngle = flipEx,
    system = system,
    duration = tEx,
    sliceThickness = sliceThickness,
    apodization = 0.5,
    timeBwProduct = 4.0,
    phaseOffset = rfExPhase,
    returnGz = true,
    delay = system.rfDeadTime,
    use = "excitation",
  )
  let gsEx = makeTrapezoid(
    channel = "z",
    system = system,
    amplitude = gz.trapAmplitude,
    flatTime = tExwd,
    riseTime = dG,
  )

  let flipRef = rfFlip * PI / 180.0
  var (rfRef, gz2, _) = makeSincPulse(
    flipAngle = flipRef,
    system = system,
    duration = tRef,
    sliceThickness = sliceThickness,
    apodization = 0.5,
    timeBwProduct = 4.0,
    phaseOffset = rfRefPhase,
    use = "refocusing",
    returnGz = true,
    delay = system.rfDeadTime,
  )
  let gsRef = makeTrapezoid(
    channel = "z",
    system = system,
    amplitude = gsEx.trapAmplitude,
    flatTime = tRefwd,
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
  let gsSpex = makeTrapezoid(channel = "z", system = system, area = agsEx * fspS, duration = tSpex, riseTime = dG)

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
  let grSpr = makeTrapezoid(
    channel = "x",
    system = system,
    area = grAcq.trapArea * fspR,
    duration = tSp,
    riseTime = dG,
  )

  let agrSpr = grSpr.trapArea
  let agrPreph = grAcq.trapArea / 2.0 + agrSpr
  let grPreph = makeTrapezoid(channel = "x", system = system, area = agrPreph, duration = tSpex, riseTime = dG)

  # Phase-encoding
  let nEx = int(floor(float64(Ny) / float64(nEcho)))
  # pe_steps = np.arange(1, n_echo * n_ex + 1) - 0.5 * n_echo * n_ex - 1
  var peSteps = newSeq[float64](nEcho * nEx)
  for i in 0 ..< peSteps.len:
    peSteps[i] = float64(i + 1) - 0.5 * float64(nEcho * nEx) - 1.0

  if nEcho mod 2 == 0:
    # roll by -round(n_ex / 2)
    let rollBy = -int(round(float64(nEx) / 2.0))
    var temp = peSteps
    for i in 0 ..< peSteps.len:
      let srcIdx = ((i - rollBy) mod peSteps.len + peSteps.len) mod peSteps.len
      peSteps[i] = temp[srcIdx]

  # pe_order = pe_steps.reshape((n_ex, n_echo), order='F').T
  # Fortran order: mat[ex, echo] = pe_steps[ex + echo * n_ex]
  # After transpose: pe_order[echo, ex] = mat[ex, echo] = pe_steps[ex + echo * n_ex]
  proc phaseArea(kEcho, kEx: int): float64 =
    peSteps[kEx + kEcho * nEx] * deltaK

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
  let texDur = calcDuration(gs1) + calcDuration(gs2) + calcDuration(gs3)
  let trefDur = calcDuration(gs4) + calcDuration(gs5) + calcDuration(gs7) + readoutTime
  let tendDur = calcDuration(gs4) + calcDuration(gs5)

  let teTrain = texDur + float64(nEcho) * trefDur + tendDur
  var trFill = (TR - float64(nSlices) * teTrain) / float64(nSlices)
  trFill = system.gradRasterTime * round(trFill / system.gradRasterTime)
  if trFill < 0:
    trFill = 1e-3
    echo "TR too short, adapted to include all slices to: ", 1000.0 * float64(nSlices) * (teTrain + trFill), " ms"
  else:
    echo "TR fill: ", 1000.0 * trFill, " ms"
  let delayTR = makeDelay(trFill)

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  for kEx in 0 .. nEx:
    for s in 0 ..< nSlices:
      rfEx.rfFreqOffset = gsEx.trapAmplitude * sliceThickness * (float64(s) - float64(nSlices - 1) / 2.0)
      rfRef.rfFreqOffset = gsRef.trapAmplitude * sliceThickness * (float64(s) - float64(nSlices - 1) / 2.0)
      rfEx.rfPhaseOffset = rfExPhase - 2.0 * PI * rfEx.rfFreqOffset * calcRfCenter(rfEx)[0]
      rfRef.rfPhaseOffset = rfRefPhase - 2.0 * PI * rfRef.rfFreqOffset * calcRfCenter(rfRef)[0]

      seqObj.addBlock(gs1)
      seqObj.addBlock(rfEx, gs2)
      seqObj.addBlock(gs3, gr3)

      for kEcho in 0 ..< nEcho:
        var pa: float64
        if kEx > 0:
          pa = phaseArea(kEcho, kEx - 1)
        else:
          pa = 0.0

        let gpPre = makeTrapezoid(
          channel = "y",
          system = system,
          area = pa,
          duration = tSp,
          riseTime = dG,
        )
        let gpRew = makeTrapezoid(
          channel = "y",
          system = system,
          area = -pa,
          duration = tSp,
          riseTime = dG,
        )
        seqObj.addBlock(rfRef, gs4)
        seqObj.addBlock(gr5, gpPre, gs5)
        if kEx > 0:
          seqObj.addBlock(gr6, adc)
        else:
          seqObj.addBlock(gr6)
        seqObj.addBlock(gr7, gpRew, gs7)

      seqObj.addBlock(gs4)
      seqObj.addBlock(gs5)
      seqObj.addBlock(delayTR)

  let (ok, errorReport) = seqObj.checkTiming()
  if ok:
    echo "Timing check passed successfully"
  else:
    echo "Timing check failed. Error listing follows:"
    echo errorReport

  result = seqObj

when isMainModule:
  let seqObj = writeTseSeq()
  seqObj.writeSeq("examples/tse_nim.seq", createSignature = true)

import std/math
import ../src/nimpulseq

proc main() =
  # ======
  # SETUP
  # ======
  let system = newOpts(
    maxGrad = 24, gradUnit = "mT/m",
    maxSlew = 100, slewUnit = "T/m/s",
    rfRingdownTime = 20e-6,
    rfDeadTime = 100e-6,
    adcDeadTime = 10e-6,
  )

  var seqObj = newSequence(system)

  let alpha = 7
  let roDur = 5017.6e-6
  let roOs = 1
  let roSpoil = 3
  let TI = 1.1
  let TRout = 2.5

  let rfSpoilingInc = 117
  let rfLen = 100e-6

  # Encoding axes
  let fov = @[192e-3, 240e-3, 256e-3]
  let N = @[48, 60, 64]
  let axD1 = "z"  # Fastest dimension (readout)
  let axD2 = "x"  # Second-fastest dimension (inner phase-encoding loop)
  let axD3 = "y"  # Third dimension
  let axN1 = 2  # z index
  let axN2 = 0  # x index
  let axN3 = 1  # y index

  # Create alpha-degree hard pulse and gradient
  let rf = makeBlockPulse(
    flipAngle = float64(alpha) * PI / 180.0,
    system = system,
    duration = rfLen,
    delay = system.rfDeadTime,
    use = "excitation",
  )
  let rf180 = makeAdiabaticPulse(
    pulseType = "hypsec",
    system = system,
    duration = 10.24e-3,
    dwell = 1e-5,
    delay = system.rfDeadTime,
    use = "inversion",
  ).rf

  # Define other gradients and ADC events
  let deltak = @[1.0 / fov[0], 1.0 / fov[1], 1.0 / fov[2]]
  let gro = makeTrapezoid(
    channel = axD1,
    amplitude = float64(N[axN1]) * deltak[axN1] / roDur,
    flatTime = ceil((roDur + system.adcDeadTime) / system.gradRasterTime) * system.gradRasterTime,
    system = system,
  )
  var adc = makeAdc(
    numSamples = N[axN1] * roOs,
    duration = roDur,
    delay = gro.trapRiseTime,
    system = system,
  )
  let groPre = makeTrapezoid(
    channel = axD1,
    area = -gro.trapAmplitude * (adc.adcDwell * (float64(adc.adcNumSamples) / 2.0 + 0.5) + 0.5 * gro.trapRiseTime),
    system = system,
  )
  let gpe1 = makeTrapezoid(channel = axD2, area = -deltak[axN2] * (float64(N[axN2]) / 2.0), system = system)
  let gpe2 = makeTrapezoid(channel = axD3, area = -deltak[axN3] * (float64(N[axN3]) / 2.0), system = system)
  let gslSp = makeTrapezoid(
    channel = axD3,
    area = max(max(deltak[0] * float64(N[0]), deltak[1] * float64(N[1])), deltak[2] * float64(N[2])) * 4.0,
    duration = 10e-3,
    system = system,
  )

  # We cut the RO gradient into two parts for the optimal spoiler timing
  var (gro1, groSp) = splitGradientAt(grad = gro, timePoint = gro.trapRiseTime + gro.trapFlatTime, system = system)
  # Gradient spoiling
  if roSpoil > 0:
    groSp = makeExtendedTrapezoidArea(
      channel = axD1,
      gradStart = gro.trapAmplitude,
      gradEnd = 0.0,
      area = deltak[axN1] / 2.0 * float64(N[axN1]) * float64(roSpoil),
      system = system,
    ).grad

  # Calculate timing of the fast loop
  rf.rfDelay = calcDuration(groSp, gpe1, gpe2)
  var aligned = alignEvents(asRight, @[groPre, gpe1, gpe2])
  var groPreAligned = aligned[0]
  gro1.gradDelay = calcDuration(groPreAligned)
  adc.adcDelay = gro1.gradDelay + gro.trapRiseTime
  gro1 = addGradients(@[gro1, groPreAligned], system)
  let trInner = calcDuration(rf) + calcDuration(gro1)

  # pe_steps
  var pe1Steps = newSeq[float64](N[axN2])
  for i in 0 ..< N[axN2]:
    pe1Steps[i] = (float64(i) - float64(N[axN2]) / 2.0) / float64(N[axN2]) * 2.0
  var pe2Steps = newSeq[float64](N[axN3])
  for i in 0 ..< N[axN3]:
    pe2Steps[i] = (float64(i) - float64(N[axN3]) / 2.0) / float64(N[axN3]) * 2.0

  # Find index where pe1_steps == 0
  var pe1ZeroIdx = 0
  for i in 0 ..< pe1Steps.len:
    if pe1Steps[i] == 0.0:
      pe1ZeroIdx = i
      break

  # TI calc
  let tiDelay =
    round(
      (TI -
        float64(pe1ZeroIdx) * trInner -
        (calcDuration(rf180) - calcRfCenter(rf180)[0] - rf180.rfDelay) -
        rf.rfDelay -
        calcRfCenter(rf)[0]) /
      system.blockDurationRaster
    ) * system.blockDurationRaster
  let trOutDelay = TRout - trInner * float64(N[axN2]) - tiDelay - calcDuration(rf180)

  let labelIncLin = makeLabel("INC", "LIN", 1)
  let labelIncPar = makeLabel("INC", "PAR", 1)
  let labelResetPar = makeLabel("SET", "PAR", 0)

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  for j in 0 ..< N[axN3]:
    seqObj.addBlock(rf180)
    seqObj.addBlock(makeDelay(tiDelay), gslSp)
    var rfPhase = 0.0
    var rfInc = 0.0
    # Pre-register PE events that repeat in the inner loop
    let gpe2je = scaleGrad(grad = gpe2, scale = pe2Steps[j])
    discard seqObj.registerGradEvent(gpe2je)
    let gpe2jr = scaleGrad(grad = gpe2, scale = -pe2Steps[j])
    discard seqObj.registerGradEvent(gpe2jr)

    for i in 0 ..< N[axN2]:
      rf.rfPhaseOffset = rfPhase / 180.0 * PI
      adc.adcPhaseOffset = rfPhase / 180.0 * PI
      rfInc = (rfInc + float64(rfSpoilingInc)) mod 360.0
      rfPhase = (rfPhase + rfInc) mod 360.0

      if i == 0:
        seqObj.addBlock(rf)
      else:
        seqObj.addBlock(
          rf,
          groSp,
          scaleGrad(grad = gpe1, scale = -pe1Steps[i - 1]),
          gpe2jr,
          labelIncPar,
        )
      seqObj.addBlock(adc, gro1, scaleGrad(grad = gpe1, scale = pe1Steps[i]), gpe2je)
    seqObj.addBlock(groSp, makeDelay(trOutDelay), labelResetPar, labelIncLin)

  seqObj.writeSeq("examples/mprage_nim.seq", createSignature = true)

main()

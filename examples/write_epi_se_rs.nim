import std/math
import ../src/nimpulseq

proc main() =
  # ======
  # SETUP
  # ======
  let fov = 250e-3
  let Nx = 64
  let Ny = 64
  let sliceThickness = 3e-3
  let nSlices = 3
  let TE = 40e-3

  let peEnable = 1
  let roOs = 1
  let readoutTime = 4.2e-4
  let partFourierFactor = 0.75

  let tRFex = 2e-3
  let tRFref = 2e-3
  let spoilFactor = 1.5

  let system = newOpts(
    maxGrad = 32, gradUnit = "mT/m",
    maxSlew = 130, slewUnit = "T/m/s",
    rfRingdownTime = 30e-6,
    rfDeadTime = 100e-6,
  )

  var seqObj = newSequence(system)

  # ======
  # CREATE EVENTS
  # ======
  # Create fat-sat pulse
  let B0 = 2.89
  let satPpm = -3.45
  let satFreq = satPpm * 1e-6 * B0 * system.gamma
  let rfFs = makeGaussPulse(
    flipAngle = 110.0 * PI / 180.0,
    system = system,
    duration = 8e-3,
    bandwidth = abs(satFreq),
    freqOffset = satFreq,
    delay = system.rfDeadTime,
    use = "saturation",
  ).rf
  let gzFs = makeTrapezoid(channel = "z", system = system, delay = calcDuration(rfFs), area = 1.0 / 1e-4)

  # Create 90 degree slice selection pulse and gradient
  var (rf, gz, gzReph) = makeSincPulse(
    flipAngle = PI / 2.0,
    system = system,
    duration = tRFex,
    sliceThickness = sliceThickness,
    apodization = 0.5,
    timeBwProduct = 4.0,
    returnGz = true,
    delay = system.rfDeadTime,
    use = "excitation",
  )

  # Create 90 degree slice refocusing pulse and gradients
  var (rf180, gz180, _) = makeSincPulse(
    flipAngle = PI,
    system = system,
    duration = tRFref,
    sliceThickness = sliceThickness,
    apodization = 0.5,
    timeBwProduct = 4.0,
    phaseOffset = PI / 2.0,
    use = "refocusing",
    returnGz = true,
    delay = system.rfDeadTime,
  )
  var (_, gzr1T, gzr1A) = makeExtendedTrapezoidArea(
    channel = "z",
    gradStart = 0.0,
    gradEnd = gz180.trapAmplitude,
    area = spoilFactor * gz.trapArea,
    system = system,
  )
  var (_, gzr2T, gzr2A) = makeExtendedTrapezoidArea(
    channel = "z",
    gradStart = gz180.trapAmplitude,
    gradEnd = 0.0,
    area = -gzReph.trapArea + spoilFactor * gz.trapArea,
    system = system,
  )
  if gz180.trapDelay > (gzr1T[3] - gz180.trapRiseTime):
    gz180.trapDelay -= gzr1T[3] - gz180.trapRiseTime
  else:
    rf180.rfDelay += (gzr1T[3] - gz180.trapRiseTime) - gz180.trapDelay

  # Construct combined times for gz180n
  var gz180nTimes: seq[float64] = @[]
  for t in gzr1T:
    gz180nTimes.add(t + gz180.trapDelay)
  for t in gzr2T:
    gz180nTimes.add(gzr1T[3] + gz180.trapFlatTime + t + gz180.trapDelay)
  var gz180nAmps: seq[float64] = @[]
  for a in gzr1A:
    gz180nAmps.add(a)
  for a in gzr2A:
    gz180nAmps.add(a)

  let gz180n = makeExtendedTrapezoid(
    channel = "z",
    system = system,
    times = gz180nTimes,
    amplitudes = gz180nAmps,
  )

  # Define the output trigger
  let trig = makeDigitalOutputPulse(channel = "osc0", duration = 100e-6)

  # Define other gradients and ADC events
  let deltaK = 1.0 / fov
  let kWidth = float64(Nx) * deltaK

  # Phase blip in shortest possible time
  let blipDuration = ceil(2.0 * sqrt(deltaK / system.maxSlew) / 10e-6 / 2.0) * 10e-6 * 2.0
  let gy = makeTrapezoid(channel = "y", system = system, area = -deltaK, duration = blipDuration)

  # Readout gradient
  let extraArea = blipDuration / 2.0 * blipDuration / 2.0 * system.maxSlew
  var gx = makeTrapezoid(
    channel = "x",
    system = system,
    area = kWidth + extraArea,
    duration = readoutTime + blipDuration,
  )
  var actualArea = gx.trapArea - gx.trapAmplitude / gx.trapRiseTime * blipDuration / 2.0 * blipDuration / 2.0 / 2.0
  actualArea -= gx.trapAmplitude / gx.trapFallTime * blipDuration / 2.0 * blipDuration / 2.0 / 2.0
  gx.trapAmplitude = gx.trapAmplitude / actualArea * kWidth
  gx.trapArea = gx.trapAmplitude * (gx.trapFlatTime + gx.trapRiseTime / 2.0 + gx.trapFallTime / 2.0)
  gx.trapFlatArea = gx.trapAmplitude * gx.trapFlatTime

  # Calculate ADC with ramp sampling
  let adcDwellNyquist = deltaK / gx.trapAmplitude / float64(roOs)
  let adcDwell = floor(adcDwellNyquist * 1e7) * 1e-7
  let adcSamples = int(floor(readoutTime / adcDwell / 4.0)) * 4
  var adc = makeAdc(numSamples = adcSamples, dwell = adcDwell, delay = blipDuration / 2.0)
  # Realign ADC
  let timeToCenter = adcDwell * (float64(adcSamples - 1) / 2.0 + 0.5)
  adc.adcDelay = round((gx.trapRiseTime + gx.trapFlatTime / 2.0 - timeToCenter) * 1e6) * 1e-6

  # Split the blip into two halves
  let gyParts = splitGradientAt(grad = gy, timePoint = blipDuration / 2.0, system = system)
  let alignedRight = alignEvents(asRight, @[gyParts.grad1])
  let alignedLeft = alignEvents(asLeft, @[gyParts.grad2, gx])
  var gyBlipup = alignedRight[0]
  var gyBlipdown = alignedLeft[0]

  # Need to align right=gy_parts[0] with left=[gy_parts[1], gx]
  # The duration of left group determines the total duration
  let leftDur = max(calcDuration(gyParts.grad2), calcDuration(gx))
  # gyBlipup needs to be right-aligned to leftDur
  gyBlipup.gradDelay = leftDur - calcDuration(gyParts.grad1) + gyParts.grad1.gradDelay

  var gyBlipdownup = addGradients(@[gyBlipdown, gyBlipup], system)

  # pe_enable support
  for i in 0 ..< gyBlipup.gradWaveform.len:
    gyBlipup.gradWaveform[i] = gyBlipup.gradWaveform[i] * float64(peEnable)
  for i in 0 ..< gyBlipdown.gradWaveform.len:
    gyBlipdown.gradWaveform[i] = gyBlipdown.gradWaveform[i] * float64(peEnable)
  for i in 0 ..< gyBlipdownup.gradWaveform.len:
    gyBlipdownup.gradWaveform[i] = gyBlipdownup.gradWaveform[i] * float64(peEnable)

  # Phase encoding and partial Fourier
  let NyPre = int(round(partFourierFactor * float64(Ny) / 2.0 - 1.0))
  let NyPost = int(round(float64(Ny) / 2.0 + 1.0))
  let NyMeas = NyPre + NyPost

  # Pre-phasing gradients
  var gxPre = makeTrapezoid(channel = "x", system = system, area = -gx.trapArea / 2.0)
  var gyPre = makeTrapezoid(channel = "y", system = system, area = float64(NyPre) * deltaK)

  let aligned2 = alignEvents(asRight, @[gxPre])
  gxPre = aligned2[0]
  let aligned3 = alignEvents(asLeft, @[gyPre])
  gyPre = aligned3[0]

  # Use the longer duration for both
  let preDur = max(calcDuration(gxPre), calcDuration(gyPre))
  # Right-align gxPre, left-align gyPre
  gxPre.trapDelay = preDur - calcDuration(gxPre) + gxPre.trapDelay

  # Relax the PE prephaser
  gyPre = makeTrapezoid("y", system = system, area = gyPre.trapArea, duration = calcDuration(gxPre, gyPre))
  gyPre.trapAmplitude = gyPre.trapAmplitude * float64(peEnable)

  # Calculate delay times
  let durationToCenter = (float64(NyPre) + 0.5) * calcDuration(gx)
  let rfCenterInclDelay = rf.rfDelay + calcRfCenter(rf)[0]
  let rf180CenterInclDelay = rf180.rfDelay + calcRfCenter(rf180)[0]
  let delayTE1 =
    ceil(
      (TE / 2.0 - calcDuration(rf, gz) + rfCenterInclDelay - rf180CenterInclDelay) /
      system.gradRasterTime
    ) * system.gradRasterTime
  var delayTE2 =
    ceil(
      (TE / 2.0 - calcDuration(rf180, gz180n) + rf180CenterInclDelay - durationToCenter) /
      system.gradRasterTime
    ) * system.gradRasterTime
  assert delayTE1 >= 0
  # Now merge
  delayTE2 = delayTE2 + calcDuration(rf180, gz180n)
  gxPre.trapDelay = 0.0
  gxPre.trapDelay = delayTE2 - calcDuration(gxPre)
  assert gxPre.trapDelay >= calcDuration(rf180)
  gyPre.trapDelay = calcDuration(rf180)
  assert calcDuration(gyPre) <= calcDuration(gxPre)

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  for s in 0 ..< nSlices:
    seqObj.addBlock(rfFs, gzFs)
    rf.rfFreqOffset = gz.trapAmplitude * sliceThickness * (float64(s) - float64(nSlices - 1) / 2.0)
    rf180.rfFreqOffset = gz180.trapAmplitude * sliceThickness * (float64(s) - float64(nSlices - 1) / 2.0)
    seqObj.addBlock(rf, gz, trig)
    seqObj.addBlock(makeDelay(delayTE1))
    seqObj.addBlock(rf180, gz180n, makeDelay(delayTE2), gxPre, gyPre)
    for i in 1 .. NyMeas:
      if i == 1:
        seqObj.addBlock(gx, gyBlipup, adc)
      elif i == NyMeas:
        seqObj.addBlock(gx, gyBlipdown, adc)
      else:
        seqObj.addBlock(gx, gyBlipdownup, adc)
      gx.trapAmplitude = -gx.trapAmplitude

  let (ok, errorReport) = seqObj.checkTiming()
  if ok:
    echo "Timing check passed successfully"
  else:
    echo "Timing check failed. Error listing follows:"
    echo errorReport

  seqObj.setDefinition("FOV", @[fov, fov, sliceThickness])
  seqObj.setDefinition("Name", "epi")
  seqObj.writeSeq("examples/epi_se_rs_nim.seq", createSignature = true)

main()

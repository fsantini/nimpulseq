import std/math
import nimpulseq

proc writeEpiSeSeq*(): Sequence =
  # ======
  # SETUP
  # ======
  let fov = 256e-3
  let Nx = 64
  let Ny = 64

  let system = newOpts(
    maxGrad = 32, gradUnit = "mT/m",
    maxSlew = 130, slewUnit = "T/m/s",
    rfRingdownTime = 20e-6,
    rfDeadTime = 100e-6,
    adcDeadTime = 20e-6,
  )

  var seqObj = newSequence(system)

  # ======
  # CREATE EVENTS
  # ======
  var (rf, gz, _) = makeSincPulse(
    flipAngle = PI / 2.0,
    system = system,
    duration = 3e-3,
    sliceThickness = 3e-3,
    apodization = 0.5,
    timeBwProduct = 4.0,
    returnGz = true,
    delay = system.rfDeadTime,
    use = "excitation",
  )

  let deltaK = 1.0 / fov
  let kWidth = float64(Nx) * deltaK
  let readoutTime = 3.2e-4
  var gx = makeTrapezoid(channel = "x", system = system, flatArea = kWidth, flatTime = readoutTime)
  let adc = makeAdc(numSamples = Nx, system = system, duration = gx.trapFlatTime, delay = gx.trapRiseTime)

  let preTime = 8e-4
  let gzReph = makeTrapezoid(channel = "z", system = system, area = -gz.trapArea / 2.0, duration = preTime)
  let gxPre = makeTrapezoid(channel = "x", system = system, area = gx.trapArea / 2.0 - deltaK / 2.0, duration = preTime)
  let gyPre = makeTrapezoid(channel = "y", system = system, area = float64(Ny) / 2.0 * deltaK, duration = preTime)

  # Phase blip in shortest possible time
  let dur = ceil(2.0 * sqrt(deltaK / system.maxSlew) / 10e-6) * 10e-6
  let gy = makeTrapezoid(channel = "y", system = system, area = deltaK, duration = dur)

  # Refocusing pulse with spoiling gradients
  let rf180 = makeBlockPulse(
    flipAngle = PI,
    delay = system.rfDeadTime,
    system = system,
    duration = 500e-6,
    use = "refocusing",
  )
  let gzSpoil = makeTrapezoid(channel = "z", system = system, area = gz.trapArea * 2.0, duration = 3.0 * preTime)

  # Calculate delay time
  let TE = 60e-3
  let durationToCenter = (float64(Nx) / 2.0 + 0.5) * calcDuration(gx) + float64(Ny) / 2.0 * calcDuration(gy)
  let rfCenterInclDelay = rf.rfDelay + calcRfCenter(rf)[0]
  let rf180CenterInclDelay = rf180.rfDelay + calcRfCenter(rf180)[0]
  let delayTE1 = TE / 2.0 - calcDuration(gz) + rfCenterInclDelay - preTime - calcDuration(gzSpoil) - rf180CenterInclDelay
  let delayTE2 = TE / 2.0 - calcDuration(rf180) + rf180CenterInclDelay - calcDuration(gzSpoil) - durationToCenter

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  seqObj.addBlock(rf, gz)
  seqObj.addBlock(gxPre, gyPre, gzReph)
  seqObj.addBlock(makeDelay(delayTE1))
  seqObj.addBlock(gzSpoil)
  seqObj.addBlock(rf180)
  seqObj.addBlock(gzSpoil)
  seqObj.addBlock(makeDelay(delayTE2))
  for i in 0 ..< Ny:
    seqObj.addBlock(gx, adc)
    seqObj.addBlock(gy)
    gx.trapAmplitude = -gx.trapAmplitude
  seqObj.addBlock(makeDelay(1e-4))

  let (ok, errorReport) = seqObj.checkTiming()
  if ok:
    echo "Timing check passed successfully"
  else:
    echo "Timing check failed! Error listing follows:"
    echo errorReport

  result = seqObj

when isMainModule:
  let seqObj = writeEpiSeSeq()
  seqObj.writeSeq("examples/epi_se_nim.seq", createSignature = true)

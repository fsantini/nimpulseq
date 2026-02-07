import std/math
import ../src/nimpulseq

proc writeEpiSeq*(): Sequence =
  # ======
  # SETUP
  # ======
  let fov = 220e-3
  let Nx = 64
  let Ny = 64
  let sliceThickness = 3e-3
  let nSlices = 3

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
  var (rf, gz, _) = makeSincPulse(
    flipAngle = PI / 2.0,
    system = system,
    duration = 3e-3,
    sliceThickness = sliceThickness,
    apodization = 0.5,
    timeBwProduct = 4.0,
    returnGz = true,
    delay = system.rfDeadTime,
    use = "excitation",
  )

  let deltaK = 1.0 / fov
  let kWidth = float64(Nx) * deltaK
  let dwellTime = 4e-6
  let readoutTime = float64(Nx) * dwellTime
  let flatTime = ceil(readoutTime * 1e5) * 1e-5 # round-up to gradient raster
  var gx = makeTrapezoid(
    channel = "x",
    system = system,
    amplitude = kWidth / readoutTime,
    flatTime = flatTime,
  )
  let adc = makeAdc(
    numSamples = Nx,
    duration = readoutTime,
    delay = gx.trapRiseTime + flatTime / 2.0 - (readoutTime - dwellTime) / 2.0,
  )

  # Pre-phasing gradients
  let preTime = 8e-4
  let gxPre = makeTrapezoid(channel = "x", system = system, area = -gx.trapArea / 2.0, duration = preTime)
  let gzReph = makeTrapezoid(channel = "z", system = system, area = -gz.trapArea / 2.0, duration = preTime)
  let gyPre = makeTrapezoid(channel = "y", system = system, area = -float64(Ny) / 2.0 * deltaK, duration = preTime)

  # Phase blip in shortest possible time
  let dur = ceil(2.0 * sqrt(deltaK / system.maxSlew) / 10e-6) * 10e-6
  let gy = makeTrapezoid(channel = "y", system = system, area = deltaK, duration = dur)

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  for s in 0 ..< nSlices:
    rf.rfFreqOffset = gz.trapAmplitude * sliceThickness * (float64(s) - float64(nSlices - 1) / 2.0)
    seqObj.addBlock(rf, gz)
    seqObj.addBlock(gxPre, gyPre, gzReph)
    for j in 0 ..< Ny:
      seqObj.addBlock(gx, adc)
      seqObj.addBlock(gy)
      gx.trapAmplitude = -gx.trapAmplitude

  let (ok, errorReport) = seqObj.checkTiming()
  if ok:
    echo "Timing check passed successfully"
  else:
    echo "Timing check failed! Error listing follows:"
    for e in errorReport:
      echo e

  result = seqObj

when isMainModule:
  let seqObj = writeEpiSeq()
  seqObj.writeSeq("examples/epi_nim.seq", createSignature = true)

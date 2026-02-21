import std/math
import nimpulseq

proc writeEpiLabelSeq*(): Sequence =
  # ======
  # SETUP
  # ======
  let fov = 220e-3
  let Nx = 64
  let Ny = 64
  let sliceThickness = 3e-3
  let nSlices = 7
  let nReps = 4
  let navigator = 3

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

  let trig = makeTrigger(channel = "physio1", duration = 2000e-6)

  let deltaK = 1.0 / fov
  let kWidth = float64(Nx) * deltaK
  let dwellTime = 4e-6
  let readoutTime = float64(Nx) * dwellTime
  let flatTime = ceil(readoutTime * 1e5) * 1e-5  # Round-up to gradient raster

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

  let preTime = 8e-4
  let gxPre = makeTrapezoid(channel = "x", system = system, area = -gx.trapArea / 2.0, duration = preTime)
  let gzReph = makeTrapezoid(channel = "z", system = system, area = -gz.trapArea / 2.0, duration = preTime)
  let gyPre = makeTrapezoid(channel = "y", system = system, area = float64(Ny) / 2.0 * deltaK, duration = preTime)

  let dur = ceil(2.0 * sqrt(deltaK / system.maxSlew) / 10e-6) * 10e-6
  let gy = makeTrapezoid(channel = "y", system = system, area = -deltaK, duration = dur)

  let gzSpoil = makeTrapezoid(channel = "z", system = system, area = deltaK * float64(Nx) * 4.0)

  # ======
  # CONSTRUCT SEQUENCE
  # ======
  for r in 0 ..< nReps:
    seqObj.addBlock(trig, makeLabel("SET", "SLC", 0))
    for s in 0 ..< nSlices:
      rf.rfFreqOffset = gz.trapAmplitude * sliceThickness * (float64(s) - float64(nSlices - 1) / 2.0)
      rf.rfPhaseOffset = -rf.rfFreqOffset * calcRfCenter(rf)[0]
      seqObj.addBlock(rf, gz)
      seqObj.addBlock(
        gxPre,
        gzReph,
        makeLabel("SET", "NAV", 1),
        makeLabel("SET", "LIN", int(round(float64(Ny) / 2.0))),
      )
      for n in 0 ..< navigator:
        seqObj.addBlock(
          gx,
          adc,
          makeLabel("SET", "REV", int(gx.trapAmplitude < 0)),
          makeLabel("SET", "SEG", int(gx.trapAmplitude < 0)),
          makeLabel("SET", "AVG", int(n + 1 == 3)),
        )
        if n + 1 != navigator:
          seqObj.addBlock(makeDelay(calcDuration(gy)))

        gx.trapAmplitude = -gx.trapAmplitude

      # Reset lin/nav/avg
      seqObj.addBlock(
        gyPre,
        makeLabel("SET", "LIN", 0),
        makeLabel("SET", "NAV", 0),
        makeLabel("SET", "AVG", 0),
      )

      for i in 0 ..< Ny:
        seqObj.addBlock(
          makeLabel("SET", "REV", int(gx.trapAmplitude < 0)),
          makeLabel("SET", "SEG", int(gx.trapAmplitude < 0)),
        )
        seqObj.addBlock(gx, adc)
        seqObj.addBlock(gy, makeLabel("INC", "LIN", 1))
        gx.trapAmplitude = -gx.trapAmplitude

      seqObj.addBlock(
        gzSpoil,
        makeDelay(0.1),
        makeLabel("INC", "SLC", 1),
      )
      if (navigator + Ny) mod 2 != 0:
        gx.trapAmplitude = -gx.trapAmplitude

    seqObj.addBlock(makeLabel("INC", "REP", 1))

  let (ok, errorReport) = seqObj.checkTiming()
  if ok:
    echo "Timing check passed successfully"
  else:
    echo "Timing check failed! Error listing follows:"
    echo errorReport

  result = seqObj

when isMainModule:
  let seqObj = writeEpiLabelSeq()
  seqObj.setDefinition("FOV", @[220e-3, 220e-3, 3e-3 * 7.0])
  seqObj.setDefinition("Name", "epi_lbl")
  seqObj.writeSeq("examples/epi_label_nim.seq", createSignature = true)

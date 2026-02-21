import std/[math, complex]
import types
import make_trap

proc gauss(x: float64): float64 =
  exp(-PI * x * x)

proc makeGaussPulse*(
    flipAngle: float64,
    apodization: float64 = 0.0,
    bandwidth: float64 = 0.0,
    centerPos: float64 = 0.5,
    delay: float64 = 0.0,
    dwell: float64 = 0.0,
    duration: float64 = 4e-3,
    freqOffset: float64 = 0.0,
    maxGrad: float64 = 0.0,
    maxSlew: float64 = 0.0,
    phaseOffset: float64 = 0.0,
    returnGz: bool = false,
    sliceThickness: float64 = 0.0,
    system: Opts = defaultOpts(),
    timeBwProduct: float64 = 4.0,
    use: string = "undefined",
    freqPpm: float64 = 0.0,
    phasePpm: float64 = 0.0,
): tuple[rf: Event, gz: Event, gzr: Event] =
  ## Creates a Gaussian-shaped RF pulse, optionally apodized by a Hanning window.
  ##
  ## - `flipAngle` (rad): desired flip angle.
  ## - `apodization`: Hanning window weight in [0, 1]; 0 = pure Gaussian.
  ## - `bandwidth` (Hz): pulse bandwidth; if 0, derived from `timeBwProduct / duration`.
  ## - `duration` (s): pulse duration (default 4 ms).
  ## - `centerPos`: normalized center position in [0, 1]; default 0.5.
  ## - `dwell` (s): RF sample spacing; defaults to `system.rfRasterTime`.
  ## - `returnGz`: if true, also returns slice-selection (`gz`) and rephasing (`gzr`) trapezoids.
  ##   Requires `sliceThickness` > 0 when enabled.
  ## - `use`: intended use string (see `supportedRfUses`).
  ##
  ## Returns `(rf, gz, gzr)`; `gz` and `gzr` are `nil` when `returnGz = false`.
  ## Raises `ValueError` for unsupported `use` strings or missing `sliceThickness`.
  # Validate use parameter
  var validUse = false
  for u in supportedRfUses:
    if use == u:
      validUse = true
      break
  if not validUse:
    raise newException(ValueError, "Invalid use parameter. Must be one of " & $supportedRfUses)

  var sys = system
  var dw = dwell
  if dw == 0.0:
    dw = sys.rfRasterTime

  var bw = bandwidth
  if bw == 0.0:
    bw = timeBwProduct / duration

  let alpha = apodization
  let nSamples = int(round(duration / dw))

  var t = newSeq[float64](nSamples)
  var tt = newSeq[float64](nSamples)
  for i in 0 ..< nSamples:
    t[i] = (float64(i + 1) - 0.5) * dw
    tt[i] = t[i] - (duration * centerPos)

  var signal = newSeq[float64](nSamples)
  var flip = 0.0
  for i in 0 ..< nSamples:
    let window = 1.0 - alpha + alpha * cos(2.0 * PI * tt[i] / duration)
    signal[i] = window * gauss(bw * tt[i])
    flip += signal[i] * dw * 2.0 * PI

  for i in 0 ..< nSamples:
    signal[i] = signal[i] * flipAngle / flip

  # Fix negative zeros
  for i in 0 ..< nSamples:
    if signal[i] == 0.0 and copySign(1.0, signal[i]) < 0.0:
      signal[i] = 0.0

  # Build complex signal
  var rfSignal = newSeq[Complex64](nSamples)
  for i in 0 ..< nSamples:
    rfSignal[i] = complex64(signal[i], 0.0)

  var rf = Event(kind: ekRf)
  rf.rfSignal = rfSignal
  rf.rfT = t
  rf.rfShapeDur = float64(nSamples) * dw
  rf.rfFreqOffset = freqOffset
  rf.rfPhaseOffset = phaseOffset
  rf.rfFreqPpm = freqPpm
  rf.rfPhasePpm = phasePpm
  rf.rfDeadTime = sys.rfDeadTime
  rf.rfRingdownTime = sys.rfRingdownTime
  rf.rfDelay = delay
  rf.rfCenter = duration * centerPos
  rf.rfUse = use

  if rf.rfDeadTime > rf.rfDelay:
    rf.rfDelay = rf.rfDeadTime

  var gz: Event = nil
  var gzr: Event = nil

  if returnGz:
    if sliceThickness == 0.0:
      raise newException(ValueError, "Slice thickness must be provided")

    if maxGrad > 0:
      sys.maxGrad = maxGrad
    if maxSlew > 0:
      sys.maxSlew = maxSlew

    let amplitude = bw / sliceThickness
    let gzArea = amplitude * duration

    gz = makeTrapezoid(channel = "z", system = sys, flatTime = duration, flatArea = gzArea)

    gzr = makeTrapezoid(
      channel = "z",
      system = sys,
      area = -gzArea * (1.0 - centerPos) - 0.5 * (gz.trapArea - gzArea),
    )

    if rf.rfDelay > gz.trapRiseTime:
      gz.trapDelay = ceil((rf.rfDelay - gz.trapRiseTime) / sys.gradRasterTime) * sys.gradRasterTime

    if rf.rfDelay < (gz.trapRiseTime + gz.trapDelay):
      rf.rfDelay = gz.trapRiseTime + gz.trapDelay

  result = (rf, gz, gzr)

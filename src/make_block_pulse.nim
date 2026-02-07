import std/[math, complex]
import types
import calc_rf_center

proc makeBlockPulse*(
    flipAngle: float64,
    delay: float64 = 0.0,
    duration: float64 = 0.0,
    bandwidth: float64 = 0.0,
    timeBwProduct: float64 = 0.0,
    freqOffset: float64 = 0.0,
    phaseOffset: float64 = 0.0,
    system: Opts = defaultOpts(),
    use: string = "undefined",
    freqPpm: float64 = 0.0,
    phasePpm: float64 = 0.0,
): Event =
  # Validate use parameter
  var validUse = false
  for u in supportedRfUses:
    if use == u:
      validUse = true
      break
  if not validUse:
    raise newException(ValueError, "Invalid use parameter. Must be one of " & $supportedRfUses)

  var dur = duration
  if dur == 0.0 and bandwidth == 0.0:
    dur = 4e-3
  elif dur > 0.0 and bandwidth > 0.0:
    raise newException(ValueError, "One of bandwidth or duration must be defined, but not both.")
  elif dur > 0.0:
    discard # Use specified duration
  elif bandwidth > 0.0:
    if timeBwProduct > 0.0:
      dur = timeBwProduct / bandwidth
    else:
      dur = 1.0 / (4.0 * bandwidth)
  else:
    raise newException(ValueError, "One of bandwidth or duration must be defined and be > 0.")

  let nSamples = int(round(dur / system.rfRasterTime))
  let t = @[0.0, float64(nSamples) * system.rfRasterTime]
  let amp = flipAngle / (2.0 * PI) / dur
  let signal = @[complex64(amp, 0.0), complex64(amp, 0.0)]

  result = Event(kind: ekRf)
  result.rfSignal = signal
  result.rfT = t
  result.rfShapeDur = t[^1]
  result.rfFreqOffset = freqOffset
  result.rfPhaseOffset = phaseOffset
  result.rfFreqPpm = freqPpm
  result.rfPhasePpm = phasePpm
  result.rfDeadTime = system.rfDeadTime
  result.rfRingdownTime = system.rfRingdownTime
  result.rfDelay = delay
  result.rfCenter = result.rfShapeDur / 2.0
  result.rfUse = use

  if result.rfDeadTime > result.rfDelay:
    result.rfDelay = result.rfDeadTime

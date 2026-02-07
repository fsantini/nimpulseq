import std/math
import types

proc calculateShortestParamsForArea(area, maxSlew, maxGrad, gradRasterTime: float64):
    tuple[amplitude, riseTime, flatTime, fallTime: float64] =
  var riseTime = ceil(sqrt(abs(area) / maxSlew) / gradRasterTime) * gradRasterTime
  riseTime = max(riseTime, gradRasterTime)

  var amplitude = area / riseTime
  var effectiveTime = riseTime

  if abs(amplitude) > maxGrad + eps:
    effectiveTime = ceil(abs(area) / maxGrad / gradRasterTime) * gradRasterTime
    amplitude = area / effectiveTime
    riseTime = ceil(abs(amplitude) / maxSlew / gradRasterTime) * gradRasterTime
    riseTime = max(riseTime, gradRasterTime)

  let flatTime = effectiveTime - riseTime
  let fallTime = riseTime

  (amplitude, riseTime, flatTime, fallTime)

proc calculateShortestRiseTime(amplitude, maxSlew, gradRasterTime: float64): float64 =
  ceil(max(abs(amplitude) / maxSlew, gradRasterTime) / gradRasterTime) * gradRasterTime

proc makeTrapezoid*(
    channel: string,
    amplitude: float64 = NaN,
    area: float64 = NaN,
    delay: float64 = 0.0,
    duration: float64 = NaN,
    fallTime: float64 = NaN,
    flatArea: float64 = NaN,
    flatTime: float64 = NaN,
    maxGrad: float64 = 0.0,
    maxSlew: float64 = 0.0,
    riseTime: float64 = NaN,
    system: Opts = defaultOpts(),
): Event =
  let ch = parseChannel(channel)
  let mg = if maxGrad > 0: maxGrad else: system.maxGrad
  let ms = if maxSlew > 0: maxSlew else: system.maxSlew

  # If either of rise_time or fall_time is not provided, set it to the other
  var rt = riseTime
  var ft = fallTime
  if rt.isNaN and not ft.isNaN:
    rt = ft
  elif not rt.isNaN and ft.isNaN:
    ft = rt

  # Determine calculation path
  let hasArea = not area.isNaN
  let hasFlatArea = not flatArea.isNaN
  let hasAmplitude = not amplitude.isNaN

  type CalcPath = enum cpArea, cpFlatArea, cpAmplitude

  var calcPath: CalcPath
  if hasArea and not hasFlatArea and not hasAmplitude:
    calcPath = cpArea
  elif not hasArea and hasFlatArea and not hasAmplitude:
    calcPath = cpFlatArea
  elif not hasArea and not hasFlatArea and hasAmplitude:
    calcPath = cpAmplitude
  else:
    raise newException(ValueError, "Must supply either 'area', 'flat_area' or 'amplitude'.")

  var amp2: float64
  var rtFinal = rt
  var ftFinal = ft
  var flatTimeFinal = flatTime

  case calcPath
  of cpArea:
    if not duration.isNaN and flatTime.isNaN:
      if rt.isNaN:
        let (_, shortRt, shortFt, shortFall) = calculateShortestParamsForArea(area, ms, mg, system.gradRasterTime)
        rtFinal = shortRt
        flatTimeFinal = shortFt
        ftFinal = shortFall
        let minDuration = shortRt + shortFt + shortFall
        assert duration >= minDuration, "Requested area is too large for this gradient."

        let dc = 1.0 / abs(2.0 * ms) + 1.0 / abs(2.0 * ms)
        amp2 = (duration - sqrt(duration * duration - 4.0 * abs(area) * dc)) / (2.0 * dc)
      else:
        if ftFinal.isNaN:
          ftFinal = rtFinal
        amp2 = area / (duration - 0.5 * rtFinal - 0.5 * ftFinal)
      flatTimeFinal = duration - rtFinal - ftFinal
      amp2 = area / (rtFinal / 2.0 + ftFinal / 2.0 + flatTimeFinal)
    elif not flatTime.isNaN:
      if rt.isNaN:
        raise newException(ValueError, "Must supply rise_time when area and flat_time is provided.")
      amp2 = area / (rtFinal + flatTimeFinal)
    else:
      let (a, r, f, fa) = calculateShortestParamsForArea(area, ms, mg, system.gradRasterTime)
      amp2 = a
      rtFinal = r
      flatTimeFinal = f
      ftFinal = fa
  of cpFlatArea:
    if not flatTime.isNaN:
      amp2 = flatArea / flatTimeFinal
    else:
      raise newException(ValueError, "flat_time required with flat_area.")
  of cpAmplitude:
    if rt.isNaN:
      rtFinal = abs(amplitude) / ms
      rtFinal = ceil(rtFinal / system.gradRasterTime) * system.gradRasterTime
      if rtFinal == 0:
        rtFinal = system.gradRasterTime
      ftFinal = rtFinal
    amp2 = amplitude
    if not duration.isNaN and flatTime.isNaN:
      flatTimeFinal = duration - rtFinal - ftFinal
    elif not flatTime.isNaN and duration.isNaN:
      discard
    else:
      raise newException(ValueError, "Must supply area or duration.")

  if rtFinal.isNaN and ftFinal.isNaN:
    rtFinal = calculateShortestRiseTime(amp2, ms, system.gradRasterTime)
    ftFinal = rtFinal

  if abs(amp2) > mg + eps:
    raise newException(ValueError, "Amplitude violation.")

  result = Event(kind: ekTrap)
  result.trapChannel = ch
  result.trapAmplitude = amp2
  result.trapRiseTime = rtFinal
  result.trapFlatTime = flatTimeFinal
  result.trapFallTime = ftFinal
  result.trapArea = amp2 * (flatTimeFinal + rtFinal / 2.0 + ftFinal / 2.0)
  result.trapFlatArea = amp2 * flatTimeFinal
  result.trapDelay = delay
  result.trapFirst = 0.0
  result.trapLast = 0.0

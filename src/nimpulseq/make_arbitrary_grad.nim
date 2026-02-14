import std/math
import types

proc makeArbitraryGrad*(
    channel: string,
    waveform: seq[float64],
    first: float64 = NaN,
    last: float64 = NaN,
    delay: float64 = 0.0,
    maxGrad: float64 = 0.0,
    maxSlew: float64 = 0.0,
    system: Opts = defaultOpts(),
    oversampling: bool = false,
): Event =
  ## Creates a gradient event from an arbitrary waveform.
  let ch = parseChannel(channel)
  let mg = if maxGrad > 0: maxGrad else: system.maxGrad
  let ms = if maxSlew > 0: maxSlew else: system.maxSlew

  # Calculate first/last by extrapolation if not provided
  var f = first
  var l = last
  if f.isNaN or l.isNaN:
    if oversampling:
      if f.isNaN:
        f = 2.0 * waveform[0] - waveform[1]
      if l.isNaN:
        l = 2.0 * waveform[^1] - waveform[^2]
    else:
      if f.isNaN:
        f = 0.5 * (3.0 * waveform[0] - waveform[1])
      if l.isNaN:
        l = 0.5 * (3.0 * waveform[^1] - waveform[^2])

  result = Event(kind: ekGrad)
  result.gradChannel = ch
  result.gradWaveform = waveform
  result.gradDelay = delay
  result.gradFirst = f
  result.gradLast = l

  if oversampling:
    # Calculate area from every other sample
    var area = 0.0
    var i = 0
    while i < waveform.len:
      area += waveform[i] * system.gradRasterTime
      i += 2
    result.gradAmplitude = 0.0
    for w in waveform:
      if abs(w) > abs(result.gradAmplitude):
        result.gradAmplitude = w

    var tt = newSeq[float64](waveform.len)
    for i in 0 ..< waveform.len:
      tt[i] = float64(i + 1) * 0.5 * system.gradRasterTime
    result.gradTt = tt
    result.gradShapeDur = float64(waveform.len + 1) * 0.5 * system.gradRasterTime
  else:
    var area = 0.0
    for w in waveform:
      area += w * system.gradRasterTime
    result.gradAmplitude = 0.0
    for w in waveform:
      if abs(w) > abs(result.gradAmplitude):
        result.gradAmplitude = w

    var tt = newSeq[float64](waveform.len)
    for i in 0 ..< waveform.len:
      tt[i] = (float64(i) + 0.5) * system.gradRasterTime
    result.gradTt = tt
    result.gradShapeDur = float64(waveform.len) * system.gradRasterTime

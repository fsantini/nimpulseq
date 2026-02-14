import std/math
import types
import make_extended_trapezoid

proc splitGradientAt*(
    grad: Event,
    timePoint: float64,
    system: Opts = defaultOpts(),
): tuple[grad1: Event, grad2: Event] =
  ## Split a trapezoidal gradient into two extended trapezoids at the given time point.
  let gradRasterTime = system.gradRasterTime
  let timeIndex = int(round(timePoint / gradRasterTime))
  # Work around floating-point arithmetic limitation
  var tp = round(float64(timeIndex) * gradRasterTime * 1e6) / 1e6
  var channel: string

  var times: seq[float64]
  var amplitudes: seq[float64]
  var gradDelay: float64

  if grad.kind == ekTrap:
    channel = $grad.trapChannel
    let rt = round(grad.trapRiseTime / gradRasterTime) * gradRasterTime
    let ft = round(grad.trapFlatTime / gradRasterTime) * gradRasterTime
    let flt = round(grad.trapFallTime / gradRasterTime) * gradRasterTime
    gradDelay = round(grad.trapDelay / gradRasterTime) * gradRasterTime

    if ft == 0:
      times = @[0.0, rt, rt + flt]
      amplitudes = @[0.0, grad.trapAmplitude, 0.0]
    else:
      times = @[0.0, rt, rt + ft, rt + ft + flt]
      amplitudes = @[0.0, grad.trapAmplitude, grad.trapAmplitude, 0.0]
  elif grad.kind == ekGrad:
    channel = $grad.gradChannel
    times = grad.gradTt
    amplitudes = grad.gradWaveform
    gradDelay = grad.gradDelay
  else:
    raise newException(ValueError, "Splitting of unsupported event.")

  # If the split line is behind the gradient, there is nothing to do
  if tp >= gradDelay + times[^1]:
    raise newException(ValueError, "Splitting of gradient at time point after the end of gradient.")

  # If the split line goes through the delay
  if tp < gradDelay:
    var newTimes = @[0.0]
    for t in times:
      newTimes.add(gradDelay + t)
    times = newTimes
    var newAmps = @[0.0]
    for a in amplitudes:
      newAmps.add(a)
    amplitudes = newAmps
    gradDelay = 0.0
  else:
    tp -= gradDelay

  # Round times to avoid floating-point issues
  for i in 0 ..< times.len:
    times[i] = round(times[i] * 1e6) / 1e6

  # Sample at time point using linear interpolation
  var ampTp: float64
  # Find the two surrounding points
  if tp <= times[0]:
    ampTp = amplitudes[0]
  elif tp >= times[^1]:
    ampTp = amplitudes[^1]
  else:
    for i in 0 ..< times.len - 1:
      if tp >= times[i] and tp <= times[i + 1]:
        let t0 = times[i]
        let t1 = times[i + 1]
        let a0 = amplitudes[i]
        let a1 = amplitudes[i + 1]
        if t1 == t0:
          ampTp = a0
        else:
          ampTp = a0 + (a1 - a0) * (tp - t0) / (t1 - t0)
        break

  let tEps = 1e-10

  # Build times1/amplitudes1 (before time point)
  var times1: seq[float64] = @[]
  var amplitudes1: seq[float64] = @[]
  for i in 0 ..< times.len:
    if times[i] < tp - tEps:
      times1.add(times[i])
      amplitudes1.add(amplitudes[i])
  times1.add(tp)
  amplitudes1.add(ampTp)

  # Build times2/amplitudes2 (after time point)
  var times2: seq[float64] = @[0.0]
  var amplitudes2: seq[float64] = @[ampTp]
  for i in 0 ..< times.len:
    if times[i] > tp + tEps:
      times2.add(times[i] - tp)
      amplitudes2.add(amplitudes[i])

  let grad1 = makeExtendedTrapezoid(
    channel = channel,
    times = times1,
    amplitudes = amplitudes1,
    skipCheck = true,
    system = system,
  )
  grad1.gradDelay = gradDelay

  let grad2 = makeExtendedTrapezoid(
    channel = channel,
    times = times2,
    amplitudes = amplitudes2,
    skipCheck = true,
    system = system,
  )
  grad2.gradDelay = tp

  result = (grad1, grad2)

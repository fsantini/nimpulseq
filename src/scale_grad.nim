import std/math
import types

proc scaleGrad*(grad: Event, scale: float64, system: Opts = defaultOpts()): Event =
  ## Scale a gradient event by a scalar factor. Returns a new event.
  if grad.kind == ekTrap:
    result = Event(kind: ekTrap)
    result.trapChannel = grad.trapChannel
    result.trapAmplitude = grad.trapAmplitude * scale
    result.trapRiseTime = grad.trapRiseTime
    result.trapFlatTime = grad.trapFlatTime
    result.trapFallTime = grad.trapFallTime
    result.trapArea = grad.trapArea * scale
    result.trapFlatArea = grad.trapFlatArea * scale
    result.trapDelay = grad.trapDelay
    result.trapFirst = grad.trapFirst
    result.trapLast = grad.trapLast
  elif grad.kind == ekGrad:
    result = Event(kind: ekGrad)
    result.gradChannel = grad.gradChannel
    result.gradAmplitude = grad.gradAmplitude * scale
    var wf = newSeq[float64](grad.gradWaveform.len)
    for i in 0 ..< wf.len:
      wf[i] = grad.gradWaveform[i] * scale
    result.gradWaveform = wf
    var tt = newSeq[float64](grad.gradTt.len)
    for i in 0 ..< tt.len:
      tt[i] = grad.gradTt[i]
    result.gradTt = tt
    result.gradDelay = grad.gradDelay
    result.gradShapeDur = grad.gradShapeDur
    result.gradFirst = grad.gradFirst * scale
    result.gradLast = grad.gradLast * scale
  else:
    raise newException(ValueError, "scaleGrad: unsupported event type")

import types

proc calcDuration*(events: varargs[Event]): float64 =
  ## Returns the duration of a group of simultaneously-played events (s).
  ## The result is the maximum end time across all supplied events,
  ## including any configured delays, dead times, and ringdown times stored on each event.
  result = 0.0
  for event in events:
    case event.kind
    of ekDelay:
      result = max(result, event.delayD)
    of ekRf:
      result = max(result, event.rfDelay + event.rfShapeDur + event.rfRingdownTime)
    of ekGrad:
      result = max(result, event.gradDelay + event.gradShapeDur)
    of ekAdc:
      result = max(result, event.adcDelay + float64(event.adcNumSamples) * event.adcDwell + event.adcDeadTime)
    of ekTrap:
      result = max(result, event.trapDelay + event.trapRiseTime + event.trapFlatTime + event.trapFallTime)
    of ekTrigger, ekOutput:
      result = max(result, event.trigDelay + event.trigDuration)
    of ekLabelSet, ekLabelInc:
      discard # Labels have zero duration
    of ekSoftDelay:
      result = max(result, event.sdDefaultDuration)

import std/math
import types
import calc_duration

type
  AlignSpec* = enum
    asLeft, asCenter, asRight

proc alignEvents*(spec: AlignSpec, events: seq[Event]): seq[Event] =
  ## Align events according to spec by setting delays.
  ## Returns new events with adjusted delays.
  var dur = 0.0
  for e in events:
    dur = max(dur, calcDuration(e))

  result = @[]
  for e in events:
    # Create a shallow copy by creating a new event with the same kind
    var newE: Event
    case e.kind
    of ekTrap:
      newE = Event(kind: ekTrap)
      newE.trapChannel = e.trapChannel
      newE.trapAmplitude = e.trapAmplitude
      newE.trapRiseTime = e.trapRiseTime
      newE.trapFlatTime = e.trapFlatTime
      newE.trapFallTime = e.trapFallTime
      newE.trapArea = e.trapArea
      newE.trapFlatArea = e.trapFlatArea
      newE.trapDelay = e.trapDelay
      newE.trapFirst = e.trapFirst
      newE.trapLast = e.trapLast
    of ekGrad:
      newE = Event(kind: ekGrad)
      newE.gradChannel = e.gradChannel
      newE.gradAmplitude = e.gradAmplitude
      newE.gradWaveform = e.gradWaveform
      newE.gradTt = e.gradTt
      newE.gradDelay = e.gradDelay
      newE.gradShapeDur = e.gradShapeDur
      newE.gradFirst = e.gradFirst
      newE.gradLast = e.gradLast
    of ekRf:
      newE = Event(kind: ekRf)
      newE.rfSignal = e.rfSignal
      newE.rfT = e.rfT
      newE.rfShapeDur = e.rfShapeDur
      newE.rfFreqOffset = e.rfFreqOffset
      newE.rfPhaseOffset = e.rfPhaseOffset
      newE.rfFreqPpm = e.rfFreqPpm
      newE.rfPhasePpm = e.rfPhasePpm
      newE.rfDeadTime = e.rfDeadTime
      newE.rfRingdownTime = e.rfRingdownTime
      newE.rfDelay = e.rfDelay
      newE.rfCenter = e.rfCenter
      newE.rfUse = e.rfUse
    of ekAdc:
      newE = Event(kind: ekAdc)
      newE.adcNumSamples = e.adcNumSamples
      newE.adcDwell = e.adcDwell
      newE.adcDelay = e.adcDelay
      newE.adcFreqOffset = e.adcFreqOffset
      newE.adcPhaseOffset = e.adcPhaseOffset
      newE.adcFreqPpm = e.adcFreqPpm
      newE.adcPhasePpm = e.adcPhasePpm
      newE.adcDeadTime = e.adcDeadTime
      newE.adcDuration = e.adcDuration
    of ekDelay:
      newE = Event(kind: ekDelay)
      newE.delayD = e.delayD
    else:
      newE = e

    case spec
    of asLeft:
      case newE.kind
      of ekTrap: newE.trapDelay = 0.0
      of ekGrad: newE.gradDelay = 0.0
      of ekRf: newE.rfDelay = 0.0
      of ekAdc: newE.adcDelay = 0.0
      else: discard
    of asCenter:
      let eDur = calcDuration(e)
      let delta = (dur - eDur) / 2.0
      case newE.kind
      of ekTrap: newE.trapDelay = delta
      of ekGrad: newE.gradDelay = delta
      of ekRf: newE.rfDelay = delta
      of ekAdc: newE.adcDelay = delta
      else: discard
    of asRight:
      let eDur = calcDuration(e)
      case newE.kind
      of ekTrap: newE.trapDelay = dur - eDur + e.trapDelay
      of ekGrad: newE.gradDelay = dur - eDur + e.gradDelay
      of ekRf: newE.rfDelay = dur - eDur + e.rfDelay
      of ekAdc: newE.adcDelay = dur - eDur + e.adcDelay
      else: discard

    result.add(newE)

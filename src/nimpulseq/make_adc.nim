import types

proc makeAdc*(
    numSamples: int,
    delay: float64 = 0.0,
    duration: float64 = 0.0,
    dwell: float64 = 0.0,
    freqOffset: float64 = 0.0,
    phaseOffset: float64 = 0.0,
    system: Opts = defaultOpts(),
    freqPpm: float64 = 0.0,
    phasePpm: float64 = 0.0,
): Event =
  ## Creates an ADC (analog-to-digital converter) readout event.
  ##
  ## Exactly one of `dwell` or `duration` must be non-zero:
  ## - `dwell` (s): sample spacing; `duration` is computed as `dwell * numSamples`.
  ## - `duration` (s): total readout window; `dwell` is computed as `duration / numSamples`.
  ##
  ## The effective delay is raised to at least `system.adcDeadTime`.
  ## `freqOffset` (Hz) and `phaseOffset` (rad) shift the demodulation frequency/phase.
  ## Raises `ValueError` if both or neither of `dwell`/`duration` are specified.
  if (dwell == 0.0 and duration == 0.0) or (dwell > 0.0 and duration > 0.0):
    raise newException(ValueError, "Either dwell or duration must be defined")

  result = Event(kind: ekAdc)
  result.adcNumSamples = numSamples
  result.adcDwell = dwell
  result.adcDelay = delay
  result.adcFreqOffset = freqOffset
  result.adcPhaseOffset = phaseOffset
  result.adcFreqPpm = freqPpm
  result.adcPhasePpm = phasePpm
  result.adcDeadTime = system.adcDeadTime

  if duration > 0.0:
    result.adcDwell = duration / float64(numSamples)

  if dwell > 0.0:
    result.adcDuration = dwell * float64(numSamples)

  if result.adcDeadTime > result.adcDelay:
    result.adcDelay = result.adcDeadTime

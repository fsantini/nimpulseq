import types

proc makeTrigger*(
    channel: string,
    delay: float64 = 0.0,
    duration: float64 = 0.0,
    system: Opts = defaultOpts(),
): Event =
  ## Create a trigger halt event for synchronization with an external signal.
  ## Possible channels: 'physio1', 'physio2'.
  if channel notin ["physio1", "physio2"]:
    raise newException(ValueError, "Channel " & channel & " is invalid. Must be 'physio1' or 'physio2'.")

  result = Event(kind: ekTrigger)
  result.trigChannel = channel
  result.trigDelay = delay
  result.trigDuration = duration
  if result.trigDuration <= system.gradRasterTime:
    result.trigDuration = system.gradRasterTime

proc makeDigitalOutputPulse*(
    channel: string,
    delay: float64 = 0.0,
    duration: float64 = 4e-3,
    system: Opts = defaultOpts(),
): Event =
  ## Create a digital output pulse (trigger) event.
  ## Possible channels: 'osc0', 'osc1', 'ext1'.
  if channel notin ["osc0", "osc1", "ext1"]:
    raise newException(ValueError, "Channel " & channel & " is invalid. Must be 'osc0', 'osc1', or 'ext1'.")

  result = Event(kind: ekOutput)
  result.trigChannel = channel
  result.trigDelay = delay
  result.trigDuration = duration
  if result.trigDuration <= system.gradRasterTime:
    result.trigDuration = system.gradRasterTime

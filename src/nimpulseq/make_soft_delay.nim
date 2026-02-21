import types

proc makeSoftDelay*(hint: string; numID: int = -1; offset: float64 = 0.0;
                    factor: float64 = 1.0; defaultDuration: float64 = 10e-6): Event =
  ## Creates a soft-delay extension event for dynamic block-duration adjustment.
  ##
  ## Soft delays enable runtime modification of block durations through the scanner
  ## interface without recompiling the sequence.  They must be placed in blocks that
  ## contain no RF, gradient, or ADC events.  The final block duration is calculated
  ## as: ``duration = (user_input / factor) + offset``.
  ##
  ## - ``hint``: label shown in the scanner interface; must not contain whitespace.
  ## - ``numID``: numeric ID; -1 (default) auto-assigns one based on insertion order.
  ## - ``offset``: additive time offset in seconds (may be negative).
  ## - ``factor``: scale applied to the user input (must not be zero).
  ## - ``defaultDuration``: initial block duration used before ``applySoftDelay`` is called.
  if hint.len == 0:
    raise newException(ValueError, "Parameter 'hint' cannot be empty.")
  for c in hint:
    if c in {' ', '\t', '\n', '\r'}:
      raise newException(ValueError, "Parameter 'hint' may not contain whitespace characters.")
  if defaultDuration <= 0.0:
    raise newException(ValueError, "Default duration must be greater than 0.")
  if factor == 0.0:
    raise newException(ValueError, "Parameter 'factor' cannot be zero.")
  if numID < -1:
    raise newException(ValueError, "Parameter 'numID' must be a non-negative integer or -1 for auto-assign.")

  result = Event(kind: ekSoftDelay,
    sdHint: hint,
    sdNumID: numID,
    sdOffset: offset,
    sdFactor: factor,
    sdDefaultDuration: defaultDuration,
  )

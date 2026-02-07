import std/math
import types

proc makeDelay*(d: float64): Event =
  if not d.isNaN and (classify(d) in {fcInf, fcNegInf, fcNan} or d < 0.0):
    raise newException(ValueError, "Delay is invalid")
  result = Event(kind: ekDelay)
  result.delayD = d

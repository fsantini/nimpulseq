import std/math
import types

proc makeExtendedTrapezoid*(
    channel: string,
    amplitudes: seq[float64] = @[],
    times: seq[float64] = @[],
    skipCheck: bool = false,
    system: Opts = defaultOpts(),
): Event =
  ## Create a gradient by specifying amplitude points at given times.
  ## Returns an arbitrary gradient object (ekGrad).
  let ch = parseChannel(channel)

  if times.len != amplitudes.len:
    raise newException(ValueError, "Times and amplitudes must have the same length.")

  var allZero = true
  for t in times:
    if t != 0.0:
      allZero = false
      break
  if allZero:
    raise newException(ValueError, "At least one of the given times must be non-zero")

  for i in 1 ..< times.len:
    if times[i] <= times[i - 1]:
      raise newException(ValueError, "Times must be in ascending order and all times must be distinct")

  if abs(round(times[^1] / system.gradRasterTime) * system.gradRasterTime - times[^1]) > eps:
    raise newException(ValueError, "The last time point must be on a gradient raster")

  if not skipCheck and times[0] > 0 and amplitudes[0] != 0:
    raise newException(ValueError, "If first amplitude of a gradient is non-zero, it must connect to previous block")

  # Check all time points are on gradient raster
  for i in 0 ..< times.len:
    if abs(round(times[i] / system.gradRasterTime) * system.gradRasterTime - times[i]) > eps:
      raise newException(ValueError, "All time points must be on a gradient raster.")

  result = Event(kind: ekGrad)
  result.gradChannel = ch

  # Copy waveform (amplitudes)
  result.gradWaveform = amplitudes

  # Calculate delay and tt
  result.gradDelay = round(times[0] / system.gradRasterTime) * system.gradRasterTime
  var tt = newSeq[float64](times.len)
  for i in 0 ..< times.len:
    tt[i] = times[i] - result.gradDelay
  result.gradTt = tt
  result.gradShapeDur = tt[^1]

  # Calculate area using trapezoidal integration
  var area = 0.0
  for i in 0 ..< tt.len - 1:
    area += 0.5 * (tt[i + 1] - tt[i]) * (amplitudes[i + 1] + amplitudes[i])

  # Calculate amplitude (max abs)
  var maxAmp = 0.0
  for a in amplitudes:
    if abs(a) > maxAmp:
      maxAmp = abs(a)
  result.gradAmplitude = maxAmp

  result.gradFirst = amplitudes[0]
  result.gradLast = amplitudes[^1]

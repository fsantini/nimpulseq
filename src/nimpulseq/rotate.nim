import std/math
import types
import scale_grad
import add_gradients

proc getGradAbsMag(grad: Event): float64 =
  if grad.kind == ekTrap:
    return abs(grad.trapAmplitude)
  elif grad.kind == ekGrad:
    result = 0.0
    for w in grad.gradWaveform:
      result = max(result, abs(w))
  else:
    return 0.0

proc rotate*(
    events: seq[Event],
    angle: float64,
    axis: string,
    system: Opts = defaultOpts(),
): seq[Event] =
  ## Rotates gradients about the given axis by the specified angle.
  ## Gradients parallel to the rotation axis and non-gradients are not affected.
  var axes = @["x", "y", "z"]

  # Remove the rotation axis
  var axesToRotate: seq[string] = @[]
  for a in axes:
    if a != axis:
      axesToRotate.add(a)
  if axesToRotate.len != 2:
    raise newException(ValueError, "Incorrect axes specification.")

  # Classify events
  var iRotate1: seq[int] = @[]
  var iRotate2: seq[int] = @[]
  var iBypass: seq[int] = @[]

  for i in 0 ..< events.len:
    let e = events[i]
    var isGrad = e.kind == ekTrap or e.kind == ekGrad
    var ch: string
    if isGrad:
      if e.kind == ekTrap:
        ch = $e.trapChannel
      else:
        ch = $e.gradChannel

    if not isGrad or ch == axis:
      iBypass.add(i)
    elif ch == axesToRotate[0]:
      iRotate1.add(i)
    elif ch == axesToRotate[1]:
      iRotate2.add(i)
    else:
      iBypass.add(i)

  # Rotate
  var rotated1: seq[Event] = @[]
  var rotated2: seq[Event] = @[]
  var maxMag = 0.0

  for i in iRotate1:
    let g = events[i]
    maxMag = max(maxMag, getGradAbsMag(g))
    rotated1.add(scaleGrad(g, cos(angle)))
    var gSin = scaleGrad(g, sin(angle))
    # Change channel
    if gSin.kind == ekTrap:
      gSin.trapChannel = parseChannel(axesToRotate[1])
    else:
      gSin.gradChannel = parseChannel(axesToRotate[1])
    rotated2.add(gSin)

  for i in iRotate2:
    let g = events[i]
    maxMag = max(maxMag, getGradAbsMag(g))
    rotated2.add(scaleGrad(g, cos(angle)))
    var gSin = scaleGrad(g, -sin(angle))
    # Change channel
    if gSin.kind == ekTrap:
      gSin.trapChannel = parseChannel(axesToRotate[0])
    else:
      gSin.gradChannel = parseChannel(axesToRotate[0])
    rotated1.add(gSin)

  # Eliminate zero-amplitude gradients
  let threshold = 1e-6 * maxMag
  var filtered1: seq[Event] = @[]
  for g in rotated1:
    if getGradAbsMag(g) >= threshold:
      filtered1.add(g)
  var filtered2: seq[Event] = @[]
  for g in rotated2:
    if getGradAbsMag(g) >= threshold:
      filtered2.add(g)

  # Add gradients on corresponding axis
  var combined: seq[Event] = @[]
  if filtered1.len > 0:
    combined.add(addGradients(filtered1, system))
  if filtered2.len > 0:
    combined.add(addGradients(filtered2, system))

  # Eliminate zero amplitude combined gradients
  var finalCombined: seq[Event] = @[]
  for g in combined:
    if getGradAbsMag(g) >= threshold:
      finalCombined.add(g)

  # Build result: bypass events + rotated gradients
  result = @[]
  for i in iBypass:
    result.add(events[i])
  for g in finalCombined:
    result.add(g)

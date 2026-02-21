import std/[math, algorithm]
import types
import make_trap
import make_extended_trapezoid

proc cumsum4*(a, b, c, d: float64): tuple[s0, s1, s2, s3: float64] =
  let s1 = a + b
  let s2 = s1 + c
  (a, s1, s2, s2 + d)

proc cumsum3*(a, b, c: float64): tuple[s0, s1, s2: float64] =
  let s1 = a + b
  (a, s1, s1 + c)

proc addGradients*(
    grads: seq[Event],
    system: Opts = defaultOpts(),
    maxGrad: float64 = 0.0,
    maxSlew: float64 = 0.0,
): Event =
  ## Returns the superposition of several gradients.
  let mg = if maxGrad > 0: maxGrad else: system.maxGrad
  let ms = if maxSlew > 0: maxSlew else: system.maxSlew

  if grads.len == 0:
    raise newException(ValueError, "No gradients specified")

  if grads.len == 1:
    # Return a copy
    let g = grads[0]
    if g.kind == ekTrap:
      result = Event(kind: ekTrap)
      result.trapChannel = g.trapChannel
      result.trapAmplitude = g.trapAmplitude
      result.trapRiseTime = g.trapRiseTime
      result.trapFlatTime = g.trapFlatTime
      result.trapFallTime = g.trapFallTime
      result.trapArea = g.trapArea
      result.trapFlatArea = g.trapFlatArea
      result.trapDelay = g.trapDelay
      result.trapFirst = g.trapFirst
      result.trapLast = g.trapLast
    else:
      result = Event(kind: ekGrad)
      result.gradChannel = g.gradChannel
      result.gradAmplitude = g.gradAmplitude
      result.gradWaveform = g.gradWaveform
      result.gradTt = g.gradTt
      result.gradDelay = g.gradDelay
      result.gradShapeDur = g.gradShapeDur
      result.gradFirst = g.gradFirst
      result.gradLast = g.gradLast
    return

  # First gradient defines channel
  var channel: string
  if grads[0].kind == ekTrap:
    channel = $grads[0].trapChannel
  else:
    channel = $grads[0].gradChannel

  # Check if we have a set of traps with the same timing
  var allTrap = true
  for g in grads:
    if g.kind != ekTrap:
      allTrap = false
      break

  if allTrap:
    var sameTiming = true
    let g0 = grads[0]
    for i in 1 ..< grads.len:
      let g = grads[i]
      if g.trapRiseTime != g0.trapRiseTime or g.trapFlatTime != g0.trapFlatTime or
         g.trapFallTime != g0.trapFallTime or g.trapDelay != g0.trapDelay:
        sameTiming = false
        break

    if sameTiming:
      var ampSum = eps
      for g in grads:
        ampSum += g.trapAmplitude
      return makeTrapezoid(
        channel = channel,
        amplitude = ampSum,
        riseTime = g0.trapRiseTime,
        flatTime = g0.trapFlatTime,
        fallTime = g0.trapFallTime,
        delay = g0.trapDelay,
        system = system,
      )

  # General case: convert all to extended trapezoid representation and interpolate
  var allIsTrap = true
  var allIsEtrap = true
  for g in grads:
    if g.kind == ekTrap:
      allIsEtrap = false
    elif g.kind == ekGrad:
      allIsTrap = false
      # Check if it's on the regular grid
      var isRegular = true
      for j in 0 ..< g.gradTt.len:
        let expected = (float64(j) + 0.5) * system.gradRasterTime
        if abs(g.gradTt[j] - expected) > eps:
          isRegular = false
          break
      if isRegular:
        allIsEtrap = false
    else:
      raise newException(ValueError, "Unknown gradient type in addGradients")

  if true:
    # Collect all time points (handles traps, extended traps, and mixed)
    var timeSet: seq[float64] = @[]
    for g in grads:
      if g.kind == ekTrap:
        let (s0, s1, s2, s3) = cumsum4(g.trapDelay, g.trapRiseTime, g.trapFlatTime, g.trapFallTime)
        timeSet.add(s0)
        timeSet.add(s1)
        timeSet.add(s2)
        timeSet.add(s3)
      else:
        for t in g.gradTt:
          timeSet.add(g.gradDelay + t)

    # Sort and remove duplicates
    timeSet.sort()
    var times: seq[float64] = @[timeSet[0]]
    for i in 1 ..< timeSet.len:
      if timeSet[i] - times[^1] >= eps:
        times.add(timeSet[i])
      else:
        # Merge close times
        times[^1] = (times[^1] + timeSet[i]) / 2.0

    # Interpolate and sum amplitudes
    var amplitudes = newSeq[float64](times.len)
    for g in grads:
      var tt: seq[float64]
      var wf: seq[float64]
      if g.kind == ekTrap:
        if g.trapFlatTime > 0:
          let (s0, s1, s2, s3) = cumsum4(g.trapDelay, g.trapRiseTime, g.trapFlatTime, g.trapFallTime)
          tt = @[s0, s1, s2, s3]
          wf = @[0.0, g.trapAmplitude, g.trapAmplitude, 0.0]
        else:
          let (s0, s1, s2) = cumsum3(g.trapDelay, g.trapRiseTime, g.trapFallTime)
          tt = @[s0, s1, s2]
          wf = @[0.0, g.trapAmplitude, 0.0]
      else:
        tt = newSeq[float64](g.gradTt.len)
        for j in 0 ..< g.gradTt.len:
          tt[j] = g.gradDelay + g.gradTt[j]
        wf = g.gradWaveform

      # Fix rounding for first and last
      if tt.len > 0:
        var bestDist = Inf
        var bestIdx = 0
        for j in 0 ..< times.len:
          let d = abs(tt[0] - times[j])
          if d < bestDist:
            bestDist = d
            bestIdx = j
        if bestDist < eps:
          tt[0] = times[bestIdx]

        bestDist = Inf
        for j in 0 ..< times.len:
          let d = abs(tt[^1] - times[j])
          if d < bestDist:
            bestDist = d
            bestIdx = j
        if bestDist < eps:
          tt[^1] = times[bestIdx]

      if abs(wf[0]) > eps and tt[0] > eps:
        tt[0] = tt[0] + eps

      # Linear interpolation
      for j in 0 ..< times.len:
        let x = times[j]
        if x < tt[0] or x > tt[^1]:
          continue  # Out of range, add 0
        # Find interval
        var k = 0
        while k < tt.len - 1 and tt[k + 1] < x:
          inc k
        if k >= tt.len - 1:
          amplitudes[j] += wf[^1]
        else:
          let t0 = tt[k]
          let t1 = tt[k + 1]
          if t1 == t0:
            amplitudes[j] += wf[k]
          else:
            amplitudes[j] += wf[k] + (wf[k + 1] - wf[k]) * (x - t0) / (t1 - t0)

    return makeExtendedTrapezoid(channel = channel, amplitudes = amplitudes, times = times, system = system)

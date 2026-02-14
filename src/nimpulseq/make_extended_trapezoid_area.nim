import std/math
import types
import make_extended_trapezoid

proc makeExtendedTrapezoidArea*(
    channel: string,
    area: float64,
    gradStart: float64,
    gradEnd: float64,
    system: Opts = defaultOpts(),
): tuple[grad: Event, times: seq[float64], amplitudes: seq[float64]] =
  ## Make the shortest possible extended trapezoid for given area and gradient start/end points.
  let maxSlew = system.maxSlew * 0.99
  let maxGrad = system.maxGrad * 0.99
  let rasterTime = system.gradRasterTime

  proc toRaster(time: float64): float64 =
    ceil(time / rasterTime) * rasterTime

  proc calcRampTime(grad1, grad2: float64): float64 =
    toRaster(abs(grad1 - grad2) / maxSlew)

  proc findSolution(duration: int): tuple[found: bool, rampUp: int, flatTime: int, rampDown: int, gradAmp: float64] =
    ## Find extended trapezoid gradient waveform for given duration.
    var rampUpTimes: seq[int] = @[]
    var rampDownTimes: seq[int] = @[]

    # First, consider solutions that use maximum slew rate (positive direction)
    var rampUpTime = int(round((float64(duration) * maxSlew * rasterTime - gradStart + gradEnd) / (2.0 * maxSlew * rasterTime)))

    if gradStart + float64(rampUpTime) * maxSlew * rasterTime > maxGrad + eps:
      rampUpTime = int(round(calcRampTime(gradStart, maxGrad) / rasterTime))
      var rampDownTime = int(round(calcRampTime(gradEnd, maxGrad) / rasterTime))
      if rampUpTime > 0 and rampDownTime > 0 and rampUpTime + rampDownTime <= duration:
        rampUpTimes.add(rampUpTime)
        rampDownTimes.add(rampDownTime)
    else:
      var rampDownTime = duration - rampUpTime
      if rampUpTime > 0 and rampDownTime > 0 and rampUpTime + rampDownTime <= duration:
        rampUpTimes.add(rampUpTime)
        rampDownTimes.add(rampDownTime)

    # Negative direction
    rampUpTime = int(round((float64(duration) * maxSlew * rasterTime + gradStart - gradEnd) / (2.0 * maxSlew * rasterTime)))

    if gradStart - float64(rampUpTime) * maxSlew * rasterTime < -maxGrad - eps:
      rampUpTime = int(round(calcRampTime(gradStart, -maxGrad) / rasterTime))
      var rampDownTime = int(round(calcRampTime(gradEnd, -maxGrad) / rasterTime))
      if rampUpTime > 0 and rampDownTime > 0 and rampUpTime + rampDownTime <= duration:
        rampUpTimes.add(rampUpTime)
        rampDownTimes.add(rampDownTime)
    else:
      var rampDownTime = duration - rampUpTime
      if rampUpTime > 0 and rampDownTime > 0 and rampUpTime + rampDownTime <= duration:
        rampUpTimes.add(rampUpTime)
        rampDownTimes.add(rampDownTime)

    # Try any solution with flat_time == 0
    for rut in 1 ..< duration:
      rampUpTimes.add(rut)
      rampDownTimes.add(duration - rut)

    # Now evaluate all candidates
    var bestSlew = Inf
    var bestIdx = -1
    var bestGradAmp = 0.0
    var bestRampUp = 0
    var bestFlatTime = 0
    var bestRampDown = 0

    for idx in 0 ..< rampUpTimes.len:
      let tru = rampUpTimes[idx]
      let trd = rampDownTimes[idx]
      let ft = duration - tru - trd
      if ft < 0:
        continue

      # Calculate gradient strength
      let denom = float64(tru + 2 * ft + trd) * rasterTime
      if denom == 0.0:
        continue
      let gradAmp = -(float64(tru) * rasterTime * gradStart + float64(trd) * rasterTime * gradEnd - 2.0 * area) / denom

      # Calculate slew rates
      let sr1 = abs(gradStart - gradAmp) / (float64(tru) * rasterTime)
      let sr2 = abs(gradEnd - gradAmp) / (float64(trd) * rasterTime)

      # Check constraints
      if abs(gradAmp) <= maxGrad + 1e-8 and sr1 <= maxSlew + 1e-8 and sr2 <= maxSlew + 1e-8:
        let totalSlew = sr1 + sr2
        if totalSlew < bestSlew:
          bestSlew = totalSlew
          bestIdx = idx
          bestGradAmp = gradAmp
          bestRampUp = tru
          bestFlatTime = ft
          bestRampDown = trd

    if bestIdx < 0:
      return (false, 0, 0, 0, 0.0)
    else:
      return (true, bestRampUp, bestFlatTime, bestRampDown, bestGradAmp)

  # Linear search for minimum duration
  let minDuration = max(int(round(calcRampTime(gradEnd, gradStart) / rasterTime)), 2)
  let maxDurationInit = max(
    max(int(round(calcRampTime(0, gradStart) / rasterTime)),
        int(round(calcRampTime(0, gradEnd) / rasterTime))),
    minDuration
  )

  var solution: tuple[found: bool, rampUp: int, flatTime: int, rampDown: int, gradAmp: float64]
  solution.found = false

  for dur in minDuration .. maxDurationInit:
    solution = findSolution(dur)
    if solution.found:
      break

  # Binary search if no solution found
  if not solution.found:
    var maxDur = maxDurationInit
    while not solution.found:
      maxDur *= 2
      solution = findSolution(maxDur)

    # Binary search
    var lo = maxDur div 2
    var hi = maxDur
    while lo < hi - 1:
      let mid = (lo + hi) div 2
      let midSol = findSolution(mid)
      if midSol.found:
        hi = mid
        solution = midSol
      else:
        lo = mid
    # Ensure we have the solution for hi
    let hiSol = findSolution(hi)
    if hiSol.found:
      solution = hiSol

  # Build the extended trapezoid
  let timeRampUp = float64(solution.rampUp) * rasterTime
  let flatTime = float64(solution.flatTime) * rasterTime
  let timeRampDown = float64(solution.rampDown) * rasterTime
  let gradAmp = solution.gradAmp

  var times: seq[float64]
  var amplitudes: seq[float64]

  if flatTime > 0:
    times = @[0.0, timeRampUp, timeRampUp + flatTime, timeRampUp + flatTime + timeRampDown]
    amplitudes = @[gradStart, gradAmp, gradAmp, gradEnd]
  else:
    times = @[0.0, timeRampUp, timeRampUp + timeRampDown]
    amplitudes = @[gradStart, gradAmp, gradEnd]

  let grad = makeExtendedTrapezoid(
    channel = channel,
    amplitudes = amplitudes,
    times = times,
    system = system,
  )

  # Verify area
  var calcArea = 0.0
  for i in 0 ..< grad.gradTt.len - 1:
    calcArea += 0.5 * (grad.gradTt[i + 1] - grad.gradTt[i]) * (grad.gradWaveform[i + 1] + grad.gradWaveform[i])
  if abs(calcArea - area) >= 1e-8:
    raise newException(ValueError, "Could not find a solution for the requested area.")

  result = (grad, grad.gradTt, grad.gradWaveform)

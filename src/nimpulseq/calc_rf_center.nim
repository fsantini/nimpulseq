import std/[math, complex]
import types

proc calcRfCenter*(rf: Event): tuple[timeCenter: float64, idCenter: int] =
  ## Calculate the time point of the effective rotation.
  ## For shaped pulses: peak of the RF amplitude.
  ## For block pulses: center of the pulse.
  ## Delay field is not taken into account.
  assert rf.kind == ekRf

  # If center is already set, use it
  if rf.rfCenter != 0.0:
    # Find the index closest to rf.rfCenter
    var bestIdx = 0
    var bestDist = abs(rf.rfT[0] - rf.rfCenter)
    for i in 1 ..< rf.rfT.len:
      let dist = abs(rf.rfT[i] - rf.rfCenter)
      if dist < bestDist:
        bestDist = dist
        bestIdx = i
    return (rf.rfCenter, bestIdx)

  # Detect the excitation peak; if it's a plateau take its center
  var rfMax = 0.0
  for i in 0 ..< rf.rfSignal.len:
    let m = abs(rf.rfSignal[i])
    if m > rfMax:
      rfMax = m

  var iPeakFirst = -1
  var iPeakLast = -1
  for i in 0 ..< rf.rfSignal.len:
    if abs(rf.rfSignal[i]) >= rfMax * 0.99999:
      if iPeakFirst < 0:
        iPeakFirst = i
      iPeakLast = i

  let timeCenter = (rf.rfT[iPeakFirst] + rf.rfT[iPeakLast]) / 2.0
  let nPeaks = iPeakLast - iPeakFirst + 1
  let idCenter = iPeakFirst + int(round(float64(nPeaks - 1) / 2.0))

  (timeCenter, idCenter)

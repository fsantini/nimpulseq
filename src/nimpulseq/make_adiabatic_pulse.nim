import std/[math, complex]
import types
import calc_rf_center
import make_trap

proc hypsec(n: int, beta: float64 = 800.0, mu: float64 = 4.9, dur: float64 = 0.012): tuple[ampMod: seq[float64], freqMod: seq[float64]] =
  var ampMod = newSeq[float64](n)
  var freqMod = newSeq[float64](n)
  for i in 0 ..< n:
    let t = float64(i - n div 2) / float64(n) * dur
    ampMod[i] = 1.0 / cosh(beta * t)
    freqMod[i] = -mu * beta * tanh(beta * t)
  (ampMod, freqMod)

proc wurst(n: int, nFac: int = 40, bw: float64 = 40e3, dur: float64 = 2e-3): tuple[ampMod: seq[float64], freqMod: seq[float64]] =
  var ampMod = newSeq[float64](n)
  var freqMod = newSeq[float64](n)
  for i in 0 ..< n:
    let t = float64(i) * dur / float64(n)
    ampMod[i] = 1.0 - pow(abs(cos(PI * t / dur)), float64(nFac))
    freqMod[i] = (-bw / 2.0 + bw * float64(i) / float64(n - 1)) * 2.0 * PI
  (ampMod, freqMod)

proc makeAdiabaticPulse*(
    pulseType: string,
    adiabaticity: int = 4,
    bandwidth: float64 = 40000.0,
    beta: float64 = 800.0,
    delay: float64 = 0.0,
    duration: float64 = 10e-3,
    dwell: float64 = 0.0,
    freqOffset: float64 = 0.0,
    maxGrad: float64 = 0.0,
    maxSlew: float64 = 0.0,
    nFac: int = 40,
    mu: float64 = 4.9,
    phaseOffset: float64 = 0.0,
    returnGz: bool = false,
    sliceThickness: float64 = 0.0,
    system: Opts = defaultOpts(),
    use: string = "inversion",
    freqPpm: float64 = 0.0,
    phasePpm: float64 = 0.0,
): tuple[rf: Event, gz: Event, gzr: Event] =
  ## Creates an adiabatic RF pulse with simultaneous amplitude and frequency modulation.
  ##
  ## - `pulseType`: waveform type; either `"hypsec"` (hyperbolic secant) or `"wurst"`.
  ## - `adiabaticity`: adiabaticity factor K (higher = more adiabatic, stronger B1).
  ## - `duration` (s): pulse duration (default 10 ms).
  ## - `bandwidth` (Hz): sweep bandwidth (used directly for "wurst"; derived for "hypsec").
  ## - `beta`: frequency modulation rate parameter for "hypsec".
  ## - `mu`: dimensionless parameter controlling the phase modulation slope for "hypsec".
  ## - `nFac`: amplitude shaping exponent for "wurst".
  ## - `returnGz`: if true, also returns slice-selection (`gz`) and rephasing (`gzr`) trapezoids.
  ##   Requires `sliceThickness` > 0.
  ## - `use`: intended use string (see `supportedRfUses`); default "inversion".
  ##
  ## Returns `(rf, gz, gzr)`; `gz` and `gzr` are `nil` when `returnGz = false`.
  ## Raises `ValueError` for unsupported `pulseType` or `use`.
  var sys = system
  if use notin supportedRfUses:
    raise newException(ValueError, "Invalid use parameter.")
  var dw = dwell
  if dw == 0.0:
    dw = sys.rfRasterTime

  let nRaw = int(round(duration / dw + eps))
  let nSamples0 = (nRaw div 4) * 4

  var ampMod: seq[float64]
  var freqMod: seq[float64]

  if pulseType == "hypsec":
    (ampMod, freqMod) = hypsec(nSamples0, beta, mu, duration)
  elif pulseType == "wurst":
    (ampMod, freqMod) = wurst(nSamples0, nFac, bandwidth, duration)
  else:
    raise newException(ValueError, "Invalid pulse type: " & pulseType)

  # Phase modulation = cumsum(freq_mod) * dwell
  var phaseMod = newSeq[float64](nSamples0)
  phaseMod[0] = freqMod[0] * dw
  for i in 1 ..< nSamples0:
    phaseMod[i] = phaseMod[i - 1] + freqMod[i] * dw

  # Find minimum absolute frequency index
  var minAbsFreqIdx = 0
  var minAbsFreqValue = abs(freqMod[0])
  for i in 1 ..< nSamples0:
    if abs(freqMod[i]) < minAbsFreqValue:
      minAbsFreqValue = abs(freqMod[i])
      minAbsFreqIdx = i

  var phaseAtZeroFreq: float64
  var ampAtZeroFreq: float64
  var rateOfFreqChange: float64

  if minAbsFreqValue == 0.0:
    phaseAtZeroFreq = phaseMod[minAbsFreqIdx]
    ampAtZeroFreq = ampMod[minAbsFreqIdx]
    rateOfFreqChange = abs(freqMod[minAbsFreqIdx + 1] - freqMod[minAbsFreqIdx - 1]) / (2.0 * dw)
  else:
    let b = if freqMod[minAbsFreqIdx] * freqMod[minAbsFreqIdx + 1] < 0: 1 else: -1
    let diffFreq = freqMod[minAbsFreqIdx + b] - freqMod[minAbsFreqIdx]

    phaseAtZeroFreq = (phaseMod[minAbsFreqIdx] * freqMod[minAbsFreqIdx + b] -
                       phaseMod[minAbsFreqIdx + b] * freqMod[minAbsFreqIdx]) / diffFreq

    ampAtZeroFreq = (ampMod[minAbsFreqIdx] * freqMod[minAbsFreqIdx + b] -
                     ampMod[minAbsFreqIdx + b] * freqMod[minAbsFreqIdx]) / diffFreq

    rateOfFreqChange = abs(freqMod[minAbsFreqIdx] - freqMod[minAbsFreqIdx + b]) / dw

  # Adjust phase modulation and calculate amplitude
  for i in 0 ..< nSamples0:
    phaseMod[i] -= phaseAtZeroFreq
  let amp = sqrt(rateOfFreqChange * float64(adiabaticity)) / (2.0 * PI * ampAtZeroFreq)

  # Create the modulated signal
  var signal = newSeq[Complex64](nSamples0)
  for i in 0 ..< nSamples0:
    signal[i] = complex64(amp * ampMod[i] * cos(phaseMod[i]),
                          amp * ampMod[i] * sin(phaseMod[i]))

  # Adjust samples if needed (padding)
  var nSamples = nSamples0
  var finalSignal: seq[Complex64]
  if nSamples != nRaw:
    let nPad = nRaw - nSamples
    let padLeft = nPad div 2
    let padRight = nPad - padLeft
    finalSignal = newSeq[Complex64](nRaw)
    for i in 0 ..< padLeft:
      finalSignal[i] = complex64(0.0, 0.0)
    for i in 0 ..< nSamples:
      finalSignal[padLeft + i] = signal[i]
    for i in 0 ..< padRight:
      finalSignal[padLeft + nSamples + i] = complex64(0.0, 0.0)
    nSamples = nRaw
  else:
    finalSignal = signal

  # Calculate time points
  var t = newSeq[float64](nSamples)
  for i in 0 ..< nSamples:
    t[i] = (float64(i) + 0.5) * dw

  var rf = Event(kind: ekRf)
  rf.rfSignal = finalSignal
  rf.rfT = t
  rf.rfShapeDur = float64(nSamples) * dw
  rf.rfFreqOffset = freqOffset
  rf.rfPhaseOffset = phaseOffset
  rf.rfFreqPpm = freqPpm
  rf.rfPhasePpm = phasePpm
  rf.rfDeadTime = sys.rfDeadTime
  rf.rfRingdownTime = sys.rfRingdownTime
  rf.rfDelay = delay
  rf.rfUse = use

  # Calculate center
  let (center, _) = calcRfCenter(rf)
  rf.rfCenter = center

  if rf.rfDeadTime > rf.rfDelay:
    rf.rfDelay = rf.rfDeadTime

  var gz: Event = nil
  var gzr: Event = nil

  if returnGz:
    if sliceThickness <= 0:
      raise newException(ValueError, "Slice thickness must be provided")

    var bw2: float64
    if pulseType == "hypsec":
      bw2 = mu * beta / PI
    else:
      bw2 = bandwidth

    let amplitude = bw2 / sliceThickness
    let area = amplitude * duration
    gz = makeTrapezoid(channel = "z", system = sys, flatTime = duration, flatArea = area)
    gzr = makeTrapezoid(
      channel = "z",
      system = sys,
      area = -area * (1.0 - center) - 0.5 * (gz.trapArea - area),
    )

    if rf.rfDelay > gz.trapRiseTime:
      gz.trapDelay = ceil((rf.rfDelay - gz.trapRiseTime) / sys.gradRasterTime) * sys.gradRasterTime

    if rf.rfDelay < (gz.trapRiseTime + gz.trapDelay):
      rf.rfDelay = gz.trapRiseTime + gz.trapDelay

  result = (rf, gz, gzr)

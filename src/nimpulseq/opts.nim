import std/math
import types

proc convert*(fromValue: float64, fromUnit: string, gamma: float64 = 42576000.0): float64 =
  ## Convert gradient or slew rate to standard units (Hz/m or Hz/m/s)
  case fromUnit
  of "Hz/m", "Hz/m/s":
    result = fromValue
  of "mT/m":
    result = fromValue * 1e-3 * gamma
  of "T/m/s", "mT/m/ms":
    result = fromValue * gamma
  of "rad/ms/mm":
    result = fromValue * 1e6 / (2 * PI)
  of "rad/ms/mm/ms":
    result = fromValue * 1e9 / (2 * PI)
  else:
    raise newException(ValueError, "Invalid unit: " & fromUnit)

proc newOpts*(
    maxGrad: float64 = 0.0,
    gradUnit: string = "Hz/m",
    maxSlew: float64 = 0.0,
    slewUnit: string = "Hz/m/s",
    rfRingdownTime: float64 = -1.0,
    rfDeadTime: float64 = -1.0,
    adcDeadTime: float64 = -1.0,
    adcRasterTime: float64 = -1.0,
    rfRasterTime: float64 = -1.0,
    gradRasterTime: float64 = -1.0,
    blockDurationRaster: float64 = -1.0,
    riseTime: float64 = 0.0,
    gamma: float64 = -1.0,
    B0: float64 = -1.0,
    adcSamplesLimit: int = -1,
    adcSamplesDivisor: int = -1,
): Opts =
  ## Creates an `Opts` scanner limits object with user-supplied values.
  ## Parameters not provided (or given a negative sentinel) fall back to `defaultOpts()`.
  ## `gradUnit` accepts "Hz/m" or "mT/m"; `slewUnit` accepts "Hz/m/s", "T/m/s", or "mT/m/ms".
  ## If `riseTime` > 0, it overrides `maxSlew` to enforce a fixed ramp time.
  let defaults = defaultOpts()
  let g = if gamma < 0: defaults.gamma else: gamma

  var mg: float64
  if maxGrad > 0:
    mg = convert(maxGrad, gradUnit, abs(g))
  else:
    mg = defaults.maxGrad

  var ms: float64
  if maxSlew > 0:
    ms = convert(maxSlew, slewUnit, abs(g))
  else:
    ms = defaults.maxSlew

  if riseTime > 0:
    ms = mg / riseTime

  Opts(
    maxGrad: mg,
    maxSlew: ms,
    riseTime: riseTime,
    rfDeadTime: (if rfDeadTime < 0: defaults.rfDeadTime else: rfDeadTime),
    rfRingdownTime: (if rfRingdownTime < 0: defaults.rfRingdownTime else: rfRingdownTime),
    adcDeadTime: (if adcDeadTime < 0: defaults.adcDeadTime else: adcDeadTime),
    adcRasterTime: (if adcRasterTime < 0: defaults.adcRasterTime else: adcRasterTime),
    rfRasterTime: (if rfRasterTime < 0: defaults.rfRasterTime else: rfRasterTime),
    gradRasterTime: (if gradRasterTime < 0: defaults.gradRasterTime else: gradRasterTime),
    blockDurationRaster: (if blockDurationRaster < 0: defaults.blockDurationRaster else: blockDurationRaster),
    adcSamplesLimit: (if adcSamplesLimit < 0: defaults.adcSamplesLimit else: adcSamplesLimit),
    adcSamplesDivisor: (if adcSamplesDivisor < 0: defaults.adcSamplesDivisor else: adcSamplesDivisor),
    gamma: g,
    B0: (if B0 < 0: defaults.B0 else: B0),
  )

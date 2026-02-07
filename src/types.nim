import std/[tables, complex, math]

const eps* = 1e-9

type
  GradChannel* = enum
    gcX = "x", gcY = "y", gcZ = "z"

  EventKind* = enum
    ekRf, ekTrap, ekGrad, ekAdc, ekDelay, ekLabelSet, ekLabelInc, ekTrigger, ekOutput

  Event* = ref object
    case kind*: EventKind
    of ekRf:
      rfSignal*: seq[Complex64]
      rfT*: seq[float64]
      rfShapeDur*: float64
      rfFreqOffset*, rfPhaseOffset*: float64
      rfFreqPpm*, rfPhasePpm*: float64
      rfDeadTime*, rfRingdownTime*: float64
      rfDelay*: float64
      rfCenter*: float64
      rfUse*: string
    of ekTrap:
      trapChannel*: GradChannel
      trapAmplitude*: float64
      trapRiseTime*, trapFlatTime*, trapFallTime*: float64
      trapArea*, trapFlatArea*: float64
      trapDelay*: float64
      trapFirst*, trapLast*: float64
    of ekGrad:
      gradChannel*: GradChannel
      gradAmplitude*: float64
      gradWaveform*: seq[float64]
      gradTt*: seq[float64]
      gradDelay*: float64
      gradShapeDur*: float64
      gradFirst*, gradLast*: float64
    of ekAdc:
      adcNumSamples*: int
      adcDwell*: float64
      adcDelay*: float64
      adcFreqOffset*, adcPhaseOffset*: float64
      adcFreqPpm*, adcPhasePpm*: float64
      adcDeadTime*: float64
      adcDuration*: float64
    of ekDelay:
      delayD*: float64
    of ekLabelSet, ekLabelInc:
      labelName*: string
      labelValue*: int
    of ekTrigger, ekOutput:
      trigChannel*: string
      trigDelay*, trigDuration*: float64

  Opts* = object
    maxGrad*: float64        # Hz/m
    maxSlew*: float64        # Hz/m/s
    riseTime*: float64
    rfDeadTime*: float64
    rfRingdownTime*: float64
    adcDeadTime*: float64
    adcRasterTime*: float64
    rfRasterTime*: float64
    gradRasterTime*: float64
    blockDurationRaster*: float64
    adcSamplesLimit*: int
    adcSamplesDivisor*: int
    gamma*: float64
    B0*: float64

  EventLibrary* = ref object
    data*: OrderedTable[int, seq[float64]]
    dataType*: Table[int, char]
    keymap*: Table[seq[float64], int]
    nextFreeID*: int
    numpyData*: bool

  Sequence* = ref object
    adcLibrary*: EventLibrary
    delayLibrary*: EventLibrary
    extensionsLibrary*: EventLibrary
    gradLibrary*: EventLibrary
    labelIncLibrary*: EventLibrary
    labelSetLibrary*: EventLibrary
    rfLibrary*: EventLibrary
    shapeLibrary*: EventLibrary
    triggerLibrary*: EventLibrary
    system*: Opts
    blockEvents*: OrderedTable[int, seq[int32]]
    nextFreeBlockID*: int
    definitions*: OrderedTable[string, seq[string]]
    rfRasterTime*: float64
    gradRasterTime*: float64
    adcRasterTime*: float64
    blockDurationRaster*: float64
    blockDurations*: Table[int, float64]
    extensionNumericIdx*: seq[int]
    extensionStringIdx*: seq[string]
    versionMajor*: int
    versionMinor*: int
    versionRevision*: string

const supportedLabels* = [
  "SLC", "SEG", "REP", "AVG", "SET", "ECO", "PHS", "LIN", "PAR", "ACQ",
  "NAV", "REV", "SMS", "REF", "IMA", "NOISE", "PMC", "NOROT", "NOPOS",
  "NOSCL", "ONCE", "TRID"
]

const supportedRfUses* = [
  "excitation", "refocusing", "inversion", "saturation", "preparation", "other", "undefined"
]

proc defaultOpts*(): Opts =
  let gamma = 42576000.0
  Opts(
    maxGrad: 40.0 * 1e-3 * gamma,   # 40 mT/m -> Hz/m
    maxSlew: 170.0 * gamma,          # 170 T/m/s -> Hz/m/s
    riseTime: 0.0,
    rfDeadTime: 0.0,
    rfRingdownTime: 0.0,
    adcDeadTime: 0.0,
    adcRasterTime: 100e-9,
    rfRasterTime: 1e-6,
    gradRasterTime: 10e-6,
    blockDurationRaster: 10e-6,
    adcSamplesLimit: 0,
    adcSamplesDivisor: 4,
    gamma: gamma,
    B0: 1.5,
  )

proc newEventLibrary*(): EventLibrary =
  EventLibrary(
    data: initOrderedTable[int, seq[float64]](),
    dataType: initTable[int, char](),
    keymap: initTable[seq[float64], int](),
    nextFreeID: 1,
    numpyData: false,
  )

proc parseChannel*(ch: string): GradChannel =
  case ch
  of "x": gcX
  of "y": gcY
  of "z": gcZ
  else: raise newException(ValueError, "Invalid channel: " & ch)

proc channelToIndex*(ch: GradChannel): int =
  case ch
  of gcX: 0
  of gcY: 1
  of gcZ: 2

proc roundHalfUp*(n: float64, decimals: int = 0): float64 =
  ## Avoid banker's rounding inconsistencies.
  let multiplier = pow(10.0, float64(decimals))
  floor(abs(n) * multiplier + 0.5) / multiplier

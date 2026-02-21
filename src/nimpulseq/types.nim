import std/[tables, complex, math]

const eps* = 1e-9
  ## Small epsilon value used for floating-point comparisons throughout the library.

type
  GradChannel* = enum
    ## Gradient channel axis selector.
    gcX = "x", gcY = "y", gcZ = "z"

  EventKind* = enum
    ## Discriminator tag for the `Event` variant object.
    ## Selects which branch of the object is active.
    ekRf, ekTrap, ekGrad, ekAdc, ekDelay, ekLabelSet, ekLabelInc, ekTrigger, ekOutput, ekSoftDelay

  Event* = ref object
    ## A pulse sequence event. The active branch is determined by `kind`.
    case kind*: EventKind
    of ekRf:
      rfSignal*: seq[Complex64]     ## Complex RF waveform samples.
      rfT*: seq[float64]            ## Time points of each sample (s).
      rfShapeDur*: float64          ## Duration of the RF shape (s).
      rfFreqOffset*, rfPhaseOffset*: float64  ## Frequency (Hz) and phase (rad) offsets.
      rfFreqPpm*, rfPhasePpm*: float64        ## PPM-based frequency and phase offsets.
      rfDeadTime*, rfRingdownTime*: float64   ## Scanner dead/ringdown times (s).
      rfDelay*: float64             ## Delay before the RF pulse starts (s).
      rfCenter*: float64            ## Time of the effective rotation center (s).
      rfUse*: string                ## Intended use, e.g. "excitation", "refocusing".
    of ekTrap:
      trapChannel*: GradChannel     ## Gradient axis.
      trapAmplitude*: float64       ## Peak amplitude (Hz/m).
      trapRiseTime*, trapFlatTime*, trapFallTime*: float64  ## Ramp and flat durations (s).
      trapArea*, trapFlatArea*: float64                     ## Total and flat areas (Hz/m·s).
      trapDelay*: float64           ## Delay before the trapezoid starts (s).
      trapFirst*, trapLast*: float64  ## Amplitude at start/end (for continuity checks).
    of ekGrad:
      gradChannel*: GradChannel     ## Gradient axis.
      gradAmplitude*: float64       ## Peak amplitude (Hz/m).
      gradWaveform*: seq[float64]   ## Amplitude samples (Hz/m).
      gradTt*: seq[float64]         ## Time points relative to delay (s).
      gradDelay*: float64           ## Delay before the gradient starts (s).
      gradShapeDur*: float64        ## Duration of the waveform (s).
      gradFirst*, gradLast*: float64  ## Amplitude at start/end (for continuity checks).
    of ekAdc:
      adcNumSamples*: int           ## Number of ADC samples.
      adcDwell*: float64            ## Dwell time per sample (s).
      adcDelay*: float64            ## Delay before acquisition starts (s).
      adcFreqOffset*, adcPhaseOffset*: float64  ## Frequency (Hz) and phase (rad) offsets.
      adcFreqPpm*, adcPhasePpm*: float64        ## PPM-based frequency and phase offsets.
      adcDeadTime*: float64         ## Post-ADC dead time (s).
      adcDuration*: float64         ## Total acquisition duration (s).
    of ekDelay:
      delayD*: float64              ## Delay duration (s).
    of ekLabelSet, ekLabelInc:
      labelName*: string            ## Label identifier string, e.g. "LIN".
      labelValue*: int              ## Value to set or increment the label by.
    of ekTrigger, ekOutput:
      trigChannel*: string          ## Channel name, e.g. "physio1" or "osc0".
      trigDelay*, trigDuration*: float64  ## Delay and duration of the trigger pulse (s).
    of ekSoftDelay:
      sdHint*: string               ## Human-readable label shown in the scanner interface (no whitespace).
      sdNumID*: int                 ## Numeric ID; -1 means auto-assign when added to the sequence.
      sdOffset*: float64            ## Time offset (s) added to the calculated duration.
      sdFactor*: float64            ## Scaling factor: duration = (input / sdFactor) + sdOffset.
      sdDefaultDuration*: float64   ## Default block duration (s) used before applySoftDelay is called.

  Opts* = object
    ## Scanner hardware limits and raster times used to constrain event creation.
    ## All gradient/slew values are stored internally in Hz/m and Hz/m/s.
    maxGrad*: float64        ## Maximum gradient amplitude (Hz/m).
    maxSlew*: float64        ## Maximum slew rate (Hz/m/s).
    riseTime*: float64       ## Fixed rise time override; 0 means derive from maxSlew (s).
    rfDeadTime*: float64     ## Minimum RF pre-pulse dead time (s).
    rfRingdownTime*: float64 ## RF ringdown time after pulse end (s).
    adcDeadTime*: float64    ## Minimum ADC pre-acquisition dead time (s).
    adcRasterTime*: float64  ## ADC dwell time raster (s).
    rfRasterTime*: float64   ## RF waveform sample raster (s).
    gradRasterTime*: float64 ## Gradient waveform sample raster (s).
    blockDurationRaster*: float64  ## Block duration must be a multiple of this (s).
    adcSamplesLimit*: int    ## Maximum allowed ADC samples (0 = no limit).
    adcSamplesDivisor*: int  ## ADC sample count must be divisible by this.
    gamma*: float64          ## Gyromagnetic ratio (Hz/T), default 42576000 for 1H.
    B0*: float64             ## Static field strength (T).

  EventLibrary* = ref object
    ## Content-addressable store that deduplicates events by their numeric representation.
    ## Each unique `seq[float64]` key maps to a unique integer ID.
    data*: OrderedTable[int, seq[float64]]   ## ID → numeric data.
    dataType*: Table[int, char]              ## ID → type tag (e.g. 't', 'g', 'u').
    keymap*: Table[seq[float64], int]        ## Reverse map: data → ID.
    nextFreeID*: int                         ## Next ID to assign on insertion.
    numpyData*: bool                         ## Reserved for numpy-compatible loading.

  Sequence* = ref object
    ## The top-level pulse sequence container.
    ## Holds all event libraries, block definitions, and metadata needed to produce a .seq file.
    adcLibrary*: EventLibrary        ## Stores deduplicated ADC events.
    delayLibrary*: EventLibrary      ## Stores deduplicated delay events.
    extensionsLibrary*: EventLibrary ## Stores extension linked-list entries.
    gradLibrary*: EventLibrary       ## Stores deduplicated gradient events (trap and arb).
    labelIncLibrary*: EventLibrary   ## Stores LABELINC events.
    labelSetLibrary*: EventLibrary   ## Stores LABELSET events.
    rfLibrary*: EventLibrary         ## Stores deduplicated RF events.
    shapeLibrary*: EventLibrary      ## Stores compressed RF/gradient waveform shapes.
    triggerLibrary*: EventLibrary    ## Stores trigger/output control events.
    system*: Opts                    ## Hardware limits used when the sequence was created.
    blockEvents*: OrderedTable[int, seq[int32]]  ## Block ID → [dur, rf, gx, gy, gz, adc, ext] IDs.
    nextFreeBlockID*: int            ## Next block ID to use in `addBlock`.
    definitions*: OrderedTable[string, seq[string]]  ## Key-value metadata written to [DEFINITIONS].
    rfRasterTime*: float64           ## RF raster time mirrored from system (s).
    gradRasterTime*: float64         ## Gradient raster time mirrored from system (s).
    adcRasterTime*: float64          ## ADC raster time mirrored from system (s).
    blockDurationRaster*: float64    ## Block duration raster mirrored from system (s).
    blockDurations*: Table[int, float64]         ## Block ID → duration (s).
    blockEventObjects*: Table[int, seq[Event]]   ## Block ID → original event objects.
    gradLastAmps*: array[3, float64] ## Last gradient amplitude on each axis for continuity checks (Hz/m).
    extensionNumericIdx*: seq[int]   ## Numeric IDs of registered extension types.
    extensionStringIdx*: seq[string] ## String names of registered extension types.
    versionMajor*: int               ## Pulseq format major version (1).
    versionMinor*: int               ## Pulseq format minor version (5).
    versionRevision*: string         ## Pulseq format revision string ("0").
    softDelayData*: OrderedTable[int, tuple[numID: int; offset: float64; factor: float64; hint: string]]
      ## Soft delay event store: ID → (numID, offset, factor, hint).
    softDelayHints*: Table[string, int]  ## Maps hint string → assigned numID.
    nextFreeSoftDelayID*: int        ## Next ID to assign to a new soft delay entry.

const supportedLabels* = [
  ## All label names accepted by `makeLabel`. Labels before index 10 support INC; the rest are flags.
  "SLC", "SEG", "REP", "AVG", "SET", "ECO", "PHS", "LIN", "PAR", "ACQ",
  "NAV", "REV", "SMS", "REF", "IMA", "NOISE", "PMC", "NOROT", "NOPOS",
  "NOSCL", "ONCE", "TRID"
]

const supportedRfUses* = [
  ## Valid strings for the `use` parameter of RF pulse creation functions.
  "excitation", "refocusing", "inversion", "saturation", "preparation", "other", "undefined"
]

proc defaultOpts*(): Opts =
  ## Returns an `Opts` instance with default scanner limits:
  ## maxGrad = 40 mT/m, maxSlew = 170 T/m/s, rfRasterTime = 1 µs,
  ## gradRasterTime = 10 µs, B0 = 1.5 T (gamma = 42576000 Hz/T).
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
  ## Creates an empty `EventLibrary` with ID numbering starting at 1.
  EventLibrary(
    data: initOrderedTable[int, seq[float64]](),
    dataType: initTable[int, char](),
    keymap: initTable[seq[float64], int](),
    nextFreeID: 1,
    numpyData: false,
  )

proc parseChannel*(ch: string): GradChannel =
  ## Converts a channel string ("x", "y", or "z") to a `GradChannel` enum value.
  ## Raises `ValueError` for any other input.
  case ch
  of "x": gcX
  of "y": gcY
  of "z": gcZ
  else: raise newException(ValueError, "Invalid channel: " & ch)

proc channelToIndex*(ch: GradChannel): int =
  ## Maps a `GradChannel` to its 0-based array index: gcX→0, gcY→1, gcZ→2.
  case ch
  of gcX: 0
  of gcY: 1
  of gcZ: 2

proc roundHalfUp*(n: float64, decimals: int = 0): float64 =
  ## Avoid banker's rounding inconsistencies.
  let multiplier = pow(10.0, float64(decimals))
  floor(abs(n) * multiplier + 0.5) / multiplier

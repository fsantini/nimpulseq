# NimPulseq API Reference

NimPulseq is a Nim port of [PyPulseq](https://github.com/imr-framework/pypulseq), a vendor-neutral MRI pulse sequence design library. It generates `.seq` files in the Pulseq v1.5.0 format.

## Quick Start

```nim
import std/math
import nimpulseq

proc main() =
  let system = newOpts(
    maxGrad = 32, gradUnit = "mT/m",
    maxSlew = 130, slewUnit = "T/m/s",
    rfRingdownTime = 20e-6,
    rfDeadTime = 100e-6,
    adcDeadTime = 20e-6,
  )
  var seqObj = newSequence(system)

  var (rf, gz, _) = makeSincPulse(
    flipAngle = PI / 2.0,
    system = system,
    duration = 3e-3,
    sliceThickness = 3e-3,
    apodization = 0.5,
    timeBwProduct = 4.0,
    returnGz = true,
    delay = system.rfDeadTime,
    use = "excitation",
  )
  let gx = makeTrapezoid(channel = "x", system = system, flatArea = 16384.0, flatTime = 3.2e-4)
  let adc = makeAdc(numSamples = 64, system = system, duration = gx.trapFlatTime, delay = gx.trapRiseTime)

  seqObj.addBlock(rf, gz)
  seqObj.addBlock(gx, adc)

  seqObj.writeSeq("my_sequence.seq", createSignature = true)

main()
```

---

## Core Types

### `Opts`

Scanner hardware limits. All gradient/slew values are stored internally in Hz/m and Hz/m/s.

| Field                  | Type      | Default          | Description                    |
|------------------------|-----------|------------------|--------------------------------|
| `maxGrad`              | `float64` | 40 mT/m equiv.   | Maximum gradient amplitude     |
| `maxSlew`              | `float64` | 170 T/m/s equiv. | Maximum slew rate              |
| `rfDeadTime`           | `float64` | `0.0`            | RF dead time (s)               |
| `rfRingdownTime`       | `float64` | `0.0`            | RF ringdown time (s)           |
| `adcDeadTime`          | `float64` | `0.0`            | ADC dead time (s)              |
| `adcRasterTime`        | `float64` | `100e-9`         | ADC raster time (s)            |
| `rfRasterTime`         | `float64` | `1e-6`           | RF raster time (s)             |
| `gradRasterTime`       | `float64` | `10e-6`          | Gradient raster time (s)       |
| `blockDurationRaster`  | `float64` | `10e-6`          | Block duration raster (s)      |
| `gamma`                | `float64` | `42576000.0`     | Gyromagnetic ratio (Hz/T)      |
| `B0`                   | `float64` | `1.494`          | Static field strength (T)      |
| `riseTime`             | `float64` | `0.0`            | Default rise time (0 = compute)|
| `adcSamplesLimit`      | `int`     | `0`              | Max ADC samples (0 = no limit) |
| `adcSamplesDivisor`    | `int`     | `4`              | ADC sample count divisor       |

### `Event`

A discriminated union (variant object) representing all event types. The `kind` field determines which fields are accessible.

**`EventKind` enum values:** `ekRf`, `ekTrap`, `ekGrad`, `ekAdc`, `ekDelay`, `ekLabelSet`, `ekLabelInc`, `ekTrigger`, `ekOutput`

#### RF fields (`ekRf`)
| Field             | Type               | Description                       |
|-------------------|--------------------|-----------------------------------|
| `rfSignal`        | `seq[Complex64]`   | Complex RF waveform               |
| `rfT`             | `seq[float64]`     | Time points (s)                   |
| `rfShapeDur`      | `float64`          | Shape duration (s)                |
| `rfFreqOffset`    | `float64`          | Frequency offset (Hz)             |
| `rfPhaseOffset`   | `float64`          | Phase offset (rad)                |
| `rfFreqPpm`       | `float64`          | Frequency offset (ppm)            |
| `rfPhasePpm`      | `float64`          | Phase offset (ppm)                |
| `rfDeadTime`      | `float64`          | Dead time (s)                     |
| `rfRingdownTime`  | `float64`          | Ringdown time (s)                 |
| `rfDelay`         | `float64`          | Delay before pulse (s)            |
| `rfCenter`        | `float64`          | Center time (s)                   |
| `rfUse`           | `string`           | Use type (e.g. "excitation")      |

#### Trapezoid gradient fields (`ekTrap`)
| Field             | Type          | Description                   |
|-------------------|---------------|-------------------------------|
| `trapChannel`     | `GradChannel` | Axis: `gcX`, `gcY`, `gcZ`    |
| `trapAmplitude`   | `float64`     | Peak amplitude (Hz/m)         |
| `trapRiseTime`    | `float64`     | Rise time (s)                 |
| `trapFlatTime`    | `float64`     | Flat-top time (s)             |
| `trapFallTime`    | `float64`     | Fall time (s)                 |
| `trapArea`        | `float64`     | Total area (Hz/m * s)         |
| `trapFlatArea`    | `float64`     | Flat-top area (Hz/m * s)      |
| `trapDelay`       | `float64`     | Delay before gradient (s)     |
| `trapFirst`       | `float64`     | First amplitude sample        |
| `trapLast`        | `float64`     | Last amplitude sample         |

#### Arbitrary gradient fields (`ekGrad`)
| Field             | Type            | Description                    |
|-------------------|-----------------|--------------------------------|
| `gradChannel`     | `GradChannel`   | Axis: `gcX`, `gcY`, `gcZ`     |
| `gradAmplitude`   | `float64`       | Peak amplitude (Hz/m)          |
| `gradWaveform`    | `seq[float64]`  | Waveform samples (normalized)  |
| `gradTt`          | `seq[float64]`  | Time points (s)                |
| `gradDelay`       | `float64`       | Delay before gradient (s)      |
| `gradShapeDur`    | `float64`       | Shape duration (s)             |
| `gradFirst`       | `float64`       | First amplitude sample         |
| `gradLast`        | `float64`       | Last amplitude sample          |

#### ADC fields (`ekAdc`)
| Field             | Type      | Description                   |
|-------------------|-----------|-------------------------------|
| `adcNumSamples`   | `int`     | Number of samples             |
| `adcDwell`        | `float64` | Dwell time per sample (s)     |
| `adcDelay`        | `float64` | Delay before acquisition (s)  |
| `adcFreqOffset`   | `float64` | Frequency offset (Hz)         |
| `adcPhaseOffset`  | `float64` | Phase offset (rad)            |
| `adcFreqPpm`      | `float64` | Frequency offset (ppm)        |
| `adcPhasePpm`     | `float64` | Phase offset (ppm)            |
| `adcDeadTime`     | `float64` | Dead time (s)                 |
| `adcDuration`     | `float64` | Total acquisition duration (s)|

#### Delay fields (`ekDelay`)
| Field    | Type      | Description      |
|----------|-----------|------------------|
| `delayD` | `float64` | Delay duration (s) |

#### Label fields (`ekLabelSet`, `ekLabelInc`)
| Field        | Type     | Description         |
|--------------|----------|---------------------|
| `labelName`  | `string` | Label name (e.g. "LIN") |
| `labelValue` | `int`    | Label value         |

#### Trigger/Output fields (`ekTrigger`, `ekOutput`)
| Field          | Type      | Description                 |
|----------------|-----------|-----------------------------|
| `trigChannel`  | `string`  | Channel name                |
| `trigDelay`    | `float64` | Delay before trigger (s)    |
| `trigDuration` | `float64` | Trigger duration (s)        |

### `GradChannel`

```nim
type GradChannel* = enum
  gcX = "x", gcY = "y", gcZ = "z"
```

### `Sequence`

The main sequence object. Created via `newSequence()`. Key user-facing fields:

| Field                | Type                                    | Description                  |
|----------------------|-----------------------------------------|------------------------------|
| `system`             | `Opts`                                  | Scanner hardware limits      |
| `gradRasterTime`     | `float64`                               | Gradient raster time         |
| `blockDurationRaster`| `float64`                               | Block duration raster        |
| `definitions`        | `OrderedTable[string, seq[string]]`     | Sequence definitions         |

### `AlignSpec`

```nim
type AlignSpec* = enum
  asLeft, asCenter, asRight
```

### Constants

```nim
const eps* = 1e-9
const supportedLabels* = ["SLC", "SEG", "REP", "AVG", "SET", "ECO", "PHS",
                           "LIN", "PAR", "ACQ", "NAV", "REV", "SMS", "REF",
                           "IMA", "NOISE", "PMC", "NOROT", "NOPOS", "NOSCL",
                           "ONCE", "TRID"]
const supportedRfUses* = ["excitation", "refocusing", "inversion",
                           "saturation", "preparation", "other", "undefined"]
```

---

## Sequence Construction

### `newSequence`

```nim
proc newSequence*(system: Opts = defaultOpts()): Sequence
```

Creates a new empty sequence with the given system limits. Automatically sets the standard definitions (`AdcRasterTime`, `BlockDurationRaster`, `GradientRasterTime`, `RadiofrequencyRasterTime`).

### `addBlock`

```nim
proc addBlock*(seq: Sequence, events: varargs[Event])
proc addBlock*(seq: Sequence, events: seq[Event])
```

Appends a new block containing the given events. All events in a block execute simultaneously. The `seq[Event]` overload is provided for passing the result of `rotate()`.

Enforces **gradient continuity**: the starting amplitude of each gradient must match the ending amplitude of the same channel in the previous block. Raises `ValueError` if a discontinuity is detected. Trapezoid gradients always start and end at 0; arbitrary gradients use their `gradFirst`/`gradLast` fields.

### `setDefinition`

```nim
proc setDefinition*(seq_obj: Sequence, key: string, value: string)
proc setDefinition*(seq_obj: Sequence, key: string, value: seq[string])
proc setDefinition*(seq_obj: Sequence, key: string, value: seq[float64])
```

Sets a key-value pair in the sequence definitions header. Float sequences are formatted with 9 significant digits.

### `totalDuration`

```nim
proc totalDuration*(seq_obj: Sequence): float64
```

Returns the total duration of the sequence in seconds (sum of all block durations).

### `registerGradEvent`

```nim
proc registerGradEvent*(seq: Sequence, event: Event): int
```

Pre-registers a gradient event in the library without adding it to a block. Returns the assigned library ID. Useful when specific ID ordering is required (e.g. MPRAGE).

### `checkTiming`

```nim
proc checkTiming*(seq: Sequence): tuple[ok: bool, errors: seq[TimingError]]
```

Performs comprehensive timing validation on the sequence. Returns a tuple of `(ok, errors)` where each `TimingError` contains the block index and a description. Checks include:

- **BLOCK_DURATION_MISMATCH** — stored block duration differs from the computed duration of its events
- **RASTER** — event timing fields not aligned to their respective raster times (gradient, RF, ADC, block duration)
- **RF_DEAD_TIME** — RF delay is less than the system RF dead time
- **RF_RINGDOWN_TIME** — RF extends beyond block duration minus ringdown time
- **ADC_DEAD_TIME** — ADC delay is less than the system ADC dead time
- **POST_ADC_DEAD_TIME** — ADC acquisition ends after block duration minus system dead time
- **NEGATIVE_DELAY** — any event has a negative delay value

### `writeSeq`

```nim
proc writeSeq*(
    seq_obj: Sequence,
    fileName: string,
    createSignature: bool = false,
    doRemoveDuplicates: bool = true,
)
```

Writes the sequence to a `.seq` file. Automatically computes and adds a `TotalDuration` definition. When `createSignature = true`, an MD5 signature is appended to the file.

---

## Event Creation Functions

### `makeSincPulse`

```nim
proc makeSincPulse*(
    flipAngle: float64,           # Flip angle in radians
    apodization: float64 = 0.0,   # Hanning window fraction (0..1)
    delay: float64 = 0.0,         # Delay before pulse (s)
    duration: float64 = 4e-3,     # Pulse duration (s)
    dwell: float64 = 0.0,         # RF dwell time (0 = auto)
    centerPos: float64 = 0.5,     # Center position (0..1)
    freqOffset: float64 = 0.0,    # Frequency offset (Hz)
    maxGrad: float64 = 0.0,       # Max gradient (0 = use system)
    maxSlew: float64 = 0.0,       # Max slew (0 = use system)
    phaseOffset: float64 = 0.0,   # Phase offset (rad)
    returnGz: bool = false,       # Return slice-select gradient
    sliceThickness: float64 = 0.0,# Slice thickness (m)
    system: Opts = defaultOpts(),
    timeBwProduct: float64 = 4.0, # Time-bandwidth product
    use: string = "undefined",    # RF use type
    freqPpm: float64 = 0.0,
    phasePpm: float64 = 0.0,
): tuple[rf: Event, gz: Event, gzr: Event]
```

Creates a sinc RF pulse. Always returns a 3-tuple; when `returnGz = false`, `gz` and `gzr` are `nil`. Validates that `use` is one of `supportedRfUses`.

### `makeBlockPulse`

```nim
proc makeBlockPulse*(
    flipAngle: float64,            # Flip angle in radians
    delay: float64 = 0.0,
    duration: float64 = 0.0,      # Must specify duration, bandwidth, or timeBwProduct
    bandwidth: float64 = 0.0,
    timeBwProduct: float64 = 0.0,
    freqOffset: float64 = 0.0,
    phaseOffset: float64 = 0.0,
    system: Opts = defaultOpts(),
    use: string = "undefined",
    freqPpm: float64 = 0.0,
    phasePpm: float64 = 0.0,
): Event
```

Creates a rectangular (hard) RF pulse. Validates that `use` is one of `supportedRfUses`; raises `ValueError` if not.

### `makeGaussPulse`

```nim
proc makeGaussPulse*(
    flipAngle: float64,
    apodization: float64 = 0.0,
    bandwidth: float64 = 0.0,
    centerPos: float64 = 0.5,
    delay: float64 = 0.0,
    dwell: float64 = 0.0,
    duration: float64 = 4e-3,
    freqOffset: float64 = 0.0,
    maxGrad: float64 = 0.0,
    maxSlew: float64 = 0.0,
    phaseOffset: float64 = 0.0,
    returnGz: bool = false,
    sliceThickness: float64 = 0.0,
    system: Opts = defaultOpts(),
    timeBwProduct: float64 = 4.0,
    use: string = "undefined",
    freqPpm: float64 = 0.0,
    phasePpm: float64 = 0.0,
): tuple[rf: Event, gz: Event, gzr: Event]
```

Creates a Gaussian RF pulse. Returns 3-tuple like `makeSincPulse`. Validates that `use` is one of `supportedRfUses`; raises `ValueError` if not.

### `makeAdiabaticPulse`

```nim
proc makeAdiabaticPulse*(
    pulseType: string,             # "hypsec" (only supported type)
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
): tuple[rf: Event, gz: Event, gzr: Event]
```

Creates an adiabatic RF pulse. Currently only the `"hypsec"` pulse type is implemented. Validates that `use` is one of `supportedRfUses`; raises `ValueError` if not.

### `makeTrapezoid`

```nim
proc makeTrapezoid*(
    channel: string,               # "x", "y", or "z"
    amplitude: float64 = NaN,      # Peak amplitude (Hz/m)
    area: float64 = NaN,           # Total area (Hz/m * s)
    delay: float64 = 0.0,
    duration: float64 = NaN,       # Total duration (s)
    fallTime: float64 = NaN,
    flatArea: float64 = NaN,       # Flat-top area
    flatTime: float64 = NaN,       # Flat-top time (s)
    maxGrad: float64 = 0.0,
    maxSlew: float64 = 0.0,
    riseTime: float64 = NaN,
    system: Opts = defaultOpts(),
): Event
```

Creates a trapezoidal gradient. Three modes depending on which parameters are given:
1. **amplitude + flatTime** (+ optional riseTime/fallTime)
2. **flatArea + flatTime** (computes amplitude)
3. **area** (+ optional duration; computes optimal shape)

### `makeExtendedTrapezoid`

```nim
proc makeExtendedTrapezoid*(
    channel: string,
    amplitudes: seq[float64] = @[],
    times: seq[float64] = @[],
    skipCheck: bool = false,
    system: Opts = defaultOpts(),
): Event
```

Creates an extended trapezoid (arbitrary piecewise-linear gradient) from explicit time-amplitude pairs.

### `makeExtendedTrapezoidArea`

```nim
proc makeExtendedTrapezoidArea*(
    channel: string,
    area: float64,
    gradStart: float64,
    gradEnd: float64,
    system: Opts = defaultOpts(),
): tuple[grad: Event, times: seq[float64], amplitudes: seq[float64]]
```

Creates an extended trapezoid that achieves a specified area while connecting given start and end amplitudes.

### `makeArbitraryGrad`

```nim
proc makeArbitraryGrad*(
    channel: string,
    waveform: seq[float64],        # Gradient waveform samples (Hz/m)
    first: float64 = NaN,
    last: float64 = NaN,
    delay: float64 = 0.0,
    maxGrad: float64 = 0.0,
    maxSlew: float64 = 0.0,
    system: Opts = defaultOpts(),
    oversampling: bool = false,
): Event
```

Creates an arbitrary gradient from a waveform array.

### `makeAdc`

```nim
proc makeAdc*(
    numSamples: int,
    delay: float64 = 0.0,
    duration: float64 = 0.0,       # Specify duration or dwell, not both
    dwell: float64 = 0.0,
    freqOffset: float64 = 0.0,
    phaseOffset: float64 = 0.0,
    system: Opts = defaultOpts(),
    freqPpm: float64 = 0.0,
    phasePpm: float64 = 0.0,
): Event
```

Creates an ADC readout event.

### `makeDelay`

```nim
proc makeDelay*(d: float64): Event
```

Creates a simple delay event.

### `makeLabel`

```nim
proc makeLabel*(
    labelType: string,   # "SET" or "INC"
    label: string,       # Label name (e.g. "LIN", "PAR", "SLC")
    value: int,          # Label value
): Event
```

Creates a label event for ADC labeling. Valid label names are listed in `supportedLabels`.

### `makeTrigger`

```nim
proc makeTrigger*(
    channel: string,               # "physio1" or "physio2"
    delay: float64 = 0.0,
    duration: float64 = 0.0,
    system: Opts = defaultOpts(),
): Event
```

Creates a synchronization trigger event.

### `makeDigitalOutputPulse`

```nim
proc makeDigitalOutputPulse*(
    channel: string,               # "osc0", "osc1", or "ext1"
    delay: float64 = 0.0,
    duration: float64 = 4e-3,
    system: Opts = defaultOpts(),
): Event
```

Creates a digital output pulse event.

---

## Gradient Manipulation Functions

### `scaleGrad`

```nim
proc scaleGrad*(
    grad: Event,
    scale: float64,
    system: Opts = defaultOpts(),
): Event
```

Scales a gradient's amplitude by the given factor. Works for both trapezoid and arbitrary gradients. Returns a new event.

After scaling, validates hardware constraints:
- **Amplitude**: raises `ValueError` ("maximum amplitude exceeded") if the scaled amplitude exceeds `system.maxGrad`
- **Slew rate**: raises `ValueError` ("maximum slew rate exceeded") if the slew rate (computed from amplitude/rise_time for trapezoids, or from waveform differences for arbitrary gradients) exceeds `system.maxSlew`

### `addGradients`

```nim
proc addGradients*(
    grads: seq[Event],
    system: Opts = defaultOpts(),
    maxGrad: float64 = 0.0,
    maxSlew: float64 = 0.0,
): Event
```

Returns the superposition (sum) of multiple gradients. Handles trapezoids, extended trapezoids, and mixed types. When all inputs are trapezoids with identical timing, returns a trapezoid; otherwise returns an extended trapezoid.

### `splitGradientAt`

```nim
proc splitGradientAt*(
    grad: Event,
    timePoint: float64,
    system: Opts = defaultOpts(),
): tuple[grad1: Event, grad2: Event]
```

Splits a gradient at the given time point into two extended trapezoid events.

### `rotate`

```nim
proc rotate*(
    events: seq[Event],
    angle: float64,                # Rotation angle (rad)
    axis: string,                  # Rotation axis: "x", "y", or "z"
    system: Opts = defaultOpts(),
): seq[Event]
```

Rotates gradient events about the specified axis. Non-gradient events (ADC, delay, etc.) are passed through unchanged.

### `alignEvents`

```nim
proc alignEvents*(
    spec: AlignSpec,               # asLeft, asCenter, or asRight
    events: seq[Event],
): seq[Event]
```

Aligns events by adjusting their delays. Returns a new sequence of events.

---

## Calculation Functions

### `calcDuration`

```nim
proc calcDuration*(events: varargs[Event]): float64
```

Returns the maximum duration across all given events. Works for all event types.

### `calcRfCenter`

```nim
proc calcRfCenter*(rf: Event): tuple[timeCenter: float64, idCenter: int]
```

Calculates the temporal center of an RF pulse (the point of maximum magnitude).

---

## Utility Functions

### `newOpts`

```nim
proc newOpts*(
    maxGrad: float64 = 0.0, gradUnit: string = "Hz/m",
    maxSlew: float64 = 0.0, slewUnit: string = "Hz/m/s",
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
): Opts
```

Creates scanner hardware limits. Gradient units can be `"Hz/m"`, `"mT/m"`, or `"rad/ms/mm"`. Slew units can be `"Hz/m/s"`, `"mT/m/ms"`, `"T/m/s"`, or `"rad/ms/mm/ms"`. Parameters set to `-1.0` use defaults.

### `roundHalfUp`

```nim
proc roundHalfUp*(n: float64, decimals: int = 0): float64
```

Python-compatible rounding: 0.5 rounds up (not to even).

### `parseChannel`

```nim
proc parseChannel*(ch: string): GradChannel
```

Converts `"x"`, `"y"`, `"z"` to the corresponding `GradChannel` enum value.

### `formatG`

```nim
proc formatG*(v: float64, precision: int = 6): string
```

Formats a float using Python's `%g` convention: significant digits, strip trailing zeros, scientific notation for very large/small values.

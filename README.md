# NimPulseq

A Nim port of [PyPulseq](https://github.com/imr-framework/pypulseq) for vendor-neutral MRI pulse sequence design. NimPulseq generates `.seq` files in the [Pulseq](https://pulseq.github.io/) v1.5.0 format, compatible with **Siemens**, **GE**, **Bruker**, and **Philips** MRI scanners.

## Overview

NimPulseq is a direct, API-compatible port of PyPulseq to the Nim programming language. It implements the complete sequence generation pipeline — event creation, block assembly, timing validation, and `.seq` file writing — producing output that is byte-identical to PyPulseq for all included example sequences.

The library consists of 27 source modules and ships with 12 example pulse sequences and a comprehensive test suite of 1052 automated tests.

## Getting Started

### Requirements

- [Nim](https://nim-lang.org/) >= 1.6

### Compilation

```bash
nim c -r examples/write_gre.nim
```

This compiles and runs the GRE example, producing a `gre_nim.seq` file.

### Minimal Example

```nim
import std/math
import nimpulseq

let system = newOpts(
  maxGrad = 28, gradUnit = "mT/m",
  maxSlew = 150, slewUnit = "T/m/s",
  rfRingdownTime = 20e-6,
  rfDeadTime = 100e-6,
  adcDeadTime = 10e-6,
)
var seqObj = newSequence(system)

# Create a sinc RF pulse with slice-select gradient
var (rf, gz, _) = makeSincPulse(
  flipAngle = PI / 2.0,
  duration = 3e-3,
  sliceThickness = 3e-3,
  apodization = 0.5,
  timeBwProduct = 4.0,
  system = system,
  returnGz = true,
  delay = system.rfDeadTime,
  use = "excitation",
)

# Create readout gradient and ADC
let gx = makeTrapezoid(channel = "x", flatArea = 16384.0, flatTime = 3.2e-3, system = system)
let adc = makeAdc(numSamples = 64, duration = gx.trapFlatTime, delay = gx.trapRiseTime, system = system)

# Assemble blocks
seqObj.addBlock(rf, gz)
seqObj.addBlock(gx, adc)

# Validate and write
let (ok, _) = seqObj.checkTiming()
assert ok
seqObj.writeSeq("my_sequence.seq", createSignature = true)
```

## Example Sequences

The `examples/` directory contains 12 complete pulse sequence implementations, all ported from PyPulseq:

| Example | Description |
|---------|-------------|
| `write_gre.nim` | Gradient-recalled echo |
| `write_gre_label.nim` | GRE with ADC labeling |
| `write_epi.nim` | Echo-planar imaging |
| `write_epi_se.nim` | Spin-echo EPI |
| `write_epi_se_rs.nim` | Spin-echo EPI with ramp sampling |
| `write_epi_label.nim` | EPI with ADC labeling |
| `write_haste.nim` | Half-Fourier single-shot TSE |
| `write_tse.nim` | Turbo spin echo |
| `write_mprage.nim` | Magnetization-prepared rapid gradient echo |
| `write_radial_gre.nim` | Radial GRE |
| `write_ute.nim` | Ultrashort echo time |
| `write_gre_label_softdelay.nim` | GRE with labels and soft delays |

Run any example with:

```bash
cd nimpulseq
nim c -r examples/write_haste.nim
```

## API

NimPulseq follows the same design pattern as PyPulseq:

```
Opts (scanner limits) -> make_*(...) -> Event objects -> Sequence.addBlock(*events) -> .seq file
```

Events within the same `addBlock()` call execute simultaneously. The `Sequence` object manages event libraries that deduplicate identical events by content.

### Event Creation

| Function | Description |
|----------|-------------|
| `makeSincPulse` | Sinc RF pulse (with optional slice-select gradient) |
| `makeBlockPulse` | Rectangular (hard) RF pulse |
| `makeGaussPulse` | Gaussian RF pulse |
| `makeAdiabaticPulse` | Adiabatic inversion pulse (hypsec) |
| `makeTrapezoid` | Trapezoidal gradient |
| `makeExtendedTrapezoid` | Piecewise-linear arbitrary gradient |
| `makeExtendedTrapezoidArea` | Extended trapezoid from target area |
| `makeArbitraryGrad` | Arbitrary gradient from waveform array |
| `makeAdc` | ADC readout event |
| `makeDelay` | Simple delay |
| `makeLabel` | ADC label (SET/INC) |
| `makeTrigger` | Synchronization trigger |
| `makeDigitalOutputPulse` | Digital output pulse |
| `makeSoftDelay` | Soft delay (runtime-adjustable block duration) |

### Gradient Operations

| Function | Description |
|----------|-------------|
| `scaleGrad` | Scale gradient amplitude (with limit validation) |
| `addGradients` | Superposition of multiple gradients |
| `splitGradientAt` | Split gradient at a time point |
| `rotate` | Rotate gradients about an axis |
| `alignEvents` | Align events (left, center, right) |

### Sequence Methods

| Method | Description |
|--------|-------------|
| `addBlock` | Append a block of simultaneous events |
| `checkTiming` | Comprehensive timing validation |
| `writeSeq` | Write `.seq` file |
| `setDefinition` | Set sequence header definitions |
| `registerGradEvent` | Pre-register gradient for ID ordering |
| `totalDuration` | Total sequence duration |
| `applySoftDelay` | Apply runtime delay values to soft delay blocks |

For complete API documentation, see [API.md](API.md). For a guide on converting PyPulseq scripts to NimPulseq, see [PORTING_GUIDE.md](PORTING_GUIDE.md).

## Tests

The test suite is ported from PyPulseq and covers all implemented functionality:

```bash
cd nimpulseq
bash tests/run_tests.sh
```

| Test | Count | Description |
|------|-------|-------------|
| test_calc_duration | 816 | Duration calculation for all event types |
| test_make_trapezoid | 19 | Trapezoid creation and error handling |
| test_make_block_pulse | 10 | Block pulse creation and validation |
| test_make_gauss_pulse | 8 | Gaussian pulse creation |
| test_make_adiabatic_pulse | 14 | Adiabatic pulse creation |
| test_make_extended_trapezoid_area | 134 | Extended trapezoid area calculations |
| test_scale_grad | 17 | Gradient scaling with limit checks |
| test_block | 11 | Block assembly and gradient continuity |
| test_check_timing | 1 | Timing validation |
| test_sequence | 24 | End-to-end `.seq` file comparison against PyPulseq |
| **Total** | **1054** | |

The `test_sequence` tests generate `.seq` files and compare them line-by-line against reference output produced by PyPulseq.

## Project Structure

```
nimpulseq/
  src/           # 27 library modules
  examples/      # 12 example pulse sequences + STYLE_GUIDE.md
  tests/         # 10 test files + runner script
API.md           # Complete API reference
PORTING_GUIDE.md # PyPulseq-to-NimPulseq conversion guide
```

## Differences from PyPulseq

NimPulseq implements the complete **sequence generation** pipeline. The following PyPulseq features are not implemented as they are not needed for `.seq` file generation:

- Visualization (plotting)
- Analysis (k-space calculation, gradient spectra, PNS)
- File reading (parsing `.seq` files)
- Scanner deployment
- SigPy integration

For a detailed implementation status, see the [Porting Guide](PORTING_GUIDE.md#7-implementation-status).

## Citation

If you use NimPulseq in your research, please cite the original PyPulseq paper:

> Ravi, Keerthi, Sairam Geethanath, and John Vaughan. "PyPulseq: A Python Package for MRI Pulse Sequence Design." *Journal of Open Source Software* 4.42 (2019): 1725.

## License

NimPulseq is released under the [MIT License](LICENSE).

## Details

The current version is based on [commit 75f2c27 of PyPulseq](https://github.com/imr-framework/pypulseq/commit/75f2c27) 2026-02-21

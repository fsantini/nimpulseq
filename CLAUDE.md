# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NimPulseq is a Nim port of [PyPulseq](https://github.com/imr-framework/pypulseq), a vendor-neutral MRI pulse sequence design library. It generates `.seq` files in Pulseq v1.5.0 format, compatible with Siemens, GE, Bruker, and Philips MRI scanners. All 11 example sequences produce byte-identical output to PyPulseq.

Requires Nim >= 2.0.0. No external dependencies.

## Commands

**Run all tests:**
```sh
bash tests/run_tests.sh
```

**Run a single test file:**
```sh
nim c -r tests/test_make_trapezoid.nim
nim c -r tests/test_sequence.nim
```

**Compile and run an example:**
```sh
nim c -r examples/write_gre.nim
```

## Architecture

### Module Layout

All source lives in `src/nimpulseq/`. The top-level `src/nimpulseq.nim` exports everything.

**Core types** (`types.nim`):
- `Event`: Discriminated union over all event kinds (RF, trapezoid, arbitrary gradient, ADC, delay, label, trigger, output). The `kind: EventKind` field selects the active branch.
- `Opts`: Scanner hardware limits (maxGrad, maxSlew, raster times, dead times). Values are stored in Hz/m and Hz/m/s internally; `opts.nim` provides unit conversion.
- `Sequence`: Holds 9 `EventLibrary` instances (content-addressable, deduplicating), plus maps from block ID → event IDs, durations, and event objects.
- `EventLibrary`: Maps `seq[float64]` content → unique integer ID; identical waveforms share one ID.

**Event creation** (`make_*.nim` — one file per event type):
- RF pulses: `makeSincPulse`, `makeBlockPulse`, `makeGaussPulse`, `makeAdiabaticPulse`
- Gradients: `makeTrapezoid`, `makeExtendedTrapezoid`, `makeExtendedTrapezoidArea`, `makeArbitraryGrad`
- Other: `makeAdc`, `makeDelay`, `makeLabel`, `makeTrigger`

**Gradient operations**: `scale_grad`, `add_gradients`, `split_gradient_at`, `rotate`, `align`

**Sequence assembly**:
- `addBlock()` in `blocks.nim` appends simultaneous events to the sequence; it also handles RF/gradient event registration with shape compression.
- `checkTiming()` in `check_timing.nim` validates RF/gradient continuity, dead times, and block duration raster alignment.
- `writeSeq()` in `write_seq.nim` serializes to Pulseq v1.5.0 format, including a custom `formatG()` that replicates Python's `{:g}` float formatting and MD5 signature generation.

### Typical Usage Pattern

```nim
let system = newOpts(maxGrad = 28, gradUnit = "mT/m", maxSlew = 150, slewUnit = "T/m/s",
                     rfRingdownTime = 20e-6, rfDeadTime = 100e-6, adcDeadTime = 10e-6)
var seqObj = newSequence(system)

var (rf, gz, _) = makeSincPulse(...)
let gx = makeTrapezoid(...)
let adc = makeAdc(...)

seqObj.addBlock(rf, gz)
seqObj.addBlock(gx, adc)

let (ok, _) = seqObj.checkTiming()
seqObj.writeSeq("output.seq", createSignature = true)
```

### Tests

`tests/test_sequence.nim` performs end-to-end validation: it runs each example sequence and compares the resulting `.seq` file against a reference in `tests/expected_output/`. The comparison skips the file header and starts from the `[VERSION]` section, which is located dynamically (not assumed to be at a fixed line number).

## Documentation

- `API.md`: Complete function signatures and parameters
- `PORTING_GUIDE.md`: PyPulseq-to-NimPulseq conversion guide with examples
- `README.md`: Project overview and example table

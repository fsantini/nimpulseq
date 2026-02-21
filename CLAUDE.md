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
- `docs/`: Sphinx documentation source (builds to HTML via ReadTheDocs)

### Keeping documentation in sync

**Always apply all three steps below when modifying or adding exported symbols.**

#### 1. Docstrings in source (`src/`)

Every exported symbol — procs, types, consts, enum variants, and type fields — must have a `##` docstring. Docstrings are written in RST markup (Nim parses them that way).

- **New proc**: add a `## ...` block immediately after the signature, before the first statement. Describe purpose, all parameters, return value, and any exceptions raised.
- **Modified proc**: update the docstring to reflect changed parameters, semantics, or constraints.
- **New type or field**: add `## ...` inline on the same line or as the first line of the object body.
- **Removed symbol**: no action needed for the docstring itself, but update the docs below.

#### 2. Regenerate the Sphinx RST files

The `docs/api/` directory is generated — never edit files there by hand.

```sh
# From the repo root (requires Nim in PATH):
python docs/generate_rst.py
```

Run this after every change to exported symbols. The script calls `nim jsondoc` on each source module and converts the JSON output to RST under `docs/api/`.

To verify the HTML builds correctly:

```sh
# Activate the venv first (created once with: python3 -m venv docs/.venv && docs/.venv/bin/pip install -r docs/requirements.txt)
LC_ALL=C.UTF-8 docs/.venv/bin/sphinx-build -T -b html docs/ docs/_build/html
```

Or using the Makefile (runs both steps):

```sh
make -C docs html
```

#### 3. Update the narrative docs when features change

Some documentation is hand-maintained and must be kept in sync manually:

| File | Update when… |
|------|-------------|
| `docs/porting.rst` — *Not Implemented* section | A previously missing PyPulseq feature is added, or a new deliberate omission is introduced. Keep the bullet list accurate. |
| `docs/porting.rst` — naming/unit tables | A new `make_*` function or gradient operation is added. Add a row to the relevant table. |
| `docs/quickstart.rst` — example sequence table | A new example is added to `examples/`. Add a row. |
| `README.md` — API tables | A new public function or method is added. Add a row to the relevant table. |
| `API.md` | New or changed function signatures. Update the entry. |
| `docs/generate_rst.py` — `MODULES` list | A new source file is added under `src/nimpulseq/`. Append a `(module_name, path, title)` tuple to `MODULES`. |

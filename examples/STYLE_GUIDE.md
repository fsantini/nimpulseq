# Example Script Style Guide (Nim)

This document describes the conventions and coding style for NimPulseq example scripts.
It serves as a reference for contributors writing new examples or refactoring existing ones.

This guide is adapted from the [PyPulseq style guide](../../pypulseq/examples/scripts/STYLE_GUIDE.md)
with changes for Nim language conventions.

For a minimal reference implementation, see `write_gre.nim`.
For a more advanced example, see `write_gre_label_softdelay.nim`.

---

## General Rules

- Follow **Nim naming conventions**: use `camelCase` for all variable and procedure names.
- Use **descriptive variable names** that convey meaning (e.g., `readoutDuration` instead of `roDur`).
- Use the **`n` prefix** (camelCase) for all variables describing a count or number of something
  (e.g., `nX`, `nY`, `nSlices`, `nEcho`, `nSpokes`).
- Variables derived from or related to another variable should **start with the referring
  variable name** (e.g., `teDelay`, `teMin`, `trDelay`, `adcDuration`, `gxFlatTime`).
- Use `degToRad()` from `std/math` for flip angle conversions, not manual `* PI / 180`.
- Import NimPulseq consistently as `import nimpulseq`.

---

## Script Structure

Every example script should follow this structure:

### 1. Imports

```nim
import std/math
import nimpulseq
```

Standard library imports first (`std/math`, `std/strutils`, etc.), then NimPulseq.

### 2. Proc Signature

All sequence logic lives inside a named `proc` that returns `Sequence`. The proc:

- Is exported with `*`
- Takes no arguments (uses hardcoded default parameters matching PyPulseq defaults)
- Returns `Sequence`

```nim
proc writeGreSeq*(): Sequence =
```

### 3. Body Order

Inside the proc, follow this general order:

1. **Setup** — declare parameters (`fov`, `nX`, `nY`, etc.)
2. **System limits** — create `system = newOpts(...)`.
3. **Sequence object** — create `var seqObj = newSequence(system)`.
4. **Create events** — RF pulses, gradients, ADC, delays.
5. **Calculate timing** — compute delays, round to raster time.
6. **Construct sequence** — loop over slices/phase encodes, add blocks.
7. **Check timing** — call `seqObj.checkTiming()` and print result.
8. **Set definitions** — call `seqObj.setDefinition()` (always, unconditionally).
9. **Return** — `result = seqObj`.

### 4. `when isMainModule` Block

```nim
when isMainModule:
  let seqObj = writeGreSeq()
  seqObj.writeSeq("gre_nim.seq", createSignature = true)
```

---

## Naming Conventions

### Common Variable Names

| Nim Variable | Description |
|---|---|
| `seqObj` | Sequence object (`Sequence`) |
| `system` | System limits object (`Opts`) |
| `rf` | RF excitation pulse |
| `rfRef` | RF refocusing pulse |
| `rfPrep` | RF preparation/inversion pulse |
| `gz` | Slice selection gradient |
| `gzReph` | Slice rephasing gradient |
| `gx` | Readout gradient |
| `gxPre` | Readout prephaser gradient |
| `gxSpoil` | Readout spoiler gradient |
| `gzSpoil` | Slice spoiler gradient |
| `adc` | ADC readout event |
| `deltaKx` | k-space step size in readout direction (`1 / fov`) |
| `deltaKy` | k-space step size in phase encoding direction (`1 / fov`) |
| `deltaKz` | k-space step size in partition/slice direction (3D only) |
| `phaseAreas` | Sequence of phase encoding areas |

### Count Variables

| Convention | Example | Avoid |
|---|---|---|
| `n` prefix, camelCase | `nX`, `nY`, `nSlices`, `nEcho` | `Nx`, `Ny`, `nSlices` (snake_case) |
| Descriptive names | `flipAngleDeg`, `readoutDuration` | `alpha`, `roDur` |

### Derived / Timing Variables

| Variable | Description |
|---|---|
| `teDelay` | Delay to achieve desired TE |
| `teMin` | Minimum achievable TE |
| `trDelay` | Delay to achieve desired TR |
| `trMin` | Minimum achievable TR |
| `tiDelay` | Delay to achieve desired TI |
| `adcDuration` | Duration of the ADC readout |
| `readoutDuration` | Duration of the readout flat-top |

### Loop Variables

| Variable | Description |
|---|---|
| `iPhase` | Phase encoding loop index |
| `iSlice` | Slice loop index |
| `iEcho` | Echo loop index |
| `iExcitation` | Excitation loop index |
| `iPartition` | Partition (3D) loop index |

---

## Field of View and k-Space Steps

For 2D sequences, use a single `fov` variable. For 3D sequences, use a `fov` sequence.

Always use **dimension-specific k-space step variables**:

```nim
let deltaKx = 1.0 / fov
let deltaKy = 1.0 / fov
# For 3D sequences:
let deltaKz = 1.0 / fovZ
```

Use `deltaKx` for readout-related areas and `deltaKy` for phase encoding areas.
Never use a single `deltaK` for both dimensions.

The FOV definition should use the actual values:

```nim
# 2D sequences:
seqObj.setDefinition("FOV", @[fov, fov, sliceThickness])
# 3D sequences:
seqObj.setDefinition("FOV", @[fovX, fovY, fovZ])
```

---

## Timing Calculations

When computing durations that need rounding to the raster time, **either use a single
`ceil(expr / raster) * raster` expression or split into two steps**:

```nim
# Good: two separate steps
var teDelay = te - calcDuration(gxPre) - gz.trapFallTime - gz.trapFlatTime / 2.0 - calcDuration(gx) / 2.0
teDelay = ceil(teDelay / seqObj.gradRasterTime) * seqObj.gradRasterTime

# Also acceptable: single expression with ceil (useful when result is const)
let teDelay = ceil(
  (te - calcDuration(gxPre) - gz.trapFallTime - gz.trapFlatTime / 2.0 - calcDuration(gx) / 2.0) /
  seqObj.gradRasterTime
) * seqObj.gradRasterTime
```

Note: In Nim, multi-line binary expressions require the operator at the **end** of the line
(not at the start of the continuation line):

```nim
# Correct: operator at end of line
let teDelay = ceil(
  (te - calcDuration(gxPre)) /
  seqObj.gradRasterTime
) * seqObj.gradRasterTime

# Wrong: operator at start of next line (parse error)
let teDelay = ceil(
  (te - calcDuration(gxPre))
  / seqObj.gradRasterTime    # ERROR
) * seqObj.gradRasterTime
```

---

## Things to Avoid

- **No section banner comments** like `# ====== SETUP ======`. Nim conventions prefer inline
  comments where needed.
- **No single-letter variable names** (except loop counters like `i`, `j`, `s`, `c`).
- **No uppercase variable names** for sequence parameters (e.g., use `te`, not `TE`).
- **No conditional `setDefinition`** — always set FOV and Name definitions inside the proc,
  not only in `when isMainModule` or inside `if writeSeq`.

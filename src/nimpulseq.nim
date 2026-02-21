import std/[tables, math]
import nimpulseq/types
export types

import nimpulseq/opts
export opts

import nimpulseq/event_lib
export event_lib

import nimpulseq/calc_duration
export calc_duration

import nimpulseq/compress
export compress

import nimpulseq/make_trap
export make_trap

import nimpulseq/make_sinc
export make_sinc

import nimpulseq/make_adc
export make_adc

import nimpulseq/make_delay
export make_delay

import nimpulseq/make_label
export make_label

import nimpulseq/make_soft_delay
export make_soft_delay

import nimpulseq/calc_rf_center
export calc_rf_center

import nimpulseq/make_block_pulse
export make_block_pulse

import nimpulseq/make_trigger
export make_trigger

import nimpulseq/make_gauss_pulse
export make_gauss_pulse

import nimpulseq/make_extended_trapezoid
export make_extended_trapezoid

import nimpulseq/make_extended_trapezoid_area
export make_extended_trapezoid_area

import nimpulseq/make_arbitrary_grad
export make_arbitrary_grad

import nimpulseq/make_adiabatic_pulse
export make_adiabatic_pulse

import nimpulseq/split_gradient_at
export split_gradient_at

import nimpulseq/scale_grad
export scale_grad

import nimpulseq/add_gradients
export add_gradients

import nimpulseq/align
export align

import nimpulseq/rotate
export rotate

import nimpulseq/blocks
export blocks

import nimpulseq/check_timing
export check_timing

import nimpulseq/write_seq
export write_seq

proc setDefinition*(seq_obj: Sequence, key: string, value: seq[string]) =
  ## Sets a sequence definition entry to a list of string values.
  ## Definitions are written to the `[DEFINITIONS]` section of the `.seq` file.
  seq_obj.definitions[key] = value

proc setDefinition*(seq_obj: Sequence, key: string, value: string) =
  ## Sets a sequence definition entry to a single string value.
  seq_obj.definitions[key] = @[value]

proc setDefinition*(seq_obj: Sequence, key: string, value: seq[float64]) =
  ## Sets a sequence definition entry from a list of floats,
  ## formatted with 9 significant digits using `{:g}`-style notation.
  var strs: seq[string] = @[]
  for v in value:
    strs.add(formatG(v, 9))
  seq_obj.definitions[key] = strs

proc totalDuration*(seq_obj: Sequence): float64 =
  ## Returns the total duration of all blocks in the sequence (s).
  result = 0.0
  for _, d in seq_obj.blockDurations:
    result += d

proc newSequence*(system: Opts = defaultOpts()): Sequence =
  ## Creates a new, empty `Sequence` object configured for the given scanner limits.
  ## Initialises all event libraries and writes the standard raster-time definitions.
  result = Sequence(
    adcLibrary: newEventLibrary(),
    delayLibrary: newEventLibrary(),
    extensionsLibrary: newEventLibrary(),
    gradLibrary: newEventLibrary(),
    labelIncLibrary: newEventLibrary(),
    labelSetLibrary: newEventLibrary(),
    rfLibrary: newEventLibrary(),
    shapeLibrary: newEventLibrary(),
    triggerLibrary: newEventLibrary(),
    system: system,
    blockEvents: initOrderedTable[int, seq[int32]](),
    nextFreeBlockID: 1,
    definitions: initOrderedTable[string, seq[string]](),
    rfRasterTime: system.rfRasterTime,
    gradRasterTime: system.gradRasterTime,
    adcRasterTime: system.adcRasterTime,
    blockDurationRaster: system.blockDurationRaster,
    blockDurations: initTable[int, float64](),
    blockEventObjects: initTable[int, seq[Event]](),
    gradLastAmps: [0.0, 0.0, 0.0],
    extensionNumericIdx: @[],
    extensionStringIdx: @[],
    versionMajor: 1,
    versionMinor: 5,
    versionRevision: "0",
    softDelayData: initOrderedTable[int, tuple[numID: int; offset: float64; factor: float64; hint: string]](),
    softDelayHints: initTable[string, int](),
    nextFreeSoftDelayID: 1,
  )

  # Set default definitions
  result.setDefinition("AdcRasterTime", @[formatG(system.adcRasterTime, 9)])
  result.setDefinition("BlockDurationRaster", @[formatG(system.blockDurationRaster, 9)])
  result.setDefinition("GradientRasterTime", @[formatG(system.gradRasterTime, 9)])
  result.setDefinition("RadiofrequencyRasterTime", @[formatG(system.rfRasterTime, 9)])

proc applySoftDelay*(seq_obj: Sequence, delays: Table[string, float64]) =
  ## Updates block durations for all blocks containing a soft delay event.
  ##
  ## For each block with a soft delay whose hint is a key in `delays`, the new
  ## duration is computed as ``round((delays[hint] / factor + offset) / raster) * raster``.
  ## Raises `ValueError` if a duration would be negative, if numID/hint consistency
  ## is violated, or if a key in `delays` is not present in the sequence.
  var seenHints: Table[string, int]   # hint → numID
  var seenNumIDs: Table[int, string]  # numID → hint

  for blockID, events in seq_obj.blockEventObjects:
    for event in events:
      if event.kind != ekSoftDelay:
        continue
      let hint = event.sdHint
      let numID = seq_obj.softDelayHints.getOrDefault(hint, -1)

      # Consistency checks
      if hint in seenHints:
        if seenHints[hint] != numID:
          raise newException(ValueError,
            "Soft delay in block " & $blockID & " with hint '" & hint &
            "' has inconsistent numID.")
      else:
        seenHints[hint] = numID

      if numID in seenNumIDs:
        if seenNumIDs[numID] != hint:
          raise newException(ValueError,
            "Soft delay in block " & $blockID & " with numID " & $numID &
            " has inconsistent hint.")
      else:
        seenNumIDs[numID] = hint

      if hint in delays:
        let newDurRaw = delays[hint] / event.sdFactor + event.sdOffset
        let newDur = round(newDurRaw / seq_obj.blockDurationRaster) * seq_obj.blockDurationRaster
        if newDur < 0.0:
          raise newException(ValueError,
            "Soft delay '" & hint & "' in block " & $blockID &
            ": calculated duration is negative.")
        seq_obj.blockDurations[blockID] = newDur

  # Check that all specified hints exist in the sequence
  for hint in delays.keys:
    if hint notin seenHints:
      var available: seq[string] = @[]
      for k in seenHints.keys:
        available.add(k)
      raise newException(ValueError,
        "Soft delay '" & hint & "' not found in sequence. Available: " & $available)

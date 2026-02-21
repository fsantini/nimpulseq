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
  )

  # Set default definitions
  result.setDefinition("AdcRasterTime", @[formatG(system.adcRasterTime, 9)])
  result.setDefinition("BlockDurationRaster", @[formatG(system.blockDurationRaster, 9)])
  result.setDefinition("GradientRasterTime", @[formatG(system.gradRasterTime, 9)])
  result.setDefinition("RadiofrequencyRasterTime", @[formatG(system.rfRasterTime, 9)])

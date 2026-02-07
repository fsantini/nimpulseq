import std/[tables, math]
import types
export types

import opts
export opts

import event_lib
export event_lib

import calc_duration
export calc_duration

import compress
export compress

import make_trap
export make_trap

import make_sinc
export make_sinc

import make_adc
export make_adc

import make_delay
export make_delay

import make_label
export make_label

import calc_rf_center
export calc_rf_center

import make_block_pulse
export make_block_pulse

import make_trigger
export make_trigger

import make_gauss_pulse
export make_gauss_pulse

import make_extended_trapezoid
export make_extended_trapezoid

import make_extended_trapezoid_area
export make_extended_trapezoid_area

import make_arbitrary_grad
export make_arbitrary_grad

import make_adiabatic_pulse
export make_adiabatic_pulse

import split_gradient_at
export split_gradient_at

import scale_grad
export scale_grad

import add_gradients
export add_gradients

import align
export align

import rotate
export rotate

import blocks
export blocks

import check_timing
export check_timing

import write_seq
export write_seq

proc setDefinition*(seq_obj: Sequence, key: string, value: seq[string]) =
  seq_obj.definitions[key] = value

proc setDefinition*(seq_obj: Sequence, key: string, value: string) =
  seq_obj.definitions[key] = @[value]

proc setDefinition*(seq_obj: Sequence, key: string, value: seq[float64]) =
  var strs: seq[string] = @[]
  for v in value:
    strs.add(formatG(v, 9))
  seq_obj.definitions[key] = strs

proc totalDuration*(seq_obj: Sequence): float64 =
  result = 0.0
  for _, d in seq_obj.blockDurations:
    result += d

proc newSequence*(system: Opts = defaultOpts()): Sequence =
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

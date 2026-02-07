import std/[tables, strformat, math]
import types

type
  TimingError* = object
    blockIdx*: int
    event*: string
    field*: string
    errorType*: string
    message*: string

proc checkTiming*(seq: Sequence): tuple[ok: bool, errors: seq[TimingError]] =
  ## Basic timing check - verifies block durations align to raster times.
  ## Returns (ok, error_list). Simplified version compared to Python.
  var errors: seq[TimingError] = @[]

  for blockIdx, blockEvent in seq.blockEvents:
    let duration = seq.blockDurations[blockIdx]

    # Check block duration raster
    let c = duration / seq.system.blockDurationRaster
    let cRounded = round(c)
    if abs(c - cRounded) >= 1e-6:
      errors.add(TimingError(
        blockIdx: blockIdx,
        event: "block",
        field: "duration",
        errorType: "RASTER",
        message: &"Block {blockIdx}: duration {duration*1e6:.2f} us does not align to block_duration_raster",
      ))

  result = (errors.len == 0, errors)

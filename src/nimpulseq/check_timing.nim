import std/[tables, strformat, math]
import types

type
  TimingError* = object
    ## Describes a single timing constraint violation found by `checkTiming`.
    blockIdx*: int     ## 1-based index of the block that contains the violation.
    event*: string     ## Event type label, e.g. "rf", "gx", "adc", "delay".
    field*: string     ## Specific field that violated the constraint, e.g. "delay", "duration".
    errorType*: string ## Machine-readable error tag, e.g. "RASTER", "RF_DEAD_TIME".
    message*: string   ## Human-readable description of the violation.

proc divCheck(errors: var seq[TimingError], blockIdx: int, a: float64, b: float64,
              event: string, field: string, raster: string) =
  ## Checks whether `a` can be divided by `b` to an accuracy of 1e-6.
  let c = a / b
  let cRounded = round(c)
  if abs(c - cRounded) >= 1e-6:
    errors.add(TimingError(
      blockIdx: blockIdx,
      event: event,
      field: field,
      errorType: "RASTER",
      message: &"Block {blockIdx}: {event}.{field} = {a*1e6:.2f} us does not align to {raster}",
    ))

proc computeSystemDuration(events: seq[Event], sys: Opts): float64 =
  ## Compute block duration using sequence system opts for dead_time/ringdown_time,
  ## matching Python get_block + calc_duration behavior.
  result = 0.0
  for event in events:
    case event.kind
    of ekRf:
      result = max(result, event.rfDelay + event.rfShapeDur + sys.rfRingdownTime)
    of ekAdc:
      result = max(result, event.adcDelay + float64(event.adcNumSamples) * event.adcDwell + sys.adcDeadTime)
    of ekTrap:
      result = max(result, event.trapDelay + event.trapRiseTime + event.trapFlatTime + event.trapFallTime)
    of ekGrad:
      result = max(result, event.gradDelay + event.gradShapeDur)
    of ekDelay:
      result = max(result, event.delayD)
    of ekTrigger, ekOutput:
      result = max(result, event.trigDelay + event.trigDuration)
    of ekLabelSet, ekLabelInc:
      discard

proc checkTiming*(s: Sequence): tuple[ok: bool, errors: seq[TimingError]] =
  ## Full timing check - verifies block durations, raster alignment,
  ## dead times, ringdown times, and delay signs.
  ## Matches Python ext_check_timing behavior.
  var errors: seq[TimingError] = @[]

  for blockIdx in s.blockEvents.keys:
    let storedDuration = s.blockDurations[blockIdx]

    # Get original events for this block
    let events = s.blockEventObjects.getOrDefault(blockIdx, @[])

    # Compute duration using sequence system opts (matches Python get_block + calc_duration)
    let computedDuration = computeSystemDuration(events, s.system)

    # Check block duration raster
    divCheck(errors, blockIdx, storedDuration, s.system.blockDurationRaster,
             "block", "duration", "block_duration_raster")

    # Check BLOCK_DURATION_MISMATCH
    if abs(computedDuration - storedDuration) > eps:
      errors.add(TimingError(
        blockIdx: blockIdx,
        event: "block",
        field: "duration",
        errorType: "BLOCK_DURATION_MISMATCH",
        message: &"Block {blockIdx}: stored duration {storedDuration*1e6:.2f} us != computed {computedDuration*1e6:.2f} us",
      ))

    # Check each event in the block
    for event in events:
      case event.kind
      of ekRf:
        let raster = s.system.rfRasterTime
        let rasterStr = "rf_raster_time"

        # Check delay negativity
        if event.rfDelay < -eps:
          errors.add(TimingError(
            blockIdx: blockIdx,
            event: "rf",
            field: "delay",
            errorType: "NEGATIVE_DELAY",
            message: &"Block {blockIdx}: rf.delay = {event.rfDelay*1e6:.2f} us is negative",
          ))

        # Check delay raster
        divCheck(errors, blockIdx, event.rfDelay, raster, "rf", "delay", rasterStr)

        # Check RF dead time: delay must be >= dead_time (from sequence system)
        if event.rfDelay - s.system.rfDeadTime < -eps:
          errors.add(TimingError(
            blockIdx: blockIdx,
            event: "rf",
            field: "delay",
            errorType: "RF_DEAD_TIME",
            message: &"Block {blockIdx}: rf.delay {event.rfDelay*1e6:.2f} us < rf_dead_time {s.system.rfDeadTime*1e6:.0f} us",
          ))

        # Check RF ringdown time: delay + t[-1] + ringdown_time must fit in block duration
        let rfEnd = event.rfDelay + event.rfT[^1]
        if rfEnd + s.system.rfRingdownTime - storedDuration > eps:
          errors.add(TimingError(
            blockIdx: blockIdx,
            event: "rf",
            field: "duration",
            errorType: "RF_RINGDOWN_TIME",
            message: &"Block {blockIdx}: rf ends at {rfEnd*1e6:.2f} us + ringdown {s.system.rfRingdownTime*1e6:.0f} us > duration {storedDuration*1e6:.2f} us",
          ))

      of ekAdc:
        # ADC start time must be on RF raster time
        let raster = s.system.rfRasterTime
        let rasterStr = "rf_raster_time"

        # Check delay negativity
        if event.adcDelay < -eps:
          errors.add(TimingError(
            blockIdx: blockIdx,
            event: "adc",
            field: "delay",
            errorType: "NEGATIVE_DELAY",
            message: &"Block {blockIdx}: adc.delay = {event.adcDelay*1e6:.2f} us is negative",
          ))

        # Check delay raster
        divCheck(errors, blockIdx, event.adcDelay, raster, "adc", "delay", rasterStr)

        # Check dwell raster (ADC samples on ADC raster)
        divCheck(errors, blockIdx, event.adcDwell, s.system.adcRasterTime, "adc", "dwell", "adc_raster_time")

        # Check ADC dead time: delay must be >= system adc_dead_time
        if event.adcDelay - s.system.adcDeadTime < -eps:
          errors.add(TimingError(
            blockIdx: blockIdx,
            event: "adc",
            field: "delay",
            errorType: "ADC_DEAD_TIME",
            message: &"Block {blockIdx}: adc.delay {event.adcDelay*1e6:.2f} us < adc_dead_time {s.system.adcDeadTime*1e6:.0f} us",
          ))

        # Check post-ADC dead time: adc end + dead_time must fit in block duration
        let adcEnd = event.adcDelay + float64(event.adcNumSamples) * event.adcDwell + s.system.adcDeadTime
        if adcEnd > storedDuration + eps:
          errors.add(TimingError(
            blockIdx: blockIdx,
            event: "adc",
            field: "duration",
            errorType: "POST_ADC_DEAD_TIME",
            message: &"Block {blockIdx}: adc end + dead_time {adcEnd*1e6:.2f} us > duration {storedDuration*1e6:.2f} us",
          ))

      of ekTrap:
        let raster = s.system.gradRasterTime
        let rasterStr = "grad_raster_time"
        let channelStr = $event.trapChannel

        # Check delay negativity
        if event.trapDelay < -eps:
          errors.add(TimingError(
            blockIdx: blockIdx,
            event: "g" & channelStr,
            field: "delay",
            errorType: "NEGATIVE_DELAY",
            message: &"Block {blockIdx}: g{channelStr}.delay = {event.trapDelay*1e6:.2f} us is negative",
          ))

        # Check delay raster
        divCheck(errors, blockIdx, event.trapDelay, raster, "g" & channelStr, "delay", rasterStr)

        # Check rise_time raster
        divCheck(errors, blockIdx, event.trapRiseTime, raster, "g" & channelStr, "rise_time", rasterStr)

        # Check flat_time raster
        divCheck(errors, blockIdx, event.trapFlatTime, raster, "g" & channelStr, "flat_time", rasterStr)

        # Check fall_time raster
        divCheck(errors, blockIdx, event.trapFallTime, raster, "g" & channelStr, "fall_time", rasterStr)

      of ekGrad:
        let raster = s.system.gradRasterTime
        let rasterStr = "grad_raster_time"
        let channelStr = $event.gradChannel

        # Check delay negativity
        if event.gradDelay < -eps:
          errors.add(TimingError(
            blockIdx: blockIdx,
            event: "g" & channelStr,
            field: "delay",
            errorType: "NEGATIVE_DELAY",
            message: &"Block {blockIdx}: g{channelStr}.delay = {event.gradDelay*1e6:.2f} us is negative",
          ))

        # Check delay raster
        divCheck(errors, blockIdx, event.gradDelay, raster, "g" & channelStr, "delay", rasterStr)

      of ekDelay:
        # Check delay negativity
        if event.delayD < -eps:
          errors.add(TimingError(
            blockIdx: blockIdx,
            event: "delay",
            field: "delay",
            errorType: "NEGATIVE_DELAY",
            message: &"Block {blockIdx}: delay = {event.delayD*1e6:.2f} us is negative",
          ))

      of ekTrigger, ekOutput:
        let raster = s.system.gradRasterTime
        let rasterStr = "grad_raster_time"

        if event.trigDelay < -eps:
          errors.add(TimingError(
            blockIdx: blockIdx,
            event: "trigger",
            field: "delay",
            errorType: "NEGATIVE_DELAY",
            message: &"Block {blockIdx}: trigger.delay = {event.trigDelay*1e6:.2f} us is negative",
          ))

        divCheck(errors, blockIdx, event.trigDelay, raster, "trigger", "delay", rasterStr)
        divCheck(errors, blockIdx, event.trigDuration, raster, "trigger", "duration", rasterStr)

      of ekLabelSet, ekLabelInc:
        discard # Labels have no timing constraints

  result = (errors.len == 0, errors)

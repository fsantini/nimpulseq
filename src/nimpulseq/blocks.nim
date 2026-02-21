import std/[math, complex, tables, algorithm]
import types
import event_lib
import compress

proc registerRfEvent*(seq: Sequence, event: Event): tuple[rfId: int, shapeIDs: seq[int]] =
  ## Compresses the RF waveform (magnitude + phase shapes) and stores it in
  ## the sequence's `rfLibrary` and `shapeLibrary`, deduplicating automatically.
  ## Returns the assigned RF library ID and a 3-element seq of shape IDs
  ## `[magShapeId, phaseShapeId, timeShapeId]`.
  var mag = newSeq[float64](event.rfSignal.len)
  var amplitude = 0.0
  for i in 0 ..< event.rfSignal.len:
    mag[i] = abs(event.rfSignal[i])
    if mag[i] > amplitude:
      amplitude = mag[i]

  for i in 0 ..< mag.len:
    mag[i] = mag[i] / amplitude
    if mag[i] != mag[i]: # NaN check
      mag[i] = 0.0

  var phase = newSeq[float64](event.rfSignal.len)
  for i in 0 ..< event.rfSignal.len:
    var p = arctan2(event.rfSignal[i].im, event.rfSignal[i].re)
    if p < 0:
      p += 2.0 * PI
    phase[i] = p / (2.0 * PI)

  var mayExist = true
  var shapeIDs = @[0, 0, 0]

  # Magnitude shape
  let magShape = compressShape(mag)
  var magData = @[float64(magShape.numSamples)]
  magData.add(magShape.data)
  let (magId, magFound) = seq.shapeLibrary.findOrInsert(magData)
  shapeIDs[0] = magId
  mayExist = mayExist and magFound

  # Phase shape
  let phaseShape = compressShape(phase)
  var phaseData = @[float64(phaseShape.numSamples)]
  phaseData.add(phaseShape.data)
  let (phaseId, phaseFound) = seq.shapeLibrary.findOrInsert(phaseData)
  shapeIDs[1] = phaseId
  mayExist = mayExist and phaseFound

  # Time shape - check if regular
  var tRegular = true
  for i in 0 ..< event.rfT.len:
    let expected = float64(i)
    let actual = floor(event.rfT[i] / seq.rfRasterTime)
    if abs(actual - expected) > 1e-10:
      tRegular = false
      break

  if tRegular:
    shapeIDs[2] = 0
  else:
    var timeArr = newSeq[float64](event.rfT.len)
    for i in 0 ..< event.rfT.len:
      timeArr[i] = event.rfT[i] / seq.rfRasterTime
    let timeShape = compressShape(timeArr)
    var tData = @[float64(timeShape.numSamples)]
    tData.add(timeShape.data)
    let (timeId, timeFound) = seq.shapeLibrary.findOrInsert(tData)
    shapeIDs[2] = timeId
    mayExist = mayExist and timeFound

  var use: char = 'u'
  if event.rfUse in ["excitation", "refocusing", "inversion", "saturation", "preparation"]:
    use = event.rfUse[0]

  let data = @[
    amplitude,
    float64(shapeIDs[0]), float64(shapeIDs[1]), float64(shapeIDs[2]),
    event.rfCenter,
    event.rfDelay,
    event.rfFreqPpm,
    event.rfPhasePpm,
    event.rfFreqOffset,
    event.rfPhaseOffset,
  ]

  var rfId: int
  if mayExist:
    let (id, _) = seq.rfLibrary.findOrInsert(data, use)
    rfId = id
  else:
    rfId = seq.rfLibrary.insert(0, data, use)

  result = (rfId, shapeIDs)

proc registerGradEvent*(seq: Sequence, event: Event): int =
  ## Stores a trapezoid (`ekTrap`) or arbitrary gradient (`ekGrad`) event in
  ## the sequence's `gradLibrary`, deduplicating automatically.
  ## Returns the assigned gradient library ID.
  if event.kind == ekTrap:
    let data = @[
      event.trapAmplitude,
      event.trapRiseTime,
      event.trapFlatTime,
      event.trapFallTime,
      event.trapDelay,
    ]
    let (gradId, _) = seq.gradLibrary.findOrInsert(data, 't')
    return gradId
  elif event.kind == ekGrad:
    var mayExist = true
    var shapeIDs = @[0, 0]

    # Calculate amplitude
    var amplitude = 0.0
    for w in event.gradWaveform:
      if abs(w) > abs(amplitude):
        amplitude = w
    if amplitude == 0.0:
      # Find first non-zero
      for w in event.gradWaveform:
        if w != 0.0:
          amplitude = abs(w) * (if w < 0: -1.0 else: 1.0)
          break

    # Shape for waveform
    var g = newSeq[float64](event.gradWaveform.len)
    if amplitude != 0.0:
      for i in 0 ..< g.len:
        g[i] = event.gradWaveform[i] / amplitude
    else:
      g = event.gradWaveform

    let cShape = compressShape(g)
    var sData = @[float64(cShape.numSamples)]
    sData.add(cShape.data)
    let (shapeId0, found0) = seq.shapeLibrary.findOrInsert(sData)
    shapeIDs[0] = shapeId0
    mayExist = mayExist and found0

    # Shape for timing
    var timeArr = newSeq[float64](event.gradTt.len)
    for i in 0 ..< event.gradTt.len:
      timeArr[i] = event.gradTt[i] / seq.gradRasterTime
    let cTime = compressShape(timeArr)
    var tData = @[float64(cTime.numSamples)]
    tData.add(cTime.data)

    # Check for standard raster
    if cTime.data.len == 4:
      var isStandard = true
      if abs(cTime.data[0] - 0.5) > 1e-6 or abs(cTime.data[1] - 1.0) > 1e-6 or
         abs(cTime.data[2] - 1.0) > 1e-6 or abs(cTime.data[3] - float64(cTime.numSamples - 3)) > 1e-6:
        isStandard = false
      if isStandard:
        shapeIDs[1] = 0  # Standard raster
      else:
        let (tId, tFound) = seq.shapeLibrary.findOrInsert(tData)
        shapeIDs[1] = tId
        mayExist = mayExist and tFound
    elif cTime.data.len == 3:
      var isHalfRaster = true
      if abs(cTime.data[0] - 0.5) > 1e-6 or abs(cTime.data[1] - 0.5) > 1e-6 or
         abs(cTime.data[2] - float64(cTime.numSamples - 2)) > 1e-6:
        isHalfRaster = false
      if isHalfRaster:
        shapeIDs[1] = -1  # Half-raster flag
      else:
        let (tId, tFound) = seq.shapeLibrary.findOrInsert(tData)
        shapeIDs[1] = tId
        mayExist = mayExist and tFound
    else:
      let (tId, tFound) = seq.shapeLibrary.findOrInsert(tData)
      shapeIDs[1] = tId
      mayExist = mayExist and tFound

    # Data layout: amplitude, first, last, shape_id_waveform, shape_id_timing, delay
    let data = @[
      amplitude,
      event.gradFirst,
      event.gradLast,
      float64(shapeIDs[0]),
      float64(shapeIDs[1]),
      event.gradDelay,
    ]

    if mayExist:
      let (gradId, _) = seq.gradLibrary.findOrInsert(data, 'g')
      return gradId
    else:
      return seq.gradLibrary.insert(0, data, 'g')
  else:
    raise newException(ValueError, "Unsupported gradient type")

proc registerAdcEvent*(seq: Sequence, event: Event): tuple[adcId: int, shapeId: int] =
  ## Stores an ADC event in the sequence's `adcLibrary`, deduplicating automatically.
  ## Returns the assigned ADC library ID and the phase modulation shape ID (currently always 0).
  let shapeId = 0 # No phase modulation support for now
  let data = @[
    float64(event.adcNumSamples),
    event.adcDwell,
    max(event.adcDelay, event.adcDeadTime),
    event.adcFreqPpm,
    event.adcPhasePpm,
    event.adcFreqOffset,
    event.adcPhaseOffset,
    float64(shapeId),
    event.adcDeadTime,
  ]
  let (adcId, _) = seq.adcLibrary.findOrInsert(data)
  result = (adcId, shapeId)

proc registerLabelEvent*(seq: Sequence, event: Event): int =
  ## Stores a LABELSET or LABELINC event in the appropriate label library.
  ## Returns the assigned label library ID.
  var labelIdx = -1
  for i, sl in supportedLabels:
    if sl == event.labelName:
      labelIdx = i + 1 # 1-based
      break

  let data = @[float64(event.labelValue), float64(labelIdx)]
  if event.kind == ekLabelSet:
    let (id, _) = seq.labelSetLibrary.findOrInsert(data)
    return id
  else:
    let (id, _) = seq.labelIncLibrary.findOrInsert(data)
    return id

proc registerSoftDelayEvent*(seq: Sequence, event: Event): int =
  ## Assigns a numID to the soft delay (based on hint), then finds or inserts the
  ## ``(numID, offset, factor, hint)`` tuple in the sequence's soft delay store.
  ## Returns the assigned soft delay ID.
  var assignedNumID: int
  if event.sdHint in seq.softDelayHints:
    assignedNumID = seq.softDelayHints[event.sdHint]
    if event.sdNumID >= 0 and event.sdNumID != assignedNumID:
      raise newException(ValueError,
        "Soft delay hint '" & event.sdHint & "' is already assigned to numID " &
        $assignedNumID & ". Cannot use numID " & $event.sdNumID & ".")
  else:
    if event.sdNumID < 0:
      # Auto-assign: next available numID (max of existing + 1)
      var maxNumID = -1
      for v in seq.softDelayHints.values:
        if v > maxNumID:
          maxNumID = v
      assignedNumID = maxNumID + 1
    else:
      # User-provided numID: check it is not already taken by another hint
      for hint, numID in seq.softDelayHints:
        if numID == event.sdNumID:
          raise newException(ValueError,
            "numID " & $event.sdNumID & " is already used by soft delay '" & hint & "'.")
      assignedNumID = event.sdNumID
    seq.softDelayHints[event.sdHint] = assignedNumID

  # Find or insert in softDelayData
  for id, data in seq.softDelayData:
    if data.numID == assignedNumID and
       abs(data.offset - event.sdOffset) < 1e-12 and
       abs(data.factor - event.sdFactor) < 1e-12 and
       data.hint == event.sdHint:
      return id

  let newId = seq.nextFreeSoftDelayID
  seq.softDelayData[newId] = (numID: assignedNumID, offset: event.sdOffset,
                               factor: event.sdFactor, hint: event.sdHint)
  seq.nextFreeSoftDelayID += 1
  return newId

proc registerControlEvent*(seq: Sequence, event: Event): int =
  ## Stores a trigger (`ekTrigger`) or digital output (`ekOutput`) event in `triggerLibrary`.
  ## Returns the assigned trigger library ID.
  ## Raises `ValueError` for unsupported channel names.
  var eventType: int
  var eventChannel: int
  if event.kind == ekOutput:
    eventType = 1  # output = type 1
    case event.trigChannel
    of "osc0": eventChannel = 1
    of "osc1": eventChannel = 2
    of "ext1": eventChannel = 3
    else: raise newException(ValueError, "Invalid output channel: " & event.trigChannel)
  elif event.kind == ekTrigger:
    eventType = 2  # trigger = type 2
    case event.trigChannel
    of "physio1": eventChannel = 1
    of "physio2": eventChannel = 2
    else: raise newException(ValueError, "Invalid trigger channel: " & event.trigChannel)
  else:
    raise newException(ValueError, "Unsupported control event type")

  let data = @[float64(eventType), float64(eventChannel), event.trigDelay, event.trigDuration]
  let (controlId, _) = seq.triggerLibrary.findOrInsert(data)
  return controlId

proc getExtensionTypeID*(seq: Sequence, extensionString: string): int =
  ## Returns the numeric type ID assigned to the extension named `extensionString`
  ## (e.g. "TRIGGERS", "LABELSET", "LABELINC").
  ## If the name has not been seen before, a new ID is allocated and registered.
  for i, s in seq.extensionStringIdx:
    if s == extensionString:
      return seq.extensionNumericIdx[i]

  var extensionId: int
  if seq.extensionNumericIdx.len == 0:
    extensionId = 1
  else:
    extensionId = 1 + max(seq.extensionNumericIdx)

  seq.extensionNumericIdx.add(extensionId)
  seq.extensionStringIdx.add(extensionString)
  return extensionId

proc setBlock*(seq: Sequence, blockIndex: int, events: openArray[Event]) =
  ## Registers a group of simultaneous events as block `blockIndex`.
  ## All events are stored in the appropriate event libraries (deduplicating),
  ## the block duration is computed, and gradient-endpoint continuity is verified.
  ## Raises `ValueError` if gradient continuity is violated across consecutive blocks.
  # Gradient continuity check
  var currFirst: array[3, float64] = [0.0, 0.0, 0.0]
  var currLast: array[3, float64] = [0.0, 0.0, 0.0]
  var hasGrad: array[3, bool] = [false, false, false]
  for event in events:
    if event.kind == ekTrap:
      let ch = channelToIndex(event.trapChannel)
      hasGrad[ch] = true
      currFirst[ch] = 0.0  # traps always start from 0
      currLast[ch] = 0.0   # traps always end at 0
    elif event.kind == ekGrad:
      let ch = channelToIndex(event.gradChannel)
      hasGrad[ch] = true
      if event.gradDelay > 0:
        currFirst[ch] = 0.0
      else:
        currFirst[ch] = event.gradFirst
      currLast[ch] = event.gradLast

  let channels = ["x", "y", "z"]
  for ch in 0 ..< 3:
    let prevLast = seq.gradLastAmps[ch]
    let first = currFirst[ch]
    if abs(prevLast - first) > 1e-9:
      raise newException(ValueError,
        "Gradient continuity violated on channel " & channels[ch] &
        ": previous block ends at " & $prevLast &
        " but current block starts at " & $first)

  # Update last amplitudes for next block
  for ch in 0 ..< 3:
    if hasGrad[ch]:
      seq.gradLastAmps[ch] = currLast[ch]
    else:
      seq.gradLastAmps[ch] = 0.0

  var newBlock = newSeq[int32](7)
  var duration = 0.0
  var extensions: seq[tuple[extType: int, extRef: int]] = @[]

  for event in events:
    case event.kind
    of ekRf:
      let (rfId, _) = seq.registerRfEvent(event)
      newBlock[1] = int32(rfId)
      duration = max(duration, event.rfShapeDur + event.rfDelay + event.rfRingdownTime)
    of ekTrap:
      let channelNum = channelToIndex(event.trapChannel)
      let idx = 2 + channelNum
      let trapId = seq.registerGradEvent(event)
      newBlock[idx] = int32(trapId)
      duration = max(duration, event.trapDelay + event.trapRiseTime + event.trapFlatTime + event.trapFallTime)
    of ekGrad:
      let channelNum = channelToIndex(event.gradChannel)
      let idx = 2 + channelNum
      let gradId = seq.registerGradEvent(event)
      newBlock[idx] = int32(gradId)
      let gradDuration = event.gradDelay + ceil(event.gradTt[^1] / seq.gradRasterTime - 1e-10) * seq.gradRasterTime
      duration = max(duration, gradDuration)
    of ekAdc:
      let (adcId, _) = seq.registerAdcEvent(event)
      newBlock[5] = int32(adcId)
      duration = max(duration, event.adcDelay + float64(event.adcNumSamples) * event.adcDwell + event.adcDeadTime)
    of ekDelay:
      duration = max(duration, event.delayD)
    of ekLabelSet, ekLabelInc:
      let labelId = seq.registerLabelEvent(event)
      let extTypeStr = if event.kind == ekLabelSet: "LABELSET" else: "LABELINC"
      let extType = seq.getExtensionTypeID(extTypeStr)
      extensions.add((extType, labelId))
    of ekTrigger, ekOutput:
      let controlId = seq.registerControlEvent(event)
      let extType = seq.getExtensionTypeID("TRIGGERS")
      extensions.add((extType, controlId))
      duration = max(duration, event.trigDelay + event.trigDuration)
    of ekSoftDelay:
      let softId = seq.registerSoftDelayEvent(event)
      let extType = seq.getExtensionTypeID("DELAYS")
      extensions.add((extType, softId))
      duration = max(duration, event.sdDefaultDuration)

  # Validate soft delay constraints: must be in empty blocks
  var hasSoftDelay = false
  for event in events:
    if event.kind == ekSoftDelay:
      hasSoftDelay = true
      break
  if hasSoftDelay:
    var nSD = 0
    for event in events:
      if event.kind == ekSoftDelay: inc nSD
    if nSD > 1:
      raise newException(ValueError, "Only one soft delay per block is allowed.")
    if newBlock[1] != 0 or newBlock[2] != 0 or newBlock[3] != 0 or
       newBlock[4] != 0 or newBlock[5] != 0:
      raise newException(ValueError,
        "Soft delay extension can only be used in empty blocks (no RF, gradient, or ADC events).")

  # Add extensions (sorted by ref, built as reversed linked list)
  if extensions.len > 0:
    extensions.sort(proc(a, b: tuple[extType: int, extRef: int]): int =
      cmp(a.extRef, b.extRef)
    )

    var allFound = true
    var extensionId = 0
    for i in 0 ..< extensions.len:
      let data = @[float64(extensions[i].extType), float64(extensions[i].extRef), float64(extensionId)]
      let (eid, found) = seq.extensionsLibrary.find(data)
      extensionId = eid
      allFound = allFound and found
      if not found:
        break

    if not allFound:
      extensionId = 0
      for i in 0 ..< extensions.len:
        let data = @[float64(extensions[i].extType), float64(extensions[i].extRef), float64(extensionId)]
        let (eid, found) = seq.extensionsLibrary.find(data)
        extensionId = eid
        if not found:
          discard seq.extensionsLibrary.insert(extensionId, data)

    newBlock[6] = int32(extensionId)

  seq.blockEvents[blockIndex] = newBlock
  seq.blockDurations[blockIndex] = duration
  var eventList: seq[Event] = @[]
  for e in events:
    eventList.add(e)
  seq.blockEventObjects[blockIndex] = eventList

proc addBlock*(seq: Sequence, events: varargs[Event]) =
  ## Appends a new block containing the given events to the sequence.
  ## Events passed as `varargs` execute simultaneously.
  ## Automatically advances the internal block ID counter.
  var eventList: seq[Event] = @[]
  for e in events:
    eventList.add(e)
  seq.setBlock(seq.nextFreeBlockID, eventList)
  seq.nextFreeBlockID += 1

proc addBlock*(seq: Sequence, events: seq[Event]) =
  ## Appends a new block containing the given events to the sequence.
  ## Events in the `seq` execute simultaneously.
  ## Automatically advances the internal block ID counter.
  seq.setBlock(seq.nextFreeBlockID, events)
  seq.nextFreeBlockID += 1

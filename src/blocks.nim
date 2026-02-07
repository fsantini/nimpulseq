import std/[math, complex, tables, algorithm]
import types
import event_lib
import compress

proc registerRfEvent*(seq: Sequence, event: Event): tuple[rfId: int, shapeIDs: seq[int]] =
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
  else:
    raise newException(ValueError, "Only trap gradients supported for now")

proc registerAdcEvent*(seq: Sequence, event: Event): tuple[adcId: int, shapeId: int] =
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

proc getExtensionTypeID*(seq: Sequence, extensionString: string): int =
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
      raise newException(ValueError, "Arbitrary gradients not yet supported")
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
      raise newException(ValueError, "Trigger/Output not yet supported")

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

proc addBlock*(seq: Sequence, events: varargs[Event]) =
  var eventList: seq[Event] = @[]
  for e in events:
    eventList.add(e)
  seq.setBlock(seq.nextFreeBlockID, eventList)
  seq.nextFreeBlockID += 1

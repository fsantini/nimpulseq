import std/[tables, strutils, strformat, math, algorithm, os, md5, sequtils]
import types
import event_lib
import blocks

# =============================================================================
# Custom formatG: Matches Python's {:g} and {:.Ng} formatting
# =============================================================================
proc formatG*(v: float64, precision: int = 6): string =
  ## Formats a float matching Python's %g / {:g} behavior.
  ## precision = number of significant digits (default 6 for {:g}).
  ## Uses fixed notation unless exponent < -4 or >= precision.
  ## Strips trailing zeros. Lowercase 'e' for scientific notation.
  if v == 0.0:
    if copySign(1.0, v) < 0:
      return "-0"
    return "0"

  let isNeg = v < 0
  let absv = abs(v)
  let exponent = floor(log10(absv)).int

  if exponent >= precision or exponent < -4:
    # Scientific notation
    var s = formatFloat(absv, ffScientific, precision - 1)
    # Ensure lowercase 'e'
    s = s.replace("E", "e")
    # Strip trailing zeros after decimal in mantissa
    let ePos = s.find('e')
    if ePos >= 0:
      var mantissa = s[0 ..< ePos]
      let expPart = s[ePos .. ^1]
      if '.' in mantissa:
        mantissa = mantissa.strip(leading = false, chars = {'0'})
        mantissa = mantissa.strip(leading = false, chars = {'.'})
      s = mantissa & expPart
      # Fix exponent formatting: Python uses e+06 (2-digit min), but also e-05
      # Nim's formatFloat should be OK, but let's normalize
      # Python: e+06, e-05, e+100
      let ePlusPos = s.find("e+")
      let eMinusPos = s.find("e-")
      if ePlusPos >= 0:
        let expStr = s[ePlusPos + 2 .. ^1]
        let expVal = parseInt(expStr)
        s = s[0 ..< ePlusPos] & &"e+{expVal:02d}"
      elif eMinusPos >= 0:
        let expStr = s[eMinusPos + 2 .. ^1]
        let expVal = parseInt(expStr)
        s = s[0 ..< eMinusPos] & &"e-{expVal:02d}"
    if isNeg:
      s = "-" & s
    return s
  else:
    # Fixed notation
    let digitsAfterDot = max(0, precision - 1 - exponent)
    var s = formatFloat(absv, ffDecimal, digitsAfterDot)
    # Strip trailing zeros after decimal point
    if '.' in s:
      s = s.strip(leading = false, chars = {'0'})
      s = s.strip(leading = false, chars = {'.'})
    if isNeg:
      s = "-" & s
    return s

proc formatGPadded*(v: float64, precision: int, width: int): string =
  ## Format with {:Ng} padded to width (right-aligned)
  let s = formatG(v, precision)
  if s.len < width:
    result = repeat(' ', width - s.len) & s
  else:
    result = s

proc formatInt*(v: float64): string =
  ## Format as integer ({:.0f})
  $int(round(v))

proc formatIntPadded*(v: int, width: int): string =
  ## Right-align integer to width
  let s = $v
  if s.len < width:
    result = repeat(' ', width - s.len) & s
  else:
    result = s

# =============================================================================
# removeDuplicates
# =============================================================================
proc removeDuplicates*(seq_obj: Sequence): Sequence =
  ## Create a copy of the sequence with duplicate events removed.
  ## This is a simplified deep-copy + dedup approach.

  # Create a new sequence with copies of all libraries
  var copy = Sequence(
    adcLibrary: newEventLibrary(),
    delayLibrary: newEventLibrary(),
    extensionsLibrary: newEventLibrary(),
    gradLibrary: newEventLibrary(),
    labelIncLibrary: newEventLibrary(),
    labelSetLibrary: newEventLibrary(),
    rfLibrary: newEventLibrary(),
    shapeLibrary: newEventLibrary(),
    triggerLibrary: newEventLibrary(),
    system: seq_obj.system,
    blockEvents: initOrderedTable[int, seq[int32]](),
    nextFreeBlockID: seq_obj.nextFreeBlockID,
    definitions: seq_obj.definitions,
    rfRasterTime: seq_obj.rfRasterTime,
    gradRasterTime: seq_obj.gradRasterTime,
    adcRasterTime: seq_obj.adcRasterTime,
    blockDurationRaster: seq_obj.blockDurationRaster,
    blockDurations: initTable[int, float64](),
    extensionNumericIdx: seq_obj.extensionNumericIdx,
    extensionStringIdx: seq_obj.extensionStringIdx,
    versionMajor: seq_obj.versionMajor,
    versionMinor: seq_obj.versionMinor,
    versionRevision: seq_obj.versionRevision,
  )

  # Deep copy all library data
  proc copyLib(src: EventLibrary): EventLibrary =
    result = newEventLibrary()
    for k, v in src.data:
      result.data[k] = v
      if k in src.dataType:
        result.dataType[k] = src.dataType[k]
      result.keymap[v] = k
    result.nextFreeID = src.nextFreeID

  copy.adcLibrary = copyLib(seq_obj.adcLibrary)
  copy.delayLibrary = copyLib(seq_obj.delayLibrary)
  copy.extensionsLibrary = copyLib(seq_obj.extensionsLibrary)
  copy.gradLibrary = copyLib(seq_obj.gradLibrary)
  copy.labelIncLibrary = copyLib(seq_obj.labelIncLibrary)
  copy.labelSetLibrary = copyLib(seq_obj.labelSetLibrary)
  copy.rfLibrary = copyLib(seq_obj.rfLibrary)
  copy.shapeLibrary = copyLib(seq_obj.shapeLibrary)
  copy.triggerLibrary = copyLib(seq_obj.triggerLibrary)

  # Deep copy block_events
  for k, v in seq_obj.blockEvents:
    var newBlock = newSeq[int32](v.len)
    for i in 0 ..< v.len:
      newBlock[i] = v[i]
    copy.blockEvents[k] = newBlock
  for k, v in seq_obj.blockDurations:
    copy.blockDurations[k] = v

  # 1. Shape library dedup
  let (newShapeLib, shapeMapping) = copy.shapeLibrary.removeDuplicatesScalar(9)
  copy.shapeLibrary = newShapeLib

  # 2. Remap shape IDs in grad library (for arbitrary gradients)
  for gradId in toSeq(copy.gradLibrary.data.keys):
    if copy.gradLibrary.dataType.getOrDefault(gradId, '\0') == 'g':
      let data = copy.gradLibrary.data[gradId]
      let newData = @[data[0], data[1], data[2], float64(shapeMapping[int(data[3])]), float64(shapeMapping[int(data[4])]), data[5]]
      if data != newData:
        copy.gradLibrary.update(gradId, newData)

  # 3. Remap shape IDs in RF library
  for rfId in toSeq(copy.rfLibrary.data.keys):
    let data = copy.rfLibrary.data[rfId]
    let newData = @[
      data[0],
      float64(shapeMapping[int(data[1])]),
      float64(shapeMapping[int(data[2])]),
      float64(shapeMapping[int(data[3])]),
      data[4], data[5], data[6], data[7], data[8], data[9],
    ]
    if data != newData:
      copy.rfLibrary.update(rfId, newData)

  # 4. Gradient library dedup
  let gradDigits = @[6, -6, -6, -6, -6, -6]
  let (newGradLib, gradMapping) = copy.gradLibrary.removeDuplicates(gradDigits)
  copy.gradLibrary = newGradLib

  # Remap gradient event IDs in blocks
  for blockId in toSeq(copy.blockEvents.keys):
    copy.blockEvents[blockId][2] = int32(gradMapping[int(copy.blockEvents[blockId][2])])
    copy.blockEvents[blockId][3] = int32(gradMapping[int(copy.blockEvents[blockId][3])])
    copy.blockEvents[blockId][4] = int32(gradMapping[int(copy.blockEvents[blockId][4])])

  # 5. RF library dedup
  let rfDigits = @[6, 0, 0, 0, 6, 6, 6, 6, 6, 6]
  let (newRfLib, rfMapping) = copy.rfLibrary.removeDuplicates(rfDigits)
  copy.rfLibrary = newRfLib

  for blockId in toSeq(copy.blockEvents.keys):
    copy.blockEvents[blockId][1] = int32(rfMapping[int(copy.blockEvents[blockId][1])])

  # 6. ADC library dedup
  let adcDigits = @[0, -9, -6, 6, 6, 6, 6, 6, 6]
  let (newAdcLib, adcMapping) = copy.adcLibrary.removeDuplicates(adcDigits)
  copy.adcLibrary = newAdcLib

  for blockId in toSeq(copy.blockEvents.keys):
    copy.blockEvents[blockId][5] = int32(adcMapping[int(copy.blockEvents[blockId][5])])

  return copy

# =============================================================================
# writeSeq
# =============================================================================
proc writeSeq*(seq_obj: Sequence, fileName: string, createSignature: bool = false, doRemoveDuplicates: bool = true) =
  var fn = fileName
  if not fn.endsWith(".seq"):
    fn = fn & ".seq"

  # Calculate TotalDuration and store in definitions
  var totalDur = 0.0
  for _, d in seq_obj.blockDurations:
    totalDur += d
  seq_obj.definitions["TotalDuration"] = @[formatG(totalDur, 9)]

  var s = seq_obj
  if doRemoveDuplicates:
    s = removeDuplicates(seq_obj)

  var f = open(fn, fmWrite)

  f.write("# Pulseq sequence file\n")
  f.write("# Created by NimPulseq\n\n")

  f.write("[VERSION]\n")
  f.write(&"major {s.versionMajor}\n")
  f.write(&"minor {s.versionMinor}\n")
  f.write(&"revision {s.versionRevision}\n")
  f.write("\n")

  # Definitions
  if s.definitions.len > 0:
    f.write("[DEFINITIONS]\n")
    var keys: seq[string] = @[]
    for k in s.definitions.keys:
      keys.add(k)
    keys.sort()
    for key in keys:
      let vals = s.definitions[key]
      f.write(key & " ")
      for v in vals:
        f.write(v & " ")
      f.write("\n")
    f.write("\n")

  # Blocks
  f.write("# Format of blocks:\n")
  f.write("# NUM DUR RF  GX  GY  GZ  ADC  EXT\n")
  f.write("[BLOCKS]\n")
  let idWidth = ($s.blockEvents.len).len
  for blockCounter, blockEvent in s.blockEvents:
    let blockDuration = s.blockDurations[blockCounter] / s.blockDurationRaster
    let blockDurationRounded = int(round(blockDuration))

    var line = formatIntPadded(blockCounter, idWidth)
    line &= " " & formatIntPadded(blockDurationRounded, 3)
    line &= " " & formatIntPadded(int(blockEvent[1]), 3)
    line &= " " & formatIntPadded(int(blockEvent[2]), 3)
    line &= " " & formatIntPadded(int(blockEvent[3]), 3)
    line &= " " & formatIntPadded(int(blockEvent[4]), 3)
    line &= " " & formatIntPadded(int(blockEvent[5]), 2)
    line &= " " & formatIntPadded(int(blockEvent[6]), 2)
    f.write(line & "\n")
  f.write("\n")

  # RF events
  if s.rfLibrary.data.len > 0:
    f.write("# Format of RF events:\n")
    f.write("# id ampl. mag_id phase_id time_shape_id center delay freqPPm phasePPM freq phase use\n")
    f.write("# ..   Hz      ..       ..            ..     us    us     ppm  rad/MHz   Hz   rad  ..\n")

    var rfUseStr = ""
    for i, u in supportedRfUses:
      if i > 0: rfUseStr &= " "
      rfUseStr &= u
    f.write(&"# Field \"use\" is the initial of: {rfUseStr}\n")
    f.write("[RF]\n")

    for k in toSeq(s.rfLibrary.data.keys):
      let data = s.rfLibrary.data[k]
      let center = data[4] * 1e6 # to us
      let delay = round(data[5] / s.rfRasterTime) * s.rfRasterTime * 1e6 # to us
      # Format: id amplitude mag_id phase_id time_shape_id center delay freqPPM phasePPM freq phase use
      var line = formatInt(float64(k))
      line &= " " & formatGPadded(data[0], 6, 12)
      line &= " " & formatInt(data[1])
      line &= " " & formatInt(data[2])
      line &= " " & formatInt(data[3])
      line &= " " & formatG(center, 6)
      line &= " " & formatG(delay, 6)
      line &= " " & formatG(data[6], 6)  # freqPPM
      line &= " " & formatG(data[7], 6)  # phasePPM
      line &= " " & formatG(data[8], 6)  # freq
      line &= " " & formatG(data[9], 6)  # phase
      line &= " " & $s.rfLibrary.dataType[k]
      f.write(line & "\n")
    f.write("\n")

  # Gradient events - check for trap and arb types
  var hasArb = false
  var hasTrap = false
  for k, dt in s.gradLibrary.dataType:
    if dt == 'g': hasArb = true
    if dt == 't': hasTrap = true

  if hasArb:
    f.write("# Format of arbitrary gradients:\n")
    f.write("#   time_shape_id of 0 means default timing (stepping with grad_raster starting at 1/2 of grad_raster)\n")
    f.write("# id amplitude first last amp_shape_id time_shape_id delay\n")
    f.write("# ..      Hz/m  Hz/m Hz/m        ..         ..          us\n")
    f.write("[GRADIENTS]\n")
    for k in toSeq(s.gradLibrary.data.keys):
      if s.gradLibrary.dataType.getOrDefault(k, '\0') == 'g':
        let data = s.gradLibrary.data[k]
        var line = formatInt(float64(k))
        line &= " " & formatGPadded(data[0], 6, 12)
        line &= " " & formatGPadded(data[1], 6, 12)
        line &= " " & formatGPadded(data[2], 6, 12)
        line &= " " & formatInt(data[3])
        line &= " " & formatInt(data[4])
        line &= " " & formatInt(round(data[5] * 1e6))
        f.write(line & "\n")
    f.write("\n")

  if hasTrap:
    f.write("# Format of trapezoid gradients:\n")
    f.write("# id amplitude rise flat fall delay\n")
    f.write("# ..      Hz/m   us   us   us    us\n")
    f.write("[TRAP]\n")
    for k in toSeq(s.gradLibrary.data.keys):
      if s.gradLibrary.dataType.getOrDefault(k, '\0') == 't':
        let data = s.gradLibrary.data[k]
        var line = formatIntPadded(k, 2)
        line &= " " & formatGPadded(data[0], 6, 12)
        line &= " " & formatIntPadded(int(round(data[1] * 1e6)), 3)
        line &= " " & formatIntPadded(int(round(data[2] * 1e6)), 4)
        line &= " " & formatIntPadded(int(round(data[3] * 1e6)), 3)
        line &= " " & formatIntPadded(int(round(data[4] * 1e6)), 3)
        f.write(line & "\n")
    f.write("\n")

  # ADC events
  if s.adcLibrary.data.len > 0:
    f.write("# Format of ADC events:\n")
    f.write("# id num dwell delay freqPPM phasePPM freq phase phase_id\n")
    f.write("# ..  ..    ns    us     ppm  rad/MHz   Hz   rad       ..\n")
    f.write("[ADC]\n")
    for k in toSeq(s.adcLibrary.data.keys):
      let data = s.adcLibrary.data[k]
      # data: [numSamples, dwell, delay, freqPPM, phasePPM, freqOffset, phaseOffset, shapeId, deadTime]
      var line = formatInt(float64(k))
      line &= " " & formatInt(data[0])                    # num
      line &= " " & formatInt(data[1] * 1e9)              # dwell in ns
      line &= " " & formatInt(data[2] * 1e6)              # delay in us
      line &= " " & formatG(data[3], 6)                   # freqPPM
      line &= " " & formatG(data[4], 6)                   # phasePPM
      line &= " " & formatG(data[5], 6)                   # freq
      line &= " " & formatG(data[6], 6)                   # phase
      line &= " " & formatInt(data[7])                    # phase_id
      f.write(line & "\n")
    f.write("\n")

  # Extensions
  if s.extensionsLibrary.data.len > 0:
    f.write("# Format of extension lists:\n")
    f.write("# id type ref next_id\n")
    f.write("# next_id of 0 terminates the list\n")
    f.write("# Extension list is followed by extension specifications\n")
    f.write("[EXTENSIONS]\n")
    for k in toSeq(s.extensionsLibrary.data.keys):
      let data = s.extensionsLibrary.data[k]
      var line = formatInt(float64(k))
      for d in data:
        line &= " " & formatInt(round(d))
      f.write(line & "\n")
    f.write("\n")

  # Triggers
  if s.triggerLibrary.data.len > 0:
    f.write("# Extension specification for digital output and input triggers:\n")
    f.write("# id type channel delay (us) duration (us)\n")
    let tid = s.getExtensionTypeID("TRIGGERS")
    f.write(&"extension TRIGGERS {tid}\n")
    for k in toSeq(s.triggerLibrary.data.keys):
      let data = s.triggerLibrary.data[k]
      var line = formatInt(float64(k))
      line &= " " & formatInt(round(data[0]))
      line &= " " & formatInt(round(data[1]))
      line &= " " & formatInt(round(data[2] * 1e6))
      line &= " " & formatInt(round(data[3] * 1e6))
      f.write(line & "\n")
    f.write("\n")

  # Label SET
  if s.labelSetLibrary.data.len > 0:
    f.write("# Extension specification for setting labels:\n")
    f.write("# id set labelstring\n")
    let tid = s.getExtensionTypeID("LABELSET")
    f.write(&"extension LABELSET {tid}\n")
    for k in toSeq(s.labelSetLibrary.data.keys):
      let data = s.labelSetLibrary.data[k]
      let value = data[0]
      let labelId = supportedLabels[int(data[1]) - 1]
      f.write(&"{formatInt(float64(k))} {formatInt(value)} {labelId}\n")
    f.write("\n")

  # Label INC
  if s.labelIncLibrary.data.len > 0:
    f.write("# Extension specification for setting labels:\n")
    f.write("# id set labelstring\n")
    let tid = s.getExtensionTypeID("LABELINC")
    f.write(&"extension LABELINC {tid}\n")
    for k in toSeq(s.labelIncLibrary.data.keys):
      let data = s.labelIncLibrary.data[k]
      let value = data[0]
      let labelId = supportedLabels[int(data[1]) - 1]
      f.write(&"{formatInt(float64(k))} {formatInt(value)} {labelId}\n")
    f.write("\n")

  # Shapes
  if s.shapeLibrary.data.len > 0:
    f.write("# Sequence Shapes\n")
    f.write("[SHAPES]\n\n")
    for k in toSeq(s.shapeLibrary.data.keys):
      let data = s.shapeLibrary.data[k]
      f.write(&"shape_id {formatInt(float64(k))}\n")
      f.write(&"num_samples {formatInt(data[0])}\n")
      for i in 1 ..< data.len:
        f.write(formatG(data[i], 9) & "\n")
      f.write("\n")

  f.close()

  if createSignature:
    # Read file and compute MD5
    let content = readFile(fn)
    let hash = $toMD5(content)
    var sigFile = open(fn, fmAppend)
    sigFile.write("\n[SIGNATURE]\n")
    sigFile.write("# This is the hash of the Pulseq file, calculated right before the [SIGNATURE] section was added\n")
    sigFile.write("# It can be reproduced/verified with md5sum if the file trimmed to the position right above [SIGNATURE]\n")
    sigFile.write("# The new line character preceding [SIGNATURE] BELONGS to the signature (and needs to be stripped away for recalculating/verification)\n")
    sigFile.write("Type md5\n")
    sigFile.write(&"Hash {hash}\n")
    sigFile.close()

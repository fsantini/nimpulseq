import std/math

type
  CompressedShape* = object
    numSamples*: int
    data*: seq[float64]

proc compressShape*(decompressedShape: seq[float64], forceCompression: bool = false): CompressedShape =
  ## Compress a gradient or pulse shape using run-length encoding on the derivative.
  for v in decompressedShape:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      raise newException(ValueError, "compressShape received infinite/NaN samples.")

  if not forceCompression and decompressedShape.len <= 4:
    return CompressedShape(numSamples: decompressedShape.len, data: decompressedShape)

  let quantFactor = 1e-7
  var decompressedScaled = newSeq[float64](decompressedShape.len)
  for i in 0 ..< decompressedShape.len:
    decompressedScaled[i] = decompressedShape[i] / quantFactor

  # datq = round(concat(first, diff(scaled)))
  var datq = newSeq[float64](decompressedScaled.len)
  datq[0] = round(decompressedScaled[0])
  for i in 1 ..< decompressedScaled.len:
    datq[i] = round(decompressedScaled[i] - decompressedScaled[i - 1])

  # qerr = scaled - cumsum(datq)
  var cumsum = newSeq[float64](datq.len)
  cumsum[0] = datq[0]
  for i in 1 ..< datq.len:
    cumsum[i] = cumsum[i - 1] + datq[i]

  var qerr = newSeq[float64](decompressedScaled.len)
  for i in 0 ..< decompressedScaled.len:
    qerr[i] = decompressedScaled[i] - cumsum[i]

  # qcor = concat([0], diff(round(qerr)))
  var qcor = newSeq[float64](qerr.len)
  qcor[0] = 0.0
  for i in 1 ..< qerr.len:
    qcor[i] = round(qerr[i]) - round(qerr[i - 1])

  # datd = datq + qcor
  var datd = newSeq[float64](datq.len)
  for i in 0 ..< datq.len:
    datd[i] = datq[i] + qcor[i]

  # RLE of datd: find run starts
  var starts: seq[int] = @[0]
  for i in 1 ..< datd.len:
    if datd[i] != datd[i - 1]:
      starts.add(i)

  var lengths: seq[int] = @[]
  for i in 0 ..< starts.len - 1:
    lengths.add(starts[i + 1] - starts[i])
  lengths.add(datd.len - starts[^1])

  var values: seq[float64] = @[]
  for i in 0 ..< starts.len:
    values.add(datd[starts[i]] * quantFactor)

  # Build compressed output
  # Runs of length > 1 get (value, value, count-2)
  var v: seq[float64] = @[]
  for i in 0 ..< values.len:
    v.add(values[i])
    if lengths[i] > 1:
      v.add(values[i])
      v.add(float64(lengths[i] - 2))

  result = CompressedShape(numSamples: decompressedShape.len)
  if forceCompression or decompressedShape.len > v.len:
    result.data = v
  else:
    result.data = decompressedShape

proc decompressShape*(compressed: CompressedShape): seq[float64] =
  ## Decompress a shape from run-length encoded derivative format.
  let numSamples = compressed.numSamples
  let dataLen = compressed.data.len

  if dataLen == numSamples:
    # Not actually compressed
    return compressed.data

  # Decode RLE
  var datd: seq[float64] = @[]
  var i = 0
  while i < dataLen:
    if i + 2 < dataLen and compressed.data[i] == compressed.data[i + 1]:
      let value = compressed.data[i]
      let count = int(compressed.data[i + 2]) + 2
      for j in 0 ..< count:
        datd.add(value)
      i += 3
    else:
      datd.add(compressed.data[i])
      i += 1

  # Integrate (cumsum) to recover the original shape
  result = newSeq[float64](datd.len)
  result[0] = datd[0]
  for j in 1 ..< datd.len:
    result[j] = result[j - 1] + datd[j]

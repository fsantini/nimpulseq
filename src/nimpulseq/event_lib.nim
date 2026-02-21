import std/[tables, math, algorithm]
import types

proc find*(lib: EventLibrary, newData: seq[float64]): tuple[keyId: int, found: bool] =
  ## Looks up `newData` in the library without inserting it.
  ## Returns the existing ID and `found = true` if it exists,
  ## or the next free ID and `found = false` if it does not.
  if newData in lib.keymap:
    result = (lib.keymap[newData], true)
  else:
    result = (lib.nextFreeID, false)

proc findOrInsert*(lib: EventLibrary, newData: seq[float64], dataType: char = '\0'): tuple[keyId: int, found: bool] =
  ## Looks up `newData`; if not present, inserts it and assigns a new ID.
  ## Returns the ID and `found = true` if it already existed, `found = false` if freshly inserted.
  ## `dataType` is an optional single-character tag stored alongside the entry (e.g. 't', 'g').
  if newData in lib.keymap:
    result = (lib.keymap[newData], true)
  else:
    let keyId = lib.nextFreeID
    lib.data[keyId] = newData
    if dataType != '\0':
      lib.dataType[keyId] = dataType
    lib.keymap[newData] = keyId
    lib.nextFreeID = keyId + 1
    result = (keyId, false)

proc insert*(lib: EventLibrary, keyId: int, newData: seq[float64], dataType: char = '\0'): int =
  ## Inserts `newData` at `keyId` (or the next free ID if `keyId == 0`), overwriting any previous entry.
  ## Updates the reverse keymap and advances `nextFreeID` if necessary. Returns the used ID.
  var kid = keyId
  if kid == 0:
    kid = lib.nextFreeID

  lib.data[kid] = newData
  if dataType != '\0':
    lib.dataType[kid] = dataType
  lib.keymap[newData] = kid

  if kid >= lib.nextFreeID:
    lib.nextFreeID = kid + 1

  return kid

proc get*(lib: EventLibrary, keyId: int): tuple[data: seq[float64], dataType: char] =
  ## Retrieves the data and type tag stored under `keyId`.
  ## The type tag is `'\0'` if none was set.
  (lib.data[keyId], lib.dataType.getOrDefault(keyId, '\0'))

proc roundData(data: seq[float64], digits: seq[int]): seq[float64] =
  ## Round data to specified number of significant digits.
  ## dig > 0: significant digits (like {:Ng} format)
  ## dig <= 0: decimal places (like {:.Nf} format with negated sign)
  result = newSeq[float64](data.len)
  for i in 0 ..< data.len:
    let d = data[i]
    let dig = digits[i]
    if dig > 0:
      let ndigits = dig - int(ceil(log10(abs(d) + 1e-12)))
      result[i] = round(d * pow(10.0, float64(ndigits))) / pow(10.0, float64(ndigits))
    else:
      let ndigits = -dig
      result[i] = round(d * pow(10.0, float64(ndigits))) / pow(10.0, float64(ndigits))

proc removeDuplicates*(lib: EventLibrary, digits: seq[int]): tuple[newLib: EventLibrary, mapping: Table[int, int]] =
  ## Remove duplicate events from library by rounding data to specified precision.
  ## digits is a seq of significant digit specs, one per field.
  var roundedData = initTable[int, seq[float64]]()
  for k, v in lib.data:
    roundedData[k] = roundData(v, digits)

  var newLib = newEventLibrary()
  var mapping = initTable[int, int]()
  mapping[0] = 0

  # Sort keys to process in order
  var keys: seq[int] = @[]
  for k in roundedData.keys:
    keys.add(k)
  keys.sort()

  for k in keys:
    let v = roundedData[k]
    let dt = lib.dataType.getOrDefault(k, '\0')
    let (kid, _) = newLib.findOrInsert(v, dt)
    mapping[k] = kid

  result = (newLib, mapping)

proc removeDuplicatesScalar*(lib: EventLibrary, digits: int): tuple[newLib: EventLibrary, mapping: Table[int, int]] =
  ## Remove duplicates for numpy-like (shape) libraries with a single digit spec
  var roundedData = initTable[int, seq[float64]]()
  for k, v in lib.data:
    var rounded = newSeq[float64](v.len)
    for i in 0 ..< v.len:
      let d = v[i]
      if digits > 0:
        let mags = pow(10.0, float64(digits) - ceil(log10(abs(d) + 1e-12)))
        rounded[i] = round(d * mags) / mags
      else:
        let mags = pow(10.0, float64(-digits))
        rounded[i] = round(d * mags) / mags
    roundedData[k] = rounded

  var newLib = newEventLibrary()
  var mapping = initTable[int, int]()
  mapping[0] = 0

  var keys: seq[int] = @[]
  for k in roundedData.keys:
    keys.add(k)
  keys.sort()

  for k in keys:
    let v = roundedData[k]
    let dt = lib.dataType.getOrDefault(k, '\0')
    let (kid, _) = newLib.findOrInsert(v, dt)
    mapping[k] = kid

  result = (newLib, mapping)

proc update*(lib: EventLibrary, keyId: int, newData: seq[float64], dataType: char = '\0') =
  ## Update an existing entry, removing old keymap entry
  if keyId in lib.data:
    let oldData = lib.data[keyId]
    if oldData in lib.keymap:
      lib.keymap.del(oldData)
  discard lib.insert(keyId, newData, dataType)

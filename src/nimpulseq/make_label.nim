import types

proc makeLabel*(labelType: string, label: string, value: int): Event =
  ## Creates a label event for scanner sequence counters.
  ##
  ## - `labelType`: either "SET" (assign `value` to the counter) or "INC" (add `value` to the counter).
  ## - `label`: one of the strings in `supportedLabels` (e.g. "LIN", "SLC").
  ## - `value`: the integer to set or increment by.
  ##
  ## Raises `ValueError` for unsupported labels, invalid type strings,
  ## or if INC is requested for a flag-type label (index ≥ 10).
  var found = false
  for sl in supportedLabels:
    if sl == label:
      found = true
      break
  if not found:
    raise newException(ValueError, "Invalid label: " & label)

  if labelType notin ["SET", "INC"]:
    raise newException(ValueError, "Invalid type. Must be 'SET' or 'INC'.")

  if labelType == "SET":
    result = Event(kind: ekLabelSet)
  else:
    # Check if label is a flag (index >= 10) - flags are not compatible with INC
    var labelIdx = -1
    for i, sl in supportedLabels:
      if sl == label:
        labelIdx = i
        break
    if labelIdx >= 10 and labelIdx < supportedLabels.len - 1:
      raise newException(ValueError, "labelinc is not compatible with flags")
    result = Event(kind: ekLabelInc)

  result.labelName = label
  result.labelValue = value

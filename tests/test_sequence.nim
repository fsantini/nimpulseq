## Tests for sequence write + file comparison against expected output.
## Ports test_sequence.py from PyPulseq.
## Skips: seq6 (soft_delay), write_gre_label_softdelay, read/plot/recreate tests.

import std/[strformat, math, strutils, os]
import ../src/nimpulseq
import ../examples/write_gre
import ../examples/write_gre_label
import ../examples/write_epi
import ../examples/write_epi_se
import ../examples/write_epi_label
import ../examples/write_epi_se_rs
import ../examples/write_haste
import ../examples/write_tse
import ../examples/write_mprage
import ../examples/write_radial_gre
import ../examples/write_ute

var passed = 0
var failed = 0
let expectedDir = currentSourcePath().parentDir / "expected_output"
let tmpDir = getTempDir() / "nimpulseq_test_seq"

template test(name: string, body: untyped) =
  try:
    body
    echo "[PASS] ", name
    inc passed
  except CatchableError, AssertionDefect:
    echo "[FAIL] ", name, ": ", getCurrentExceptionMsg()
    inc failed

proc linesApproxEqual(line1, line2: string, relTol: float64 = 1e-5): bool =
  ## Compare two lines token-by-token; numeric tokens compared with relative tolerance.
  let tokens1 = line1.splitWhitespace()
  let tokens2 = line2.splitWhitespace()
  if tokens1.len != tokens2.len:
    return false
  for j in 0 ..< tokens1.len:
    if tokens1[j] == tokens2[j]:
      continue
    try:
      let v1 = parseFloat(tokens1[j])
      let v2 = parseFloat(tokens2[j])
      let denom = max(abs(v1), abs(v2))
      if denom == 0:
        continue
      if abs(v1 - v2) / denom > relTol:
        return false
    except ValueError:
      return false
  return true

proc compareSeqFiles(file1, file2: string) =
  ## Compare two .seq files, skipping everything before [VERSION] and last 2 lines (signature).
  ## Uses zip semantics (compare up to the shorter file length, like Python's zip).
  let lines1 = readFile(file1).splitLines()
  let lines2 = readFile(file2).splitLines()
  var versionLine1 = -1
  var versionLine2 = -1
  for i, line in lines1:
    if line.strip() == "[VERSION]":
      versionLine1 = i
      break
  for i, line in lines2:
    if line.strip() == "[VERSION]":
      versionLine2 = i
      break

  doAssert versionLine1 >= 0, &"[VERSION] section not found in {file1}"
  doAssert versionLine2 >= 0, &"[VERSION] section not found in {file2}"

  # Skip variable-length header and signature (last 2 lines)
  let content1 = lines1[versionLine1 .. ^3]
  let content2 = lines2[versionLine2 .. ^3]
  doAssert content1.len == content2.len,
    &"Line count mismatch: {content1.len} vs {content2.len}"
  for i in 0 ..< content1.len:
    if content1[i] != content2[i]:
      doAssert linesApproxEqual(content1[i], content2[i]),
        &"Line differs (file1 line {versionLine1 + i + 1}, file2 line {versionLine2 + i + 1}):\n  got:      '{content1[i]}'\n  expected: '{content2[i]}'"

proc writeAndCompare(seqObj: Sequence, name: string) =
  let outFile = tmpDir / (name & ".seq")
  seqObj.writeSeq(outFile, createSignature = true)
  let expectedFile = expectedDir / (name & ".seq")
  compareSeqFiles(outFile, expectedFile)
  removeFile(outFile)

# ----- Dummy sequence generators -----

proc seqMakeGaussPulses(): Sequence =
  var seqObj = newSequence()
  let (g1, _, _) = makeGaussPulse(flipAngle = 1.0)
  seqObj.addBlock(g1)
  seqObj.addBlock(makeDelay(1.0))
  let (g2, _, _) = makeGaussPulse(flipAngle = 1.0, delay = 1e-3)
  seqObj.addBlock(g2)
  seqObj.addBlock(makeDelay(1.0))
  let (g3, _, _) = makeGaussPulse(flipAngle = PI / 2.0)
  seqObj.addBlock(g3)
  seqObj.addBlock(makeDelay(1.0))
  let (g4, _, _) = makeGaussPulse(flipAngle = PI / 2.0, duration = 1e-3)
  seqObj.addBlock(g4)
  seqObj.addBlock(makeDelay(1.0))
  let (g5, _, _) = makeGaussPulse(flipAngle = PI / 2.0, duration = 2e-3, phaseOffset = PI / 2.0)
  seqObj.addBlock(g5)
  seqObj.addBlock(makeDelay(1.0))
  let (g6, _, _) = makeGaussPulse(flipAngle = PI / 2.0, duration = 1e-3, phaseOffset = PI / 2.0, freqOffset = 1e3)
  seqObj.addBlock(g6)
  seqObj.addBlock(makeDelay(1.0))
  let (g7, _, _) = makeGaussPulse(flipAngle = PI / 2.0, duration = 1e-3, timeBwProduct = 1.0)
  seqObj.addBlock(g7)
  seqObj.addBlock(makeDelay(1.0))
  let (g8, _, _) = makeGaussPulse(flipAngle = PI / 2.0, duration = 1e-3, apodization = 0.1)
  seqObj.addBlock(g8)
  result = seqObj

proc seqMakeSincPulses(): Sequence =
  var seqObj = newSequence()
  let (s1, _, _) = makeSincPulse(flipAngle = 1.0)
  seqObj.addBlock(s1)
  seqObj.addBlock(makeDelay(1.0))
  let (s2, _, _) = makeSincPulse(flipAngle = 1.0, delay = 1e-3)
  seqObj.addBlock(s2)
  seqObj.addBlock(makeDelay(1.0))
  let (s3, _, _) = makeSincPulse(flipAngle = PI / 2.0)
  seqObj.addBlock(s3)
  seqObj.addBlock(makeDelay(1.0))
  let (s4, _, _) = makeSincPulse(flipAngle = PI / 2.0, duration = 1e-3)
  seqObj.addBlock(s4)
  seqObj.addBlock(makeDelay(1.0))
  let (s5, _, _) = makeSincPulse(flipAngle = PI / 2.0, duration = 2e-3, phaseOffset = PI / 2.0)
  seqObj.addBlock(s5)
  seqObj.addBlock(makeDelay(1.0))
  let (s6, _, _) = makeSincPulse(flipAngle = PI / 2.0, duration = 1e-3, phaseOffset = PI / 2.0, freqOffset = 1e3)
  seqObj.addBlock(s6)
  seqObj.addBlock(makeDelay(1.0))
  let (s7, _, _) = makeSincPulse(flipAngle = PI / 2.0, duration = 1e-3, timeBwProduct = 1.0)
  seqObj.addBlock(s7)
  seqObj.addBlock(makeDelay(1.0))
  let (s8, _, _) = makeSincPulse(flipAngle = PI / 2.0, duration = 1e-3, apodization = 0.1)
  seqObj.addBlock(s8)
  result = seqObj

proc seqMakeBlockPulses(): Sequence =
  var seqObj = newSequence()
  seqObj.addBlock(makeBlockPulse(flipAngle = 1.0, duration = 4e-3))
  seqObj.addBlock(makeDelay(1.0))
  seqObj.addBlock(makeBlockPulse(flipAngle = 1.0, delay = 1e-3, duration = 4e-3))
  seqObj.addBlock(makeDelay(1.0))
  seqObj.addBlock(makeBlockPulse(flipAngle = PI / 2.0, duration = 4e-3))
  seqObj.addBlock(makeDelay(1.0))
  seqObj.addBlock(makeBlockPulse(flipAngle = PI / 2.0, duration = 1e-3))
  seqObj.addBlock(makeDelay(1.0))
  seqObj.addBlock(makeBlockPulse(flipAngle = PI / 2.0, duration = 2e-3, phaseOffset = PI / 2.0))
  seqObj.addBlock(makeDelay(1.0))
  seqObj.addBlock(makeBlockPulse(flipAngle = PI / 2.0, duration = 1e-3, phaseOffset = PI / 2.0, freqOffset = 1e3))
  seqObj.addBlock(makeDelay(1.0))
  seqObj.addBlock(makeBlockPulse(flipAngle = PI / 2.0, duration = 1e-3, timeBwProduct = 1.0))
  result = seqObj

proc seq1(): Sequence =
  var seqObj = newSequence()
  seqObj.addBlock(makeBlockPulse(PI / 4.0, duration = 1e-3))
  seqObj.addBlock(makeTrapezoid("x", area = 1000.0))
  seqObj.addBlock(makeTrapezoid("y", area = -500.00001))
  seqObj.addBlock(makeTrapezoid("z", area = 100.0))
  seqObj.addBlock(makeTrapezoid("x", area = -1000.0), makeTrapezoid("y", area = 500.0))
  seqObj.addBlock(makeTrapezoid("y", area = -500.0), makeTrapezoid("z", area = 1000.0))
  seqObj.addBlock(makeTrapezoid("x", area = -1000.0), makeTrapezoid("z", area = 1000.00001))
  result = seqObj

proc seq2(): Sequence =
  var seqObj = newSequence()
  seqObj.addBlock(makeBlockPulse(PI / 2.0, duration = 1e-3))
  seqObj.addBlock(makeTrapezoid("x", area = 1000.0))
  seqObj.addBlock(makeTrapezoid("x", area = -1000.0))
  seqObj.addBlock(makeBlockPulse(PI, duration = 1e-3))
  seqObj.addBlock(makeTrapezoid("x", area = -500.0))
  seqObj.addBlock(makeTrapezoid("x", area = 1000.0, duration = 10e-3), makeAdc(numSamples = 100, duration = 10e-3))
  result = seqObj

proc seq3(): Sequence =
  var seqObj = newSequence()
  for i in 0 ..< 10:
    seqObj.addBlock(makeBlockPulse(PI / 8.0, duration = 1e-3))
    seqObj.addBlock(makeTrapezoid("x", area = 1000.0))
    seqObj.addBlock(makeTrapezoid("y", area = -500.0 + float64(i) * 100.0))
    seqObj.addBlock(makeTrapezoid("x", area = -500.0))
    seqObj.addBlock(makeTrapezoid("x", area = 1000.0, duration = 10e-3),
      makeAdc(numSamples = 100, duration = 10e-3),
      makeLabel("INC", "LIN", 1))
  result = seqObj

proc seq4(): Sequence =
  var seqObj = newSequence()
  for i in 0 ..< 10:
    seqObj.addBlock(makeBlockPulse(PI / 8.0, duration = 1e-3))
    seqObj.addBlock(makeTrapezoid("x", area = 1000.0))
    seqObj.addBlock(makeTrapezoid("y", area = -500.0 + float64(i) * 100.0))
    seqObj.addBlock(makeTrapezoid("x", area = -500.0))
    seqObj.addBlock(makeTrapezoid("x", area = 1000.0, duration = 10e-3),
      makeAdc(numSamples = 100, duration = 10e-3),
      makeLabel("SET", "LIN", i))
  result = seqObj

proc seq5(): Sequence =
  let sys = defaultOpts()
  var seqObj = newSequence(sys)
  let (rf, gz, gzr) = makeSincPulse(flipAngle = PI / 8.0, duration = 1e-3,
    sliceThickness = 3e-3, returnGz = true)
  let gx = makeTrapezoid(channel = "x", flatArea = 32.0 * (1.0 / 0.3),
    flatTime = 32.0 * 1e-4, system = sys)
  let adc = makeAdc(numSamples = 32, duration = gx.trapFlatTime,
    delay = gx.trapRiseTime, system = sys)
  let gxPre = makeTrapezoid(channel = "x", area = -gx.trapArea / 2.0,
    duration = 1e-3, system = sys)

  var phaseAreas = newSeq[float64](32)
  for i in 0 ..< 32:
    phaseAreas[i] = -(float64(i) - 32.0 / 2.0) * (1.0 / 0.3)

  seqObj.addBlock(makeLabel("SET", "LIN", 0), makeLabel("SET", "SLC", 0))
  seqObj.addBlock(makeAdc(numSamples = 1000, duration = 1e-3), makeLabel("SET", "NOISE", 1))
  seqObj.addBlock(makeLabel("SET", "NOISE", 0))
  seqObj.addBlock(makeDelay(sys.rfDeadTime))

  for pe in 0 ..< 32:
    var gyPre = makeTrapezoid(channel = "y", area = phaseAreas[pe],
      duration = 1e-3, system = sys)
    seqObj.addBlock(rf, gz)
    seqObj.addBlock(gxPre, gyPre, gzr)
    seqObj.addBlock(gx, adc, makeLabel("SET", "LIN", pe))
    gyPre.trapAmplitude = -gyPre.trapAmplitude
    seqObj.addBlock(gxPre, gyPre, makeDelay(10e-3))

  result = seqObj

proc seqTrapOnly(): Sequence =
  var seqObj = newSequence()
  seqObj.addBlock(makeTrapezoid("x", area = 1000.0))
  result = seqObj

proc seqAdcOnly(): Sequence =
  var seqObj = newSequence()
  seqObj.addBlock(makeAdc(numSamples = 100, duration = 10e-3))
  result = seqObj

proc seqExtOnly(): Sequence =
  var seqObj = newSequence()
  seqObj.addBlock(makeAdc(numSamples = 1000, duration = 1e-3), makeLabel("SET", "NOISE", 1))
  result = seqObj

# Create temp dir
createDir(tmpDir)

# ----- Sequence zoo -----

test "sequence write/compare seq_make_gauss_pulses":
  writeAndCompare(seqMakeGaussPulses(), "seq_make_gauss_pulses")

test "sequence write/compare seq_make_sinc_pulses":
  writeAndCompare(seqMakeSincPulses(), "seq_make_sinc_pulses")

test "sequence write/compare seq_make_block_pulses":
  writeAndCompare(seqMakeBlockPulses(), "seq_make_block_pulses")

test "sequence write/compare seq1":
  writeAndCompare(seq1(), "seq1")

test "sequence write/compare seq2":
  writeAndCompare(seq2(), "seq2")

test "sequence write/compare seq3":
  writeAndCompare(seq3(), "seq3")

test "sequence write/compare seq4":
  writeAndCompare(seq4(), "seq4")

test "sequence write/compare seq5":
  writeAndCompare(seq5(), "seq5")

# seq6 skipped (soft_delay not implemented)

test "sequence write/compare seq_trap_only":
  writeAndCompare(seqTrapOnly(), "seq_trap_only")

test "sequence write/compare seq_adc_only":
  writeAndCompare(seqAdcOnly(), "seq_adc_only")

test "sequence write/compare seq_ext_only":
  writeAndCompare(seqExtOnly(), "seq_ext_only")

# ----- Example sequences -----
test "write_gre":
  writeAndCompare(writeGreSeq(), "write_gre")

test "write_gre_label":
  writeAndCompare(writeGreLabelSeq(), "write_gre_label")

test "write_epi":
  writeAndCompare(writeEpiSeq(), "write_epi")

test "write_epi_se":
  writeAndCompare(writeEpiSeSeq(), "write_epi_se")

test "write_epi_label":
  writeAndCompare(writeEpiLabelSeq(), "write_epi_label")

test "write_epi_se_rs":
  writeAndCompare(writeEpiSeRsSeq(), "write_epi_se_rs")

test "write_haste":
  writeAndCompare(writeHasteSeq(), "write_haste")

test "write_tse":
  writeAndCompare(writeTseSeq(), "write_tse")

test "write_mprage":
  writeAndCompare(writeMprageSeq(), "write_mprage")

test "write_radial_gre":
  writeAndCompare(writeRadialGreSeq(), "write_radial_gre")

test "write_ute":
  writeAndCompare(writeUteSeq(), "write_ute")

echo "[SKIP] write_gre_label_softdelay (soft_delay not implemented)"
echo "[SKIP] seq6 (soft_delay not implemented)"

# Clean up temp dir
removeDir(tmpDir)

echo &"\n{passed} passed, {failed} failed"
if failed > 0: quit(1)

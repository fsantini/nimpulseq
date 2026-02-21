## Tests calc_duration by feeding it sample events with known durations.
## Additionally, tests the combination of any 2 and 3 of those events.

import std/[strformat, math]
import nimpulseq

var passed = 0
var failed = 0

template test(name: string, body: untyped) =
  try:
    body
    echo "[PASS] ", name
    inc passed
  except CatchableError, AssertionDefect:
    echo "[FAIL] ", name, ": ", getCurrentExceptionMsg()
    inc failed

# Build the event zoo: (name, event, expected_duration)
type EventEntry = tuple[name: string, event: Event, dur: float64]

let zoo: seq[EventEntry] = @[
  ("trapz_amp1", makeTrapezoid("x", amplitude = 1.0, duration = 1.0), 1.0),
  ("trapz_amp1_delayed1", makeTrapezoid("x", amplitude = 1.0, duration = 1.0, delay = 1.0), 2.0),
  ("delay1", makeDelay(1.0), 1.0),
  ("delay0", makeDelay(0.0), 0.0),
  ("rf0_block1", makeBlockPulse(flipAngle = 0.0, duration = 1.0), 1.0),
  ("rf10_block1", makeBlockPulse(flipAngle = 10.0, duration = 1.0), 1.0),
  ("rf10_block1_delay1", makeBlockPulse(flipAngle = 10.0, duration = 1.0, delay = 1.0), 2.0),
  ("adc3", makeAdc(duration = 3.0, numSamples = 1), 3.0),
  ("adc3_delayed", makeAdc(duration = 3.0, delay = 1.0, numSamples = 1), 4.0),
  ("outputOsc042", makeDigitalOutputPulse("osc0", duration = 42.0), 42.0),
  ("outputOsc142_delay3", makeDigitalOutputPulse("osc1", duration = 42.0, delay = 1.0), 43.0),
  ("outputExt42_delay9", makeDigitalOutputPulse("osc1", duration = 42.0, delay = 9.0), 51.0),
  ("triggerPhysio159", makeTrigger("physio1", duration = 59.0), 59.0),
  ("triggerPhysio259_delay1", makeTrigger("physio2", duration = 59.0, delay = 1.0), 60.0),
  ("label0", makeLabel("SET", "SLC", 0), 0.0),
]

# Test no events
test "calc_duration no events":
  doAssert calcDuration() == 0.0

# Test single events
for entry in zoo:
  test &"calc_duration single {entry.name}":
    doAssert calcDuration(entry.event) == entry.dur,
      &"Expected {entry.dur}, got {calcDuration(entry.event)}"

# Test combinations of 2
for i in 0 ..< zoo.len:
  for j in i ..< zoo.len:
    let name = &"calc_duration combo2 {zoo[i].name},{zoo[j].name}"
    let expected = max(zoo[i].dur, zoo[j].dur)
    test name:
      doAssert calcDuration(zoo[i].event, zoo[j].event) == expected

# Test combinations of 3
for i in 0 ..< zoo.len:
  for j in i ..< zoo.len:
    for k in j ..< zoo.len:
      let name = &"calc_duration combo3 {zoo[i].name},{zoo[j].name},{zoo[k].name}"
      let expected = max(max(zoo[i].dur, zoo[j].dur), zoo[k].dur)
      test name:
        doAssert calcDuration(zoo[i].event, zoo[j].event, zoo[k].event) == expected

echo &"\n{passed} passed, {failed} failed"
if failed > 0: quit(1)

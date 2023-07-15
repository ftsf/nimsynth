import common
import math
import util
import machines.master
import nico

# simple clock
type
  ClockRateUnit = enum
    PerSecond
    PerBeat
    EverySecond
    EveryBeat
  Clock = ref object of Machine
    clockRateUnit: ClockRateUnit  # as unit of sampleRate
    clockRate: float32 # as unit of sampleRate
    clock: float32
    triggered: bool

{.this:self.}

method init(self: Clock) =
  procCall init(Machine(self))
  name = "clock"
  nOutputs = 0
  nInputs = 0
  stereo = false

  nBindings = 1
  bindings.setLen(1)

  globalParams.add([
    Parameter(name: "rate", kind: Float, min: 0.0, max: 48000.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.clockRate = max(newValue, 0.0)
    ),
    Parameter(name: "units", kind: Int, min: ClockRateUnit.low.float32, max: ClockRateUnit.high.float32, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.clockRateUnit = newValue.ClockRateUnit
    , getValueString: proc(value: float32, voice: int): string =
        return $(value.ClockRateUnit)
    ),
    Parameter(name: "phase", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.clock = clamp(newValue, 0.0, 1.0)
    ),
  ])

  setDefaults()

method process(self: Clock) {.inline.} =
  if clockRate > 0.0:
    case clockRateUnit:
    of PerSecond:
      clock += clockRate / sampleRate
    of PerBeat:
      clock += clockRate / sampleRate * beatsPerSecond()
    of EverySecond:
      clock += 1.0 / (clockRate * sampleRate)
    of EveryBeat:
      clock += 1.0 / (clockRate * sampleRate * beatsPerSecond())

    if clock >= 1.0:
      triggered = true
      clock -= 1.0
      clock = clamp(clock, 0.0, 1.0)

  if triggered:
    if bindings[0].isBound():
      var (voice,param) = bindings[0].getParameter()
      param.value = 1.0
      param.onchange(1.0, voice)
    triggered = false

  globalParams[2].value = clock

proc newClock(): Machine =
  var m = new(Clock)
  m.init()
  return m

registerMachine("clock", newClock, "generator")

import filter
import ringbuffer
import common
import math
import util

{.this:self.}

type
  Delay* = object of RootObj
    buffer: RingBuffer[float32]
    wet*,dry*: float
    feedback*: float
    cutoff*: float
    filter: OnePoleFilter

proc setLen*(self: var Delay, newLength: int) =
  # FIXME: expand or contract the existing buffer
  self.buffer = newRingBuffer[float32](newLength)

proc process*(self: var Delay, sample: float32): float32 =
  var fromDelay = self.buffer[0]
  filter.setCutoff(cutoff)
  fromDelay = filter.process(fromDelay)
  self.buffer.add([(sample + fromDelay * feedback).float32])
  return fromDelay * wet + sample * dry

type
  DelayMachine = ref object of Machine
    delay: Delay

method init(self: DelayMachine) =
  procCall init(Machine(self))
  name = "delay"
  nInputs = 1
  nOutputs = 1
  delay.filter.init()

  self.globalParams.add([
    Parameter(name: "length", kind: Float, min: 0.0, max: 10.0, default: Lowpass.float, onchange: proc(newValue: float, voice: int) =
      self.delay.setLen((newValue * sampleRate).int)
    ),
    Parameter(name: "wet", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.delay.wet = newValue
    ),
    Parameter(name: "dry", kind: Float, min: -1.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.delay.dry = newValue
    ),
    Parameter(name: "feedback", kind: Float, min: -1.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.delay.feedback = newValue
    ),
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.delay.filter.cutoff = exp(lerp(-8.0, -0.8, newValue))
    ),
  ])

method process(self: DelayMachine, sample: float32): float32 {.inline.} =
  # TODO: modulate
  result = self.delay.process(sample)

proc newDelayMachine(): Machine =
  result = new(DelayMachine)
  result.init()

registerMachine("delay", newDelayMachine)

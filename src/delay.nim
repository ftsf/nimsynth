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
  if self.buffer.length == 0:
    self.buffer = newRingBuffer[float32](newLength)
  else:
    self.buffer.setLen(newLength)

proc process*(self: var Delay, sample: float32): float32 =
  if self.buffer.length == 0:
    return sample * wet + sample * dry
  var fromDelay = self.buffer[0]
  filter.setCutoff(cutoff)
  filter.calc()
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
    Parameter(name: "length", kind: Float, min: 0.0, max: 10.0, default: 0.33, onchange: proc(newValue: float, voice: int) =
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
      self.delay.cutoff = exp(lerp(-8.0, -0.8, newValue))
    ),
  ])

  for param in mitems(self.globalParams):
    param.value = param.default
    if param.onchange != nil:
      param.onchange(param.value)

  echo "DelayMachine: init"

method process(self: DelayMachine): float32 {.inline.} =
  for input in mitems(self.inputs):
    result += input.machine.outputSample * input.gain
  result = self.delay.process(result)

proc newDelayMachine(): Machine =
  result = new(DelayMachine)
  result.init()

registerMachine("delay", newDelayMachine)

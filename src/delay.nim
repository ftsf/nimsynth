import filter
import ringbuffer
import common
import math
import util
import osc
import pico

{.this:self.}

const maxDelay = 1000

type
  SimpleDelay* = object of RootObj
    buffer: RingBuffer[float32]
    feedback*: float
  Delay* = object of RootObj
    buffer: RingBuffer[float32]
    wet*,dry*: float
    feedback*: float
    cutoff*: float
    filter: OnePoleFilter

proc setLen*(self: var SimpleDelay, newLength: int) =
  # FIXME: expand or contract the existing buffer
  if self.buffer.length == 0:
    self.buffer = newRingBuffer[float32](abs(newLength))
  else:
    self.buffer.setLen(abs(newLength))

proc setLen*(self: var Delay, newLength: int) =
  # FIXME: expand or contract the existing buffer
  if self.buffer.length == 0:
    self.buffer = newRingBuffer[float32](abs(newLength))
  else:
    self.buffer.setLen(abs(newLength))

proc process*(self: var SimpleDelay, sample: float32): float32 {.inline.} =
  if self.buffer.length == 0:
    return sample
  let fromDelay = self.buffer[0]
  self.buffer.add([(sample + fromDelay * feedback).float32])
  return fromDelay

proc process*(self: var Delay, sample: float32): float32 {.inline.} =
  if self.buffer.length == 0:
    return sample * wet + sample * dry
  var fromDelay = self.buffer[0]
  filter.setCutoff(cutoff)
  filter.calc()
  fromDelay = filter.process(fromDelay)
  self.buffer.add([(sample + fromDelay * feedback).float32])
  return fromDelay * wet + sample * dry

proc processPingPong*(self: var Delay, other: var Delay, sample: float32): float32 =
  if self.buffer.length == 0:
    return sample * wet + sample * dry
  var fromDelay = self.buffer[0]
  filter.setCutoff(cutoff)
  filter.calc()
  fromDelay = filter.process(fromDelay)
  self.buffer.add([(sample + fromDelay * feedback).float32])
  # add wet output to other's delays's buffer
  other.buffer[0] = other.buffer[0] + fromDelay * wet
  return fromDelay * wet + sample * dry

type
  DelayMachine = ref object of Machine
    delay: Delay
  SDelayMachine = ref object of Machine
    delayL: Delay
    delayR: Delay
  PingPongDelayMachine = ref object of Machine
    delayL: Delay
    delayR: Delay
  Chorus = ref object of Machine
    delayLs: array[10, SimpleDelay]
    delayRs: array[10, SimpleDelay]
    delaySamples: int
    chorusVoices: int
    variance: int
    dry: float
    wet: float


method init(self: DelayMachine) =
  procCall init(Machine(self))
  name = "delay"
  nInputs = 1
  nOutputs = 1
  stereo = true
  delay.filter.init()

  self.globalParams.add([
    Parameter(name: "length", kind: Float, min: 0.0, max: 10.0, default: 0.33, onchange: proc(newValue: float, voice: int) =
      self.delay.setLen((newValue * sampleRate).int)
    ),
    Parameter(name: "wet", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.delay.wet = newValue
    ),
    Parameter(name: "dry", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.delay.dry = newValue
    ),
    Parameter(name: "feedback", kind: Float, min: -1.0, max: 1.0, default: 0.75, onchange: proc(newValue: float, voice: int) =
      self.delay.feedback = newValue
    ),
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.75, onchange: proc(newValue: float, voice: int) =
      self.delay.cutoff = exp(lerp(-8.0, -0.8, newValue))
    ),
  ])

  for param in mitems(self.globalParams):
    param.value = param.default
    if param.onchange != nil:
      param.onchange(param.value)

method process(self: DelayMachine) {.inline.} =
  outputSamples[0] = 0.0
  for input in mitems(self.inputs):
    outputSamples[0] += input.getSample()
  outputSamples[0] = self.delay.process(outputSamples[0])

proc newDelayMachine(): Machine =
  result = new(DelayMachine)
  result.init()

registerMachine("delay", newDelayMachine)

method init(self: SDelayMachine) =
  procCall init(Machine(self))
  name = "sdelay"
  nInputs = 1
  nOutputs = 1
  stereo = true
  delayL.filter.init()
  delayR.filter.init()

  self.globalParams.add([
    Parameter(name: "length - l", kind: Float, min: 0.0, max: 10.0, default: 0.33, onchange: proc(newValue: float, voice: int) =
      self.delayL.setLen((newValue * sampleRate).int)
    ),
    Parameter(name: "length - r", kind: Float, min: 0.0, max: 10.0, default: 0.34, onchange: proc(newValue: float, voice: int) =
      self.delayR.setLen((newValue * sampleRate).int)
    ),
    Parameter(name: "wet", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.delayL.wet = newValue
      self.delayR.wet = newValue
    ),
    Parameter(name: "dry", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.delayL.dry = newValue
      self.delayR.dry = newValue
    ),
    Parameter(name: "feedback", kind: Float, min: -1.0, max: 1.0, default: 0.75, onchange: proc(newValue: float, voice: int) =
      self.delayL.feedback = newValue
      self.delayR.feedback = newValue
    ),
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.75, onchange: proc(newValue: float, voice: int) =
      self.delayL.cutoff = exp(lerp(-8.0, -0.8, newValue))
      self.delayR.cutoff = exp(lerp(-8.0, -0.8, newValue))
    ),
  ])

  for param in mitems(self.globalParams):
    param.value = param.default
    if param.onchange != nil:
      param.onchange(param.value)

method process(self: SDelayMachine) {.inline.} =
  outputSamples[0] = 0.0
  for input in mitems(self.inputs):
    outputSamples[0] += input.getSample()
  if outputSampleId mod 2 == 0:
    outputSamples[0] = self.delayL.process(outputSamples[0])
  else:
    outputSamples[0] = self.delayR.process(outputSamples[0])

proc newSDelayMachine(): Machine =
  result = new(SDelayMachine)
  result.init()

registerMachine("sdelay", newSDelayMachine)

method init(self: PingPongDelayMachine) =
  procCall init(Machine(self))
  name = "ppdelay"
  nInputs = 1
  nOutputs = 1
  stereo = true
  delayL.filter.init()
  delayR.filter.init()

  self.globalParams.add([
    Parameter(name: "ping", kind: Float, min: 0.0, max: 10.0, default: 0.33, onchange: proc(newValue: float, voice: int) =
      self.delayL.setLen((newValue * sampleRate).int)
    ),
    Parameter(name: "pong", kind: Float, min: 0.0, max: 10.0, default: 0.33, onchange: proc(newValue: float, voice: int) =
      self.delayR.setLen((newValue * sampleRate).int)
    ),
    Parameter(name: "wet", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.delayL.wet = newValue
      self.delayR.wet = newValue
    ),
    Parameter(name: "dry", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.delayL.dry = newValue
      self.delayR.dry = newValue
    ),
    Parameter(name: "feedback", kind: Float, min: -1.0, max: 1.0, default: 0.75, onchange: proc(newValue: float, voice: int) =
      self.delayL.feedback = newValue
      self.delayR.feedback = newValue
    ),
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.75, onchange: proc(newValue: float, voice: int) =
      self.delayL.cutoff = exp(lerp(-8.0, -0.8, newValue))
      self.delayR.cutoff = exp(lerp(-8.0, -0.8, newValue))
    ),
  ])

  for param in mitems(self.globalParams):
    param.value = param.default
    if param.onchange != nil:
      param.onchange(param.value)

method process(self: PingPongDelayMachine) {.inline.} =
  outputSamples[0] = 0.0
  for input in mitems(self.inputs):
    outputSamples[0] += input.getSample()

  if outputSampleId mod 2 == 0:
    outputSamples[0] = self.delayL.processPingPong(self.delayR, outputSamples[0])
  else:
    outputSamples[0] = self.delayR.processPingPong(self.delayL, outputSamples[0])

proc newPingPongDelayMachine(): Machine =
  result = new(PingPongDelayMachine)
  result.init()

registerMachine("ppdelay", newPingPongDelayMachine)

proc reset(self: Chorus) =
  for i,delay in mpairs(delayLs):
    delay.setLen(delaySamples + (variance.float / chorusVoices.float) * i)
  for i,delay in mpairs(delayRs):
    delay.setLen(delaySamples + (variance.float / chorusVoices.float) * i)


method init(self: Chorus) =
  procCall init(Machine(self))
  name = "chorus"
  nInputs = 1
  nOutputs = 1
  stereo = true
  delaySamples = 0
  variance = 10
  chorusVoices = 5

  self.globalParams.add([
    Parameter(name: "delay", kind: Float, min: 0.0001, max: 1.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.delaySamples = (newValue * sampleRate).int
      self.reset()
    ),
    Parameter(name: "variance", kind: Float, min: 10.0, max: 200.0, default: 10.0, onchange: proc(newValue: float, voice: int) =
      self.variance = newValue.int
      self.reset()
    ),
    Parameter(name: "voices", kind: Int, min: 1.0, max: 10.0, default: 5.0, onchange: proc(newValue: float, voice: int) =
      self.chorusVoices = newValue.int
      self.reset()
    ),
    Parameter(name: "wet", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.wet = newValue
    ),
    Parameter(name: "dry", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.dry = newValue
    ),
  ])

  for param in mitems(self.globalParams):
    param.value = param.default
    if param.onchange != nil:
      param.onchange(param.value)

method process(self: Chorus) {.inline.} =
  var dry = 0.0
  var wet = 0.0

  for input in mitems(self.inputs):
    dry += input.getSample()

  if outputSampleId mod 2 == 0:
    for delay in mitems(delayLs):
      wet += delay.process(dry)
  else:
    for delay in mitems(delayLs):
      wet += delay.process(dry)

  outputSamples[0] = (wet / chorusVoices.float) * self.wet + dry * self.dry


proc newChorus(): Machine =
  result = new(Chorus)
  result.init()

registerMachine("chorus", newChorus)

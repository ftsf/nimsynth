import math

import common

import core.moddelay
import core.oscillator


type
  Flanger = ref object of Machine
    delayL: ModDelay
    delayR: ModDelay
    delayTime: float32
    lfoL: Osc
    lfoR: Osc
    lfoAmount: float32
    lfoPhaseOffset: float32
    wet, dry: float32

{.this:self.}

method init(self: Flanger) =
  procCall init(Machine(self))
  name = "flanger"
  nInputs = 1
  nOutputs = 1
  stereo = true
  lfoL.kind = Sin
  lfoR.kind = Sin
  delayTime = 0.0

  self.globalParams.add([
    Parameter(name: "delay", kind: Float, min: 0.0, max: 0.1, default: 0.02, onchange: proc(newValue: float32, voice: int) =
      self.delayTime = newValue
    ),
    Parameter(name: "wet", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float32, voice: int) =
      self.wet = newValue
    ),
    Parameter(name: "dry", kind: Float, min: -1.0, max: 1.0, default: 0.5, onchange: proc(newValue: float32, voice: int) =
      self.dry = newValue
    ),
    Parameter(name: "feedback", kind: Float, min: -1.0, max: 1.0, default: 0.75, onchange: proc(newValue: float32, voice: int) =
      self.delayL.feedback = newValue
      self.delayR.feedback = newValue
    ),
    Parameter(name: "lfo freq", kind: Float, min: 0.0001, max: 60.0, default: 0.1, onchange: proc(newValue: float32, voice: int) =
      self.lfoL.freq = newValue
      self.lfoR.freq = newValue
      self.lfoR.phase = self.lfoL.phase + self.lfoPhaseOffset
    ),
    Parameter(name: "lfo amp", kind: Float, min: 0.0, max: 0.05, default: 0.001, onchange: proc(newValue: float32, voice: int) =
      self.lfoAmount = newValue
    ),
    Parameter(name: "lfo phase", kind: Float, min: -PI, max: PI, default: PI/2.0, onchange: proc(newValue: float32, voice: int) =
      self.lfoPhaseOffset = newValue
      self.lfoR.phase = self.lfoL.phase + self.lfoPhaseOffset
    ),
  ])

  setDefaults()

method process(self: Flanger) {.inline.} =
  var dry = 0.0
  var wet = 0.0
  for input in mitems(self.inputs):
    dry += input.getSample()

  if outputSampleId mod 2 == 0:
    self.delayL.delayTime = delayTime + (lfoL.process() * lfoAmount)
    wet = self.delayL.process(dry)
  else:
    self.delayR.delayTime = delayTime + (lfoR.process() * lfoAmount)
    wet = self.delayR.process(dry)

  outputSamples[0] = wet * self.wet + dry * self.dry

proc newFlanger(): Machine =
  result = new(Flanger)
  result.init()

registerMachine("flanger", newFlanger, "fx")



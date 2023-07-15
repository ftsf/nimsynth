import math

import nico

import common
import util

import core/envelope


{.this:self.}

type Gate = ref object of Machine
  open: bool
  env: Envelope
  level: float32


method init(self: Gate) =
  procCall init(Machine(self))

  nInputs = 1
  nOutputs = 1
  stereo = true

  name = "gate"

  self.globalParams.add([
    Parameter(name: "open", kind: Trigger, min: 0.0, max: 1.0, default: 1.00, onchange: proc(newValue: float32, voice: int) =
      let nv = newValue.bool
      if nv:
        self.env.trigger()
      else:
        self.env.release()
      self.open = nv
    ),
    Parameter(name: "level", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.level = newValue
    ),
    Parameter(name: "attack", kind: Float, min: 0.0001, max: 1.0, default: 0.05, onchange: proc(newValue: float32, voice: int) =
      self.env.a = newValue
    ),
    Parameter(name: "decay", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.env.d = newValue
    ),
    Parameter(name: "sustain", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.env.s = newValue
    ),
    Parameter(name: "release", kind: Float, min: 0.0001, max: 1.0, default: 0.05, onchange: proc(newValue: float32, voice: int) =
      self.env.r = newValue
    ),
  ])

  setDefaults()

method process(self: Gate) {.inline.} =
  if sampleId mod 2 == 0:
    discard env.process()

  outputSamples[0] = getInput() * lerp(level, 1.0, env.value)

proc newGate(): Machine =
  var gate = new(Gate)
  gate.init()
  return gate

registerMachine("gate", newGate, "fx")

## Takes an input note parameter and transposes it

{.this:self.}

import math

import common
import util

import core.filter


type Transposer = ref object of Machine
  octaves: int
  semitones: int

method init(self: Transposer) =
  procCall init(Machine(self))

  nBindings = 1
  bindings.setLen(1)

  name = "transp"

  globalParams.add([
    Parameter(name: "input", kind: Note, deferred: true, min: OffNote, max: 255.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      if self.bindings[0].isBound():
        var (voice,param) = self.bindings[0].getParameter()
        if newValue == OffNote:
          param.value = OffNote
        else:
          param.value = newValue + (self.octaves * 12 + self.semitones).float
        param.onchange(param.value, voice)
    ),
    Parameter(name: "oct", kind: Int, min: -4.0, max: 4.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.octaves = newValue.int
    ),
    Parameter(name: "semi", kind: Int, min: -12.0, max: 12.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.semitones = newValue.int
    ),
  ])

  setDefaults()

method createBinding(self: Transposer, slot: int, targetMachine: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, targetMachine, paramId)

  # match input to be the same as the target param
  var (voice,param) = targetMachine.getParameter(paramId)
  var inputParam = globalParams[0].addr
  inputParam.kind = param.kind
  inputParam.min = param.min
  inputParam.max = param.max
  inputParam.getValueString = param.getValueString


proc newTransposer(): Machine =
  var m = new(Transposer)
  m.init()
  return m

registerMachine("transp", newTransposer, "util")

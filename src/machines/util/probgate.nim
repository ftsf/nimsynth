## Takes an input and potentially passes it on based on probability

import common
import random


{.this:self.}

type
  ProbGate = ref object of Machine
    probability: float32

method init(self: ProbGate) =
  procCall init(Machine(self))
  nInputs = 0
  nOutputs = 0
  nBindings = 1
  name = "probgate"
  bindings.setLen(1)

  globalParams.add([
    Parameter(kind: Float, name: "%", min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float32, voice: int) =
      self.probability = newValue
    ),
    Parameter(kind: Float, name: "input", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      if rand(1.0) <= self.probability:
        if self.bindings[0].isBound():
          var (voice,param) = self.bindings[0].getParameter()
          param.value = newValue
          param.onchange(newValue, voice)
    ),
  ])

  setDefaults()

method createBinding*(self: ProbGate, slot: int, target: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, target, paramId)

  # match input to be the same as the target param
  var (voice,param) = target.getParameter(paramId)
  var inputParam = globalParams[1].addr
  inputParam.kind = param.kind
  inputParam.min = param.min
  inputParam.max = param.max
  inputParam.getValueString = param.getValueString

proc newProbGate(): Machine =
  var pg = new(ProbGate)
  pg.init()
  return pg


registerMachine("%gate", newProbGate, "util")

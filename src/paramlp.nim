## Takes an input parameter and smoothes it and passes it on

{.this:self.}

import common
import filter
import math
import util

type ParamLP = ref object of Machine
  filter: OnePoleFilter
  targetValue: float
  actualValue: float

method init(self: ParamLP) =
  procCall init(Machine(self))

  nBindings = 1
  bindings.setLen(1)

  name = "PARAMlp"

  filter.init()
  filter.kind = Lowpass

  globalParams.add([
    Parameter(name: "input", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.targetValue = newValue
    ),
    Parameter(name: "smooth", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.filter.setCutoff(exp(lerp(-12.0, 0.0, 1.0-newValue)))
      self.filter.calc()
    ),
  ])

  setDefaults()

method createBinding(self: ParamLP, slot: int, targetMachine: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, targetMachine, paramId)

  # match input to be the same as the target param
  var (voice,param) = targetMachine.getParameter(paramId)
  var inputParam = globalParams[0].addr
  inputParam.kind = param.kind
  inputParam.min = param.min
  inputParam.max = param.max
  inputParam.getValueString = param.getValueString


method process(self: ParamLP) =
  # take input param and lowpass it and send it to binding
  self.actualValue = filter.process(self.targetValue)

  if bindings[0].isBound:
    var (voice, param) = bindings[0].getParameter()
    param.value = self.actualValue
    param.onchange(self.actualValue, voice)

proc newParamLP(): Machine =
  var m = new(ParamLP)
  m.init()
  return m


registerMachine("PARAMlp", newParamLP, "util")

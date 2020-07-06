import strutils
import math
import util

import common

import core.envelope


# envelope

{.this:self.}

type
  EADSRMachine = ref object of Machine
    env: Envelope
    lastval: float32
    min: float32
    max: float32

method init(self: EADSRMachine) =
  procCall init(Machine(self))
  name = "eadsr"
  nInputs = 0
  nOutputs = 0
  stereo = false

  nBindings = 1
  bindings.setLen(1)

  env.init()

  globalParams.add([
    Parameter(kind: Trigger, name: "trigger", min: 0, max: 1, onchange: proc(newValue: float, voice: int) =
      if newValue == OffNote or newValue == 0:
        env.release()
      else:
        env.trigger()
    ),
    Parameter(kind: Float, name: "min", min: -10000'f, max: 10000.0'f, default: 0.0'f, onchange: proc(newValue: float, voice: int) =
      self.min = newValue
    ),
    Parameter(kind: Float, name: "max", min: -10000'f, max: 10000.0'f, default: 1.0'f, onchange: proc(newValue: float, voice: int) =
      self.max = newValue
    ),
    Parameter(name: "a", kind: Float, separator: true, min: 0.0, max: 5.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      self.env.a = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "d", kind: Float, min: 0.0, max: 5.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.env.d = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "ds", kind: Float, min: 0.1, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.env.decayExp = newValue
    ),
    Parameter(name: "s", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.env.s = newValue
    ),
    Parameter(name: "r", kind: Float, min: 0.0, max: 5.0, default: 0.01, onchange: proc(newValue: float, voice: int) =
      self.env.r = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
  ])

  setDefaults()

method createBinding*(self: EADSRMachine, slot: int, target: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, target, paramId)

  # match input to be the same as the target param
  var (voice,param) = target.getParameter(paramId)
  var inputParam = globalParams[1].addr
  inputParam.kind = param.kind
  inputParam.min = param.min
  inputParam.max = param.max
  inputParam.getValueString = param.getValueString

  inputParam = globalParams[2].addr
  inputParam.kind = param.kind
  inputParam.min = param.min
  inputParam.max = param.max
  inputParam.getValueString = param.getValueString

method process(self: EADSRMachine) =
  var val = env.process()

  if bindings[0].isBound() and val != lastval:
    var (voice,param) = bindings[0].getParameter()
    param.value = lerp(self.min, self.max, val)
    param.onchange(param.value, voice)

  lastval = val

proc newEADSRMachine(): Machine =
 var m = new(EADSRMachine)
 m.init()
 return m

registerMachine("eadsr", newEADSRMachine, "generator")

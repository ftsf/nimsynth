import common
import env
import math
import strutils

# envelope

{.this:self.}

type
  ADSRMachine = ref object of Machine
    env: Envelope

method init(self: ADSRMachine) =
  procCall init(Machine(self))
  name = "adsr"
  nInputs = 0
  nOutputs = 1
  stereo = false

  env.init()

  globalParams.add([
    Parameter(kind: Trigger, name: "trigger", min: 0, max: 1, onchange: proc(newValue: float, voice: int) =
      if newValue == 0.float:
        env.release()
      else:
        env.trigger()
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

method process(self: ADSRMachine) =
  outputSamples[0] = env.process()

proc newADSRMachine(): Machine =
 var m = new(ADSRMachine)
 m.init()
 return m

registerMachine("adsr", newADSRMachine, "components")

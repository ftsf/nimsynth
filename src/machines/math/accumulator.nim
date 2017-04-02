import common
import math

type
  Accumulator = ref object of Machine
    value: float
    max: float

{.this:self.}

method init(self: Accumulator) =
  procCall init(Machine(self))
  name = "acc"
  nOutputs = 0
  nInputs = 0
  stereo = false

  nBindings = 1
  bindings.setLen(1)

  globalParams.add([
    Parameter(name: "add", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.value += newValue
      if self.value >= self.max:
        # trigger
        if self.bindings[0].isBound():
          var (voice,param) = self.bindings[0].getParameter()
          param.value = 1.0
          param.onchange(1.0, voice)
      self.value = self.value mod self.max
      self.globalParams[2].value = self.value
    ),
    Parameter(name: "max", kind: Float, min: 1.0, max: 1000.0, default: 4.0, onchange: proc(newValue: float, voice: int) =
      self.max = newValue
      if self.value >= self.max:
        self.value = self.value mod self.max
      self.globalParams[2].value = self.value
    ),
    Parameter(name: "value", kind: Float, min: 0.0, max: 1000.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.value = newValue
    ),
  ])
  setDefaults()

proc newMachine(): Machine =
  var m = new(Accumulator)
  m.init()
  return m

registerMachine("acc", newMachine, "math")

import common

{.this:self.}

type
  Master* = ref object of Machine
    gain: float

method init*(self: Master) =
  procCall init(Machine(self))
  name = "master"
  nInputs = 1
  nOutputs = 0
  gain = 1.0
  globalParams.add([
    Parameter(kind: Float, name: "volume", min: 0.0, max: 10.0, default: 1.0, value: 1.0, onchange: proc(newValue: float, voice: int) =
      self.gain = newValue
    ),
  ])

method process*(self: Master): float32 =
  for input in inputs:
    result += input.machine.process() * input.gain
  result *= gain

proc newMaster*(): Master =
  result = new(Master)
  result.init()

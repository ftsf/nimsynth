import common

# very basic amp

type AmpMachine = ref object of Machine
  amp: float

{.this:self.}

method init(self: AmpMachine) =
  procCall init(Machine(self))
  name = "amp"
  nOutputs = 1
  nInputs = 1
  stereo = false

  self.globalParams.add([
    Parameter(name: "amp", kind: Float, min: -10.0, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.amp = newValue
    ),
  ])
  setDefaults()

method process(self: AmpMachine) =
  outputSamples[0] = getInput() * amp

proc newMachine(): Machine =
  var m = new(AmpMachine)
  m.init()
  return m

registerMachine("amp", newMachine, "fx")

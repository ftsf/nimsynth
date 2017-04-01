import common

{.this:self.}

type
  E2AMachine = ref object of Machine
    value: float

# converts an event to an audio signal

method init(self: E2AMachine) =
  procCall init(Machine(self))
  name = "e2a"
  nInputs = 0
  nOutputs = 1
  stereo = false

  globalParams.add([
    Parameter(name: "value", kind: Float, min: -1000.0, max: 1000.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.value = newValue
    ),
  ])

  setDefaults()

method process(self: E2AMachine) =
  outputSamples[0] = value

proc newE2A(): Machine =
  var m = new(E2AMachine)
  m.init()
  return m

registerMachine("e2a", newE2A, "convert")

import common
import osc

type
  NoiseMachine = ref object of Machine
    osc: Osc

{.this:self.}

method init(self: NoiseMachine) =
  procCall init(Machine(self))
  name = "noise"
  nInputs = 0
  nOutputs = 1
  stereo = false
  osc.kind = Noise

  setDefaults()


method process(self: NoiseMachine) {.inline.} =
  cachedOutputSample = osc.process()

proc newNoiseMachine(): Machine =
  result = new(NoiseMachine)
  result.init()

registerMachine("noise", newNoiseMachine)

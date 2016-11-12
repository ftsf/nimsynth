# machine that provides audio input from the system
# maybe allow to choose the inputs

import common

type
  AudioInMachine = ref object of Machine

{.this:self.}

method init(self: AudioInMachine) =
  procCall init(Machine(self))
  name = "input"
  nInputs = 0
  nOutputs = 1
  stereo = true
  setDefaults()


method process(self: AudioInMachine) {.inline.} =
  outputSamples[0] = inputSample

proc newMachine(): Machine =
  var m = new(AudioInMachine)
  m.init()
  return m

registerMachine("input", newMachine, "generator")

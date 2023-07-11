import ../../common
import math
import ../../util

# sample and hold machine
# when triggered, captures its sample value and holds that
type
  SANDH = ref object of Machine
    sampleValue: float32

{.this:self.}

method init(self: SANDH) =
  procCall init(Machine(self))
  name = "s+h"
  nOutputs = 1
  nInputs = 1
  stereo = false

  globalParams.add([
    Parameter(name: "trigger", kind: Trigger, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.sampleValue = self.getInput()
    ),
  ])
  setDefaults()

method process(self: SANDH) {.inline.} =
  outputSamples[0] = sampleValue

proc newSANDH(): Machine =
  result = new(SANDH)
  result.init()

registerMachine("s+h", newSANDH, "fx")

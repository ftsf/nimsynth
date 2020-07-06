import common

import core.filter


type
  DCRemover = ref object of Machine
    filterL: OnePoleFilter
    filterR: OnePoleFilter

const cutoff = 10.0'f

{.this:self.}

method init(self: DCRemover) =
  procCall init(Machine(self))
  name = "dc"
  nInputs = 1
  nOutputs = 1
  stereo = true
  filterL.init()
  filterR.init()

  filterL.kind = Highpass
  filterR.kind = Highpass
  filterL.setCutoff(cutoff)
  filterR.setCutoff(cutoff)

  filterL.calc()
  filterR.calc()

  setDefaults()


method process(self: DCRemover) {.inline.} =
  outputSamples[0] = 0.0
  for input in mitems(self.inputs):
    outputSamples[0] += input.getSample()

  if sampleId mod 2 == 0:
    outputSamples[0] = filterL.process(outputSamples[0])
  else:
    outputSamples[0] = filterR.process(outputSamples[0])

proc newDCRemover(): Machine =
  var dc = new(DCRemover)
  dc.init()
  return dc

registerMachine("dc", newDCRemover, "util")

import common

import core.lfsr


{.this:self.}

type
  LFSRMachine = ref object of Machine
    lfsr: LFSR
    freq: float
    nextClick: int

method init(self: LFSRMachine) =
  procCall init(Machine(self))
  name = "lfsr"
  nInputs = 0
  nOutputs = 1
  stereo = false

  lfsr.init()

  globalParams.add([
    Parameter(kind: Float, name: "freq", min: 0.0001, max: 24000.0, default: 440.0, onchange: proc(newValue: float, voice: int) =
      self.freq = newValue
      self.nextClick = ((1.0 / self.freq) * sampleRate).int
    ),
  ])

  setDefaults()

method process(self: LFSRMachine) =
  nextClick -= 1
  if nextClick <= 0:
    discard lfsr.process()
    nextClick = ((1.0 / freq) * sampleRate).int
  outputSamples[0] = lfsr.output

proc newMachine(): Machine =
 var m = new(LFSRMachine)
 m.init()
 return m

registerMachine("lfsr", newMachine, "generator")

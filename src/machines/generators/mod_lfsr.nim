import common

import core.lfsr


{.this:self.}

type
  LFSRMachine = ref object of Machine
    lfsr: LFSR
    freq: float32
    nextClick: int

method init(self: LFSRMachine) =
  procCall init(Machine(self))
  name = "lfsr"
  nInputs = 0
  nOutputs = 1
  stereo = false
  nextClick = 1

  lfsr.init()

  globalParams.add([
    Parameter(kind: Float, name: "freq", min: 20.0'f, max: 24000.0'f, default: 440.0'f, onchange: proc(newValue: float, voice: int) =
      self.freq = clamp(newValue, 20.0'f, 24000'f)
    ),
  ])

  setDefaults()

method process(self: LFSRMachine) =
  nextClick -= 1
  if nextClick <= 0:
    discard lfsr.process()
    if freq <= 1.0'f:
      nextClick = sampleRate.int
    else:
      nextClick = ((1.0 / freq) * sampleRate).int
  outputSamples[0] = lfsr.output

proc newMachine(): Machine =
 var m = new(LFSRMachine)
 m.init()
 return m

registerMachine("lfsr", newMachine, "generator")

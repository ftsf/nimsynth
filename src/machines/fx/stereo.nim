import common
import math
import core/filter

type
  Stereo* = ref object of Machine
    pan: float32
    allpassL: AllpassFilter
    allpassR: AllpassFilter

method init*(self: Stereo) =
  procCall init(Machine(self))
  self.name = "stereo"
  self.nInputs = 1
  self.nOutputs = 1
  self.stereo = true
  self.globalParams.add([
    Parameter(kind: Float, name: "pan", min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float32, voice: int) =
      self.pan = newValue
    ),
    Parameter(kind: Float, name: "phaseL", min: -1.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.allpassL.cutoff = newValue
    ),
    Parameter(kind: Float, name: "phaseR", min: -1.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.allpassR.cutoff = newValue
    )
  ])
  self.setDefaults()

method process*(self: Stereo) =
  self.outputSamples[0] = 0.0

  for input in self.inputs:
    self.outputSamples[0] += input.getSample()

  if sampleId mod 2 == 0:
    self.outputSamples[0] = self.allpassL.process(self.outputSamples[0])
    self.outputSamples[0] *= sin(self.pan * PI * 0.5)
  else:
    self.outputSamples[0] = self.allpassR.process(self.outputSamples[0])
    self.outputSamples[0] *= cos(self.pan * PI * 0.5)

proc newMachine(): Machine =
  var m = new(Stereo)
  m.init()
  return m

registerMachine("stereo", newMachine, "fx")

import math
import common

{.this:self.}

type
  DistortionKind* = enum
    Foldback
    HardClip
    SoftClip
  Distortion* = object of RootObj
    kind*: DistortionKind
    preGain*: float
    threshold*: float
    postGain*: float
    mix: float
    feedback: float

proc process*(self: Distortion, sample: float32): float32 =
  var drySignal = sample * preGain
  var wetSignal = drySignal
  if abs(wetSignal) > threshold:
    case kind:
    of Foldback:
      wetSignal = abs(abs((wetSignal - threshold) mod (threshold * 4.0)) - threshold * 2.0) - threshold
    of HardClip:
      wetSignal = clamp(wetSignal, -threshold, threshold)
    of SoftClip:
      wetSignal = tanh(wetSignal * (1.0 / threshold))
  result = (wetSignal * postGain * mix) + (drySignal * (1.0 - mix))

type
  DistortionMachine = ref object of Machine
    distortion: Distortion

method init(self: DistortionMachine) =
  procCall init(Machine(self))
  name = "dist"
  nInputs = 1
  nOutputs = 1
  stereo = true

  self.globalParams.add([
    Parameter(name: "dist", kind: Int, min: DistortionKind.low.float, max: DistortionKind.high.float, default: HardClip.float, onchange: proc(newValue: float, voice: int) =
      self.distortion.kind = newValue.DistortionKind
    , getValueString: proc(value: float, voice: int): string =
      return $value.DistortionKind
    ),
    Parameter(name: "pre", kind: Float, min: 0.0, max: 2.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.distortion.preGain = newValue
    ),
    Parameter(name: "mix", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.distortion.mix = newValue
    ),
    Parameter(name: "threshold", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.distortion.threshold = newValue
    ),
    Parameter(name: "post", kind: Float, min: 0.0, max: 2.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.distortion.postGain = newValue
    )
  ])

  setDefaults()


method process(self: DistortionMachine) {.inline.} =
  outputSamples[0] = getInput()
  outputSamples[0] = self.distortion.process(outputSamples[0])

proc newDistortionMachine(): Machine =
  result = new(DistortionMachine)
  result.init()

registerMachine("distortion", newDistortionMachine)

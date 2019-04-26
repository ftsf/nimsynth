import math

import nico

import common
import core.envelope


{.this:self.}

type EnvDetectorKind = enum
  Peak
  RMS

type EnvDetector = object of RootObj
  kind: EnvDetectorKind
  attack,release: float
  value: float

const rmsSize = 512

proc process(self: var EnvDetector, sample: float32) =
  let sample = abs(sample)
  if sample > value:
    value = attack * (value - sample) + sample
  else:
    value = release * (value - sample) + sample

type Compressor = ref object of Machine
  threshold: float
  ratio: float
  invRatio: float
  env: EnvDetector
  preGain,postGain: float
  inputLevelL: float
  inputLevelR: float
  inputSample: float
  reduction: float
  rms: array[rmsSize, float32]


method init(self: Compressor) =
  procCall init(Machine(self))

  nInputs = 2
  nOutputs = 1
  stereo = true

  name = "comp"

  self.globalParams.add([
    Parameter(name: "threshold", kind: Float, min: 0.0, max: 1.0, default: 1.00, onchange: proc(newValue: float, voice: int) =
      self.threshold = newValue
    ),
    Parameter(name: "ratio", kind: Float, min: 1.0, max: 12.0, default: 3.00, onchange: proc(newValue: float, voice: int) =
      self.ratio = newValue
      self.invRatio = 1.0/newValue
    ),
    Parameter(name: "attack", kind: Float, min: 0.0001, max: 0.5, default: 0.01, onchange: proc(newValue: float, voice: int) =
      self.env.attack = exp(ln(0.01) / (newValue * sampleRate))
    ),
    Parameter(name: "release", kind: Float, min: 0.01, max: 5.0, default: 0.05, onchange: proc(newValue: float, voice: int) =
      self.env.release = exp(ln(0.01) / (newValue * sampleRate))
    ),
    Parameter(name: "detector", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.env.kind = newValue.EnvDetectorKind
    ),
    Parameter(name: "pre gain", kind: Float, min: 0.0, max: 2.0, default: 1.00, onchange: proc(newValue: float, voice: int) =
      self.preGain = newValue
    ),
    Parameter(name: "post gain", kind: Float, min: 0.0, max: 2.0, default: 1.00, onchange: proc(newValue: float, voice: int) =
      self.postGain = newValue
    ),
  ])

  setDefaults()

proc getReduction(self: Compressor, input: float32): float32 =
  let slope = 1.0 - invRatio
  return if input >= threshold: slope * (threshold - input) else: 0.0

method process(self: Compressor) {.inline.} =
  # set input level
  if inputs.len == 0:
    inputLevelL = 0.0
    inputLevelR = 0.0
    outputSamples[0] = 0.0
    return

  let s = getInput() * preGain
  self.inputSample = s
  let s1 = if hasInput(1): getInput(1) * preGain else: s

  if sampleId mod 2 == 0:
    inputLevelL = abs(s1)
  else:
    inputLevelR = abs(s1)

  env.process(max(inputLevelL, inputLevelR))

  reduction = getReduction(env.value)

  let compGain = 1.0 + reduction

  outputSamples[0] = s * compGain * postGain

proc newCompressor(): Machine =
  var comp = new(Compressor)
  comp.init()
  return comp

method drawExtraData(self: Compressor, x,y,w,h: int) =
  var yv = y
  setColor(11)
  rectfill(x, yv, x + (w-1).float * abs(inputSample), yv + 4)
  yv += 5
  setColor(10)
  rectfill(x + (w-1) - (w-1).float * abs(reduction), yv, x + (w-1), yv + 4)

  yv += 5
  # draw plot
  setColor(8)
  var xv = x
  while xv < x+w-1:
    let input = (xv - x).float / w.float
    let output = clamp(input + getReduction(input), 0.0, 1.0)
    pset(xv, yv + w - (output * w.float))
    xv += 1
  setColor(9)
  xv = x
  while xv < x+(w-1).float * env.value:
    let input = (xv - x).float / w.float
    let output = clamp(input + getReduction(input), 0.0, 1.0)
    line(xv, yv + w, xv, yv + w - (output * w.float))
    xv += 1

method getInputName(self: Compressor, inputId: int): string =
  if inputId == 0:
    return "main"
  else:
    return "sidechain"


registerMachine("compressor", newCompressor, "fx")

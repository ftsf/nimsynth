import common
import math
import util
import master

# sample and hold machine
type
  ClockRateUnit = enum
    Samples
    KSamples
    Beats
  SANDH = ref object of Machine
    sampleValue: float32
    triggered: bool
    clockRateUnit: ClockRateUnit  # as unit of sampleRate
    clockRate: float # as unit of sampleRate
    clock: float
    bitDepth: int

{.this:self.}

method init(self: SANDH) =
  procCall init(Machine(self))
  name = "s+h"
  nOutputs = 1
  nInputs = 1
  stereo = false

  globalParams.add([
    Parameter(name: "trigger", kind: Trigger, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.triggered = newValue == 1.0
    ),
    Parameter(name: "rate", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.clockRate = newValue
    , getValueString: proc(value: float, voice: int): string =
        case self.clockRateUnit:
        of Samples:
          return $(exp(lerp(-8.0, -0.8, value)) * sampleRate).int
        of KSamples:
          return $((exp(lerp(-8.0, -0.8, value)) * sampleRate).int div 1000)
        of Beats:
          return $(value * 100).int
    ),
    Parameter(name: "units", kind: Int, min: ClockRateUnit.low.float, max: ClockRateUnit.high.float, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.clockRateUnit = newValue.ClockRateUnit
    , getValueString: proc(value: float, voice: int): string =
        return $(value.ClockRateUnit)
    ),
    Parameter(name: "bitdepth", kind: Int, min: 1.0, max: 32.0, default: 32.0, onchange: proc(newValue: float, voice: int) =
      self.bitDepth = newValue.int
      let maxValue = pow(2.0,self.bitDepth.float).int
      echo "max Value: " & $maxValue
    ),
  ])

  setDefaults()

proc snapToBitDepth(sample: float32, bitDepth: int): float32 =
  let maxValue = pow(2.0,bitDepth.float).int
  let s = (clamp(sample, -1.0, 1.0) + 1.0) / 2.0 # convert to float 0..1
  let sint = (s * maxValue.float).int # convert to int
  # convert back to float
  result = ((sint.float / maxValue.float) - 0.5) * 2.0

method process(self: SANDH) {.inline.} =
  if clockRate > 0.0:
    case clockRateUnit:
    of Samples:
      clock += exp(lerp(-8.0, -0.8, clockRate))
    of KSamples:
      clock += exp(lerp(-8.0, -0.8, clockRate)) / 1000.0
    of Beats:
      clock += ((clockRate * 100.0).floor / (sampleRate / beatsPerSecond())).float

    if clock >= 1.0:
      triggered = true
      clock -= 1.0
  if triggered:
    sampleValue = snapToBitDepth(getInput(), bitDepth)
    triggered = false
  outputSamples[0] = sampleValue

proc newSANDH(): Machine =
  result = new(SANDH)
  result.init()

registerMachine("s+h", newSANDH, "fx")

import unittest

suite "bitrate":
  test "snapToBitDepth":
    check(snapToBitDepth(0.0, 1) == 0.0)
    check(snapToBitDepth(1.0, 1) == 1.0)
    check(snapToBitDepth(-1.0, 1) == -1.0)

    check(snapToBitDepth(0.0, 2) == 0.0)
    check(snapToBitDepth(1.0, 2) == 1.0)
    check(snapToBitDepth(-1.0, 2) == -1.0)

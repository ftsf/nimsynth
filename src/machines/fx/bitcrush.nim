import common
import math

type
  BitCrush = ref object of Machine
    bitDepth: uint8

proc snapToBitDepth(sample: float32, bitDepth: uint8): float32 =
  let maxValue = pow(2.0,bitDepth.float).int
  let s = (clamp(sample, -1.0, 1.0) + 1.0) / 2.0 # convert to float 0..1
  let sint = (s * maxValue.float).int # convert to int
  # convert back to float
  result = ((sint.float / maxValue.float) - 0.5) * 2.0


{.this:self.}

method init(self: BitCrush) =
  procCall init(Machine(self))
  name = "bitcrush"
  nOutputs = 1
  nInputs = 1
  stereo = false

  globalParams.add([
    Parameter(name: "depth", kind: Int, min: 1.0, max: 32.0, default: 32.0, onchange: proc(newValue: float, voice: int) =
      self.bitDepth = newValue.uint8
    ),
  ])
  setDefaults()

method process(self: BitCrush) {.inline.} =
  outputSamples[0] = snapToBitDepth(getInput(), bitDepth)

proc newBitCrush(): Machine =
  var m = new(BitCrush)
  m.init()
  return m

registerMachine("bitcrush", newBitCrush, "fx")

import unittest

suite "bitrate":
  test "snapToBitDepth":
    check(snapToBitDepth(-0.1, 1) == -1.0)
    check(snapToBitDepth(1.0, 1) == 1.0)
    check(snapToBitDepth(-1.0, 1) == -1.0)

    check(snapToBitDepth(0.0, 2) == 0.0)
    check(snapToBitDepth(1.0, 2) == 1.0)
    check(snapToBitDepth(-1.0, 2) == -1.0)

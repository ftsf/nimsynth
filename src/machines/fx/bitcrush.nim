import ../../common
import math
import strutils

type
  BitCrush = ref object of Machine
    bitDepth: uint8

proc snapToBitDepth(sample: float32, bitDepth: uint8): float32 =
  if bitDepth == 32:
    return sample
  let s0to1 = clamp(sample * 0.5'f + 0.5'f, 0'f, 1'f)
  let maxVal = 1'u32 shl bitDepth - 1'u32
  let sint = min(maxVal, (s0to1 * (maxVal + 1'u32).float32).uint32)
  let o = (sint.float32 / maxVal.float32) * 2.0'f - 1.0'f
  return o

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
    check(snapToBitDepth(0.1, 1) == 1.0)
    check(snapToBitDepth(-0.1, 1) == -1.0)
    check(snapToBitDepth(1.0, 1) == 1.0)
    check(snapToBitDepth(-1.0, 1) == -1.0)

    check(snapToBitDepth(0.0, 2) == 0.0)
    check(snapToBitDepth(1.0, 2) == 1.0)
    check(snapToBitDepth(-1.0, 2) == -1.0)

import math

{.this:self.}

type
  LFSR* = object
    start: int
    lfsr: int
    period: uint
    output*: float32

proc process*(self: var LFSR): float32 =
  let lsb: uint = (lfsr and 1).uint
  lfsr = lfsr shr 1
  if lsb == 1:
    lfsr = lfsr xor 0xb400;
  result = if lsb == 1: 1.0 else: -1.0
  output = result

proc init*(self: var LFSR, seed = 0xfeed) =
  lfsr = seed

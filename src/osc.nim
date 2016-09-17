import math
import random

{.this:self.}

const sampleRate = 48000.0
const invSampleRate = 1.0/sampleRate

type
  OscKind* = enum
    Sin
    Tri
    Sqr
    Saw
    Noise
  Osc* = object of RootObj
    kind*: OscKind
    phase*: float
    freq*: float
    pulseWidth*: float

proc process*(self: var Osc): float32 {.inline.} =
  case kind:
  of Sin:
    result = sin(phase).float32
  of Tri:
    result = ((abs((phase mod TAU) / TAU * 2.0 - 1.0)*2.0 - 1.0) * 1.0/2.0).float32
  of Sqr:
    result = ((if phase mod TAU < (TAU * clamp(pulseWidth, 0.001, 0.999)): 1.0 else: -1.0) * 1.0/3.0).float32
  of Saw:
    result = (((phase mod TAU) - PI) * 1.0/3.0).float32
  of Noise:
    result = (random(2.0)-1.0).float32
  phase += (freq * invSampleRate)
  if phase > TAU:
    phase -= TAU


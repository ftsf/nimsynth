import math

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

proc update*(self: Distortion, sample: float32): float32 =
  result = sample * preGain
  if result > threshold or result < -threshold:
    case kind:
    of Foldback:
      result = abs(abs((result - threshold) mod (threshold * 4.0)) - threshold * 2.0) - threshold
    of HardClip:
      result = clamp(result, -threshold, threshold)
    of SoftClip:
      result = tanh(result)
  result *= postGain

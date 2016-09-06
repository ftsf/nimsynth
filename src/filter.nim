import math

{.this:self.}

type
  FilterKind* = enum
    Lowpass
    Highpass
  Filter* = object of RootObj
    kind*: FilterKind
    a0,a1,a2,b1,b2: float
    cutoff*: float
    cutoffMod*: float
    resonance*: float
    resonanceMod*: float
    thev: float
    peakGain*: float
    z1,z2: float

proc calc*(self: var Filter) =
  let cutoff = clamp(cutoff + cutoffMod, 0.0001, 0.499)
  let resonance = clamp(resonance + resonanceMod, 0.0001, 5.0)
  var norm: float
  let V = pow(10.0, abs(peakGain) / 20.0)
  let K = tan(PI * cutoff)
  case kind:
  of Lowpass:
    norm = 1.0 / (1.0 + K / resonance + K * K)
    a0 = K * K * norm
    a1 = 2.0 * a0
    a2 = a0
    b1 = 2.0 * (K * K - 1.0) * norm
    b2 = (1.0 - K / resonance + K * K) * norm
  of Highpass:
    norm = 1.0 / (1.0 + K / resonance + K * K)
    a0 = 1.0 * norm
    a1 = -2.0 * a0
    a2 = a0
    b1 = 2.0 * (K * K - 1.0) * norm
    b2 = (1.0 - K / resonance + K * K) * norm;

proc process*(self: var Filter, sample: float32): float32 =
  result = sample * a0 + z1
  z1 = sample * a1 + z2 - b1 * result
  z2 = sample * a2 - b2 * result

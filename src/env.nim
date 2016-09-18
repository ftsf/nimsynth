import util

import common
import filter
import math

{.this:self.}

type
  EnvState* = enum
    End
    Attack
    Decay
    Sustain
    Release
  DecayKind* = enum
    Linear
    Exponential
  Envelope* = object of RootObj
    a*,d*,s*,r*: float
    decayKind*: DecayKind
    decayExp*: float
    state*: EnvState
    time: float
    released: bool
    filter: OnePoleFilter
    targetLevel: float
    actualLevel: float

proc process*(self: var Envelope): float32 =
  case state:
  of Attack:
    if a == 0.0:
      state = Decay
      targetLevel = 1.0
      time = 0.0
    else:
      targetLevel = lerp(0.0, 1.0, time / a)
      time += invSampleRate
    if time > a:
      state = Decay
      time -= a
  of Decay:
    if d == 0.0:
      state = Sustain
      targetLevel = s
      time = 0.0
    else:
      case decayKind:
      of Linear:
        targetLevel = lerp(1.0, s, time / d)
      of Exponential:
        let x = time / d
        targetLevel = lerp(s, 1.0, pow(decayExp, -x))
      time += invSampleRate
      if time > d:
        state = Sustain
        time -= d
  of Sustain:
    targetLevel = s
    if released:
      state = Release
      time = 0.0
  of Release:
    if r == 0.0:
      targetLevel = 0.0
      state = End
      time = 0.0
    else:
      if time > r:
        state = End
      else:
        targetLevel = lerp(s, 0.0, time / r)
      time += invSampleRate
  else:
    targetLevel = 0.0

  actualLevel = lerp(actualLevel, targetLevel, 0.5)
  return actualLevel

proc trigger*(self: var Envelope) =
  state = Attack
  time = 0.0
  released = false

proc release*(self: var Envelope) =
  released = true

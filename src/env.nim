import util

import common
import filter

{.this:self.}

type
  EnvState* = enum
    End
    Attack
    Decay
    Sustain
    Release
  Envelope* = object of Modulator
    a*,d*,s*,r*: float
    state*: EnvState
    time: float
    released: bool
    filter: OnePoleFilter
    targetLevel: float
    actualLevel: float

proc process*(self: var Envelope): float32 =
  case state:
  of Attack:
    targetLevel = lerp(0.0, 1.0, time / a)
    time += invSampleRate
    if time > a:
      state = Decay
      time -= a
  of Decay:
    targetLevel = lerp(1.0, s, time / d)
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

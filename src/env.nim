import util

import common

{.this:self.}

type
  EnvState = enum
    End
    Attack
    Decay
    Sustain
    Release
  Envelope* = object of RootObj
    a*,d*,s*,r*: float
    state: EnvState
    time: float
    released: bool

proc update*(self: var Envelope): float32 =
  case state:
  of Attack:
    result = lerp(0.0, 1.0, time / a)
    time += invSampleRate
    if time > a:
      state = Decay
      time -= a
  of Decay:
    result = lerp(1.0, s, time / d)
    time += invSampleRate
    if time > d:
      state = Sustain
      time -= d
  of Sustain:
    result = s
    if released:
      state = Release
      time = 0.0
  of Release:
    if time > r:
      result = 0.0
    else:
      result = lerp(s, 0.0, time / r)
    time += invSampleRate
  else:
    result = 0.0

proc trigger*(self: var Envelope) =
  state = Attack
  time = 0.0
  released = false

proc release*(self: var Envelope) =
  released = true

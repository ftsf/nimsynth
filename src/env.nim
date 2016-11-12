import util

import common
import filter
import math
import pico

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
    velocity*: float

proc value*(self: Envelope): float32 =
  return self.targetLevel

proc process*(self: var Envelope): float32 =
  case state:
  of Attack:
    if a == 0.0:
      state = Decay
      targetLevel = velocity
      time = 0.0
    else:
      targetLevel = lerp(0.0, velocity, time / a)
      time += invSampleRate
    if time > a:
      state = Decay
      time -= a
  of Decay:
    if d == 0.0:
      state = Sustain
      targetLevel = s
      time = 0.0
    elif time > d:
        state = Sustain
        time -= d
    else:
      case decayKind:
      of Linear:
        targetLevel = lerp(velocity, s, time / d)
      of Exponential:
        let x = time / d
        targetLevel = lerp(velocity, s, 1.0 - pow(1.0-x, decayExp))
      time += invSampleRate
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

  return targetLevel

proc init*(self: var Envelope) =
  filter.kind = Lowpass
  filter.init()
  filter.setCutoff(exp(-4.0))
  decayExp = 1.0

proc trigger*(self: var Envelope, vel = 1.0) =
  state = Attack
  time = 0.0
  velocity = vel
  released = false

proc triggerIfReady*(self: var Envelope, vel = 1.0) =
  if state == End or released:
    state = Attack
    time = 0.0
    velocity = vel
    released = false

proc release*(self: var Envelope) =
  released = true

proc drawEnv*(a,d,dexp,s,r: float, x,y,w,h: int) =
  ## draws the envelope to the screen

  let len = a + d + 1.0 + r

  var last: float

  for i in 0..w-1:
    let time = (i.float / w.float) * len
    var val = 0.0
    if time <= a:
      if a == 0:
        val = 1.0
      else:
        val = lerp(0.0, 1.0, time / a)
    elif time <= a + d:
      if d == 0:
        val = s
      else:
        let decayTime = (time - a) / d
        if dexp > 0:
          val = lerp(1.0, s, 1.0 - pow(1.0-decayTime, dexp))
        else:
          val = lerp(1.0, s, decayTime)
    elif time <= a + d + 1.0:
      val = s
    elif time > a + d + 1.0:
      let releaseTime = (time - a - d - 1.0) / r
      if r == 0:
        val = 0
      else:
        val = lerp(s, 0.0, releaseTime)
    if i > 1:
      line(x + i - 1, y + h - (last * h.float).int, x + i, y + h - (val * h.float).int)
    last = val

import util

import common
import filter
import math
import pico

{.this:self.}

type
  EnvState* = enum
    End
    Delay
    Attack
    Decay
    Sustain
    Release
  DecayKind* = enum
    Linear
    Exponential
  Envelope* = object of RootObj
    delay*: float
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

  targetLevel = 0.0
  if state == Delay:
    if delay == 0.0:
      state = Attack
    else:
      targetLevel = 0.0
      time += invSampleRate
      if time > delay:
        state = Attack
        time -= delay
  if state == Attack:
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
  if state == Decay:
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
  if state == Sustain:
    targetLevel = s
    if released:
      state = Release
      time = 0.0
  if state == Release:
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

  return targetLevel

proc init*(self: var Envelope) =
  filter.kind = Lowpass
  filter.init()
  filter.setCutoff(exp(-4.0))
  decayExp = 1.0

proc trigger*(self: var Envelope, vel = 1.0) =
  state = Delay
  time = 0.0
  velocity = vel
  released = false

proc triggerIfReady*(self: var Envelope, vel = 1.0) =
  if state == End or released:
    state = Delay
    time = 0.0
    velocity = vel
    released = false

proc release*(self: var Envelope) =
  released = true

proc drawEnv*(a,d,dexp,s,r, length: float, x,y,w,h: int) =
  ## draws the envelope to the screen

  #let len = a + d + 1.0 + r

  setColor(1)
  line(x, y + h - 1, x + w - 1, y + h - 1)
  line(x, y, x + w - 1, y)

  # grid line each second
  for i in 0..<length.int:
    let x = ((i.float / w.float) * length).int
    line(x,y,x,y+h)

  var last = 0.0

  var state = Attack

  for i in 0..w-1:
    # for each pixel
    let time = (i.float / w.float) * length

    var val = 0.0
    if time <= a:
      if a == 0:
        val = 1.0
      else:
        val = lerp(0.0, 1.0, time / a)
    elif time <= a + d:
      state = Decay
      if d == 0:
        val = s
      else:
        let decayTime = (time - a) / d
        if dexp > 0:
          val = lerp(1.0, s, 1.0 - pow(1.0-decayTime, dexp))
        else:
          val = lerp(1.0, s, decayTime)
    elif time <= a + d + 1.0:
      state = Sustain
      val = s
    elif time <= a + d + 1.0 + r:
      state = Release
      let releaseTime = (time - a - d - 1.0) / r
      if r == 0:
        val = 0
      else:
        val = clamp(lerp(s, 0.0, releaseTime), 0.0, 1.0)
    else:
      state = End
      val = 0

    # draw the line from last to current
    setColor(case state:
      of Delay: 1
      of Attack: 2
      of Decay: 4
      of Sustain: 3
      of Release: 5
      of End: 1
    )
    line(x + i - 1, y + h - (last * h.float).int, x + i, y + h - (val * h.float).int)
    last = val

proc drawEnvs*(envs: openarray[tuple[a,d,decayExp,s,r: float]], x,y,w,h: int) =
  var maxLength = 1.0
  for env in envs:
    var envLength = env.a + env.d + 1.0 + env.r
    if envLength > maxLength:
      maxLength = envLength

  var yv = y
  var eh = h div envs.len
  for env in envs:
    yv += eh
    drawEnv(env.a, env.d, env.decayExp, env.s, env.r, maxLength, x,yv,w,eh)

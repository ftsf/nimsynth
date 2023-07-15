import util

import common
import filter
import math
import nico

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
    delay*: float32
    a*,d*,s*,r*: float32
    decayKind*: DecayKind
    decayExp*: float32
    state*: EnvState
    time: float32
    released: bool
    filter: OnePoleFilter
    targetLevel: float32
    level*: float32
    releaseStartLevel: float32
    velocity*: float32
    speed*: float32
  EnvelopeSettings* = tuple
    a,d,decayExp,s,r: float32

proc value*(self: Envelope): float32 =
  return self.targetLevel

proc updateFromSettings*(self: var Envelope, settings: EnvelopeSettings) =
  self.a = settings.a
  self.d = settings.d
  self.decayExp = settings.decayExp
  self.s = settings.s
  self.r = settings.r

proc process*(self: var Envelope): float32 =
  targetLevel = 0.0
  if state == Delay:
    if delay == 0.0:
      state = Attack
    else:
      targetLevel = 0.0
      time += invSampleRate * speed
      if time > delay:
        state = Attack
        time -= delay
  if state == Attack:
    if released:
      state = Release
      releaseStartLevel = level
      time = 0.0
    elif a == 0.0:
      state = Decay
      targetLevel = velocity
      time = 0.0
    else:
      targetLevel = lerp(0.0, velocity, time / a)
      time += invSampleRate * speed
    if time > a:
      state = Decay
      time -= a
  if state == Decay:
    if released:
      state = Release
      releaseStartLevel = level
      time = 0.0
    elif d == 0.0:
      state = Sustain
      targetLevel = s * velocity
      time = 0.0
    elif time > d:
        state = Sustain
        time -= d
    else:
      case decayKind:
      of Linear:
        targetLevel = lerp(velocity, s * velocity, time / d)
      of Exponential:
        let x = time / d
        targetLevel = lerp(velocity, s * velocity, 1.0 - pow(1.0-x, decayExp))
      time += invSampleRate * speed
  if state == Sustain:
    targetLevel = s * velocity
    if released:
      state = Release
      releaseStartLevel = level
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
        targetLevel = lerp(releaseStartLevel, 0.0, time / r)
      time += invSampleRate * speed

  if abs(level - targetLevel) > 0.01:
    level = lerp(level, targetLevel, 0.05)
  else:
    level = targetLevel
  return level

proc init*(self: var Envelope) =
  filter.kind = Lowpass
  filter.init()
  filter.setCutoff(exp(-4.0))
  decayExp = 1.0
  speed = 1

proc trigger*(self: var Envelope, vel = 1.0'f, speed = 1'f) =
  self.state = Delay
  self.time = 0.0
  self.velocity = vel
  self.released = false
  self.speed = max(speed, 0.0001'f)

proc triggerIfReady*(self: var Envelope, vel = 1.0, speed = 1'f) =
  if self.state == End or self.released:
    self.state = Delay
    self.time = 0.0
    self.speed = max(speed, 0.0001'f)
    self.velocity = vel
    self.released = false

proc release*(self: var Envelope) =
  self.released = true

proc drawEnv*(a,d,dexp,s,r, length: float32, x,y,w,h: int) =
  ## draws the envelope to the screen

  #let len = a + d + 1.0 + r

  setColor(1)
  line(x, y + h - 1, x + w - 1, y + h - 1)
  line(x, y, x + w - 1, y)

  # grid line each second
  for i in 0..<length.int:
    let x = ((i.float32 / w.float32) * length).int
    line(x,y,x,y+h)

  var last = 0.0

  var state = Attack

  for i in 0..w-1:
    # for each pixel
    let time = (i.float32 / w.float32) * length

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
    line(x + i - 1, y + h - (last * h.float32).int, x + i, y + h - (val * h.float32).int)
    last = val

proc drawEnvs*(envs: openarray[EnvelopeSettings], x,y,w,h: int) =
  var maxLength = 1.0'f
  for env in envs:
    var envLength = env.a + env.d + 1.0'f + env.r
    if envLength > maxLength:
      maxLength = envLength
  maxLength += 0.25'f

  var yv = y
  var eh = h div envs.len
  for env in envs:
    yv += eh
    drawEnv(env.a, env.d, env.decayExp, env.s, env.r, maxLength, x,yv,w,eh)
    yv += 4

proc drawEnvs*(envs: openarray[Envelope], x,y,w,h: int) =
  var maxLength = 1.0'f
  for env in envs:
    var envLength = env.a + env.d + 1.0'f + env.r
    if envLength > maxLength:
      maxLength = envLength
  maxLength += 0.25'f

  var yv = y
  var eh = h div envs.len
  for env in envs:
    yv += eh
    drawEnv(env.a, env.d, env.decayExp, env.s, env.r, maxLength, x,yv,w,eh)
    yv += 4

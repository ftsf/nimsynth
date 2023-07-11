import math
import random
import ../core/noise

const sampleRate = 48000.0'f
const invSampleRate = 1.0'f/sampleRate

type
  OscKind* = enum
    Sin
    Tri
    Sqr
    Saw
    Noise
    FatSaw

  Osc* = object of RootObj
    kind*: OscKind
    phase*: float32
    freq: float32
    phaseIncrement*: float32
    pulseWidth*: float32
    cycled*: bool

    s,c: float32

    sinOut*: float32
    sawOut*: float32
    sqrOut*: float32
    triOut*: float32
    noiseOut*: float32
    fatSawOut*: float32

  LFOOsc* = object of RootObj
    kind*: OscKind
    phase*: float32
    freq: float32
    pulseWidth*: float32
    phaseIncrement*: float32

    sinOut*: float32
    sawOut*: float32
    sqrOut*: float32
    triOut*: float32
    noiseOut*: float32
    fatSawOut*: float32

proc init*(self: var Osc) =
  self.c = 1'f
  self.s = 0'f

proc `freq=`*(self: var Osc, freq: float32) =
  self.freq = freq
  self.phaseIncrement = (freq * invSampleRate)

func freq*(self: Osc): float32 =
  return self.freq

proc process*(self: var Osc, offset: float32 = 0'f): float32 {.inline.} =
  self.phase += self.phaseIncrement

  if self.phase > 1'f:
    self.phase -= 1'f
    self.cycled = true
    self.noiseOut = rand(2'f) - 1'f
  else:
    self.cycled = false

  let p = floorMod(self.phase + offset, 1'f)

  self.sawOut = floorMod(p, 1'f) * 2'f - 1'f
  self.sqrOut = if p > self.pulseWidth: -1'f else: 1'f
  self.triOut = abs(self.sawOut) * 2'f - 1'f
  self.sinOut = sin(p * TAU)
  self.fatSawOut = tanh(1'f*self.sawOut) / tanh(1'f)

  case self.kind:
  of Sin:
    return self.sinOut
  of Saw:
    return self.sawOut
  of Sqr:
    return self.sqrOut
  of Tri:
    return self.triOut
  of Noise:
    return self.noiseOut
  of FatSaw:
    return self.fatSawOut

proc `freq=`*(self: var LFOOsc, freq: float32) {.inline.} =
  self.freq = freq
  self.phaseIncrement = (freq * invSampleRate)

func freq*(self: LFOOsc): float32 =
  return self.freq

proc process*(self: var LFOOsc): float32 {.inline.} =
  self.phase += self.phaseIncrement
  if self.phase > 1'f:
    self.phase -= 1'f
  self.sawOut = self.phase * 2'f - 1'f
  self.sqrOut = if self.phase > self.pulseWidth: -1'f else: 1'f
  self.triOut = abs(self.sawOut) * 2'f - 1'f
  self.sinOut = sin(self.phase * TAU)
  self.noiseOut = rand(2'f) - 1'f
  self.fatSawOut = tanh(1'f*self.sawOut) / tanh(1'f)
  case self.kind:
  of Sin:
    return self.sinOut
  of Saw:
    return self.sawOut
  of Sqr:
    return self.sqrOut
  of Tri:
    return self.triOut
  of Noise:
    return self.noiseOut
  of FatSaw:
    return self.fatSawOut

proc peek*(self: LFOOsc, phase: float32): float32 {.inline.} =
  let phase = floorMod(phase, 1'f)
  let sawOut = phase * 2'f - 1'f
  let sqrOut = if phase > self.pulseWidth: -1'f else: 1'f
  let triOut = abs(sawOut) * 2'f - 1'f
  let sinOut = sin(phase * TAU)
  let noiseOut = rand(2'f) - 1'f
  let fatSawOut = tanh(0.5'f*sawOut) / tanh(0.5'f)

  case self.kind:
  of Sin:
    return sinOut
  of Saw:
    return sawOut
  of Sqr:
    return sqrOut
  of Tri:
    return triOut
  of Noise:
    return noiseOut
  of FatSaw:
    return fatSawOut


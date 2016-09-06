import pico
import math
import sdl2
import util
import basic2d
import strutils
import ringbuffer

import osc
import filter
import env

import common

{.this:self.}

type
  Delay = object of RootObj
    buffer: RingBuffer[float32]
    wet,dry: float
    feedback: float

  Distortion = object of RootObj
    threshold: float
    gain: float

proc setLen(self: var Delay, newLength: int) =
  self.buffer = newRingBuffer[float32](newLength)

proc update(self: var Delay, sample: float32): float32 =
  self.buffer.add([(sample + self.buffer[0] * feedback).float32])
  return self.buffer[0] * wet + sample * dry

proc update(self: Distortion, sample: float32): float32 =
  let sample = sample * gain
  if sample > threshold or sample < -threshold:
    #return abs(abs((sample - threshold) mod (threshold * 4.0)) - threshold * 2.0) - threshold
    return tanh(sample)
  return sample

var baseOctave = 6
var lastmv: Point2d

type
  Knob = object of RootObj
    x,y: int
    min,max: float
    value: float
    default: float
    onchange: proc(newValue: float)
    getValueString: proc(value: float): string
    label: string

var currentKnob: ptr Knob

proc draw(self: var Knob) =
  setColor(4)
  circfill(x,y,4)
  setColor(7)
  let range = max - min
  let angle = lerp(-PI, 0.0, ((value - min) / range))
  line(x,y, x + cos(angle) * 4, y + sin(angle) * 4)
  printShadowC(label, x, y + 8)
  if currentKnob == addr(self):
    if self.getValueString != nil:
      printShadowC(self.getValueString(value), x, y + 16)

var knobs = newSeq[Knob]()

proc getAABB(self: Knob): AABB =
  result.min.x = x.float - 4.0
  result.min.y = y.float - 4.0
  result.max.x = x.float + 8.0
  result.max.y = y.float + 8.0

proc addKnob(label: string, x,y: int, min,max,default: float, onchange: proc(newValue: float) = nil, getValueString: proc(value: float): string = nil) =
  var knob: Knob
  knob.label = label
  knob.x = x
  knob.y = y
  knob.min = min
  knob.max = max
  knob.default = default
  knob.value = default
  knob.onchange = onchange
  knob.getValueString = getValueString
  knobs.add(knob)

var osc1: Osc
var osc2: Osc
var filter1: Filter
var delay: Delay
var distortion: Distortion
distortion.threshold = 0.8
distortion.gain = 1.1

var centOffset = 1.0
var semiOffset = 0.0
var cutoffMod: Osc
cutoffMod.kind = Sin
cutoffMod.freq = 0.5
var resonanceMod: Osc
resonanceMod.kind = Sin
resonanceMod.freq = 0.5
var pitchMod: Osc
pitchMod.kind = Sin
pitchMod.freq = 0.5

var osc1Amount = 0.5
var osc2Amount = 0.5
var cutoffModAmount = 0.0
var resonanceModAmount = 0.0
var pitchModAmount = 0.0

var env1: Envelope
env1.a = 0.1
env1.d = 0.5
env1.s = 0.5
env1.r = 0.3

var env2: Envelope
env2.a = 0.1
env2.d = 0.3
env2.s = 0.1
env2.r = 0.3

var envMod = 0.0

#[
#
#  osc1 * osc1Amount +    env2 \
#                    +--> filter1 * env1 --> delay --> distortion --> output
#  osc2 * osc2Amount +    lfo1 /
#
]#

proc noteToHz(key: int): float =
  return pow(2.0,((key - 69).float / 12.0)) * 440.0

proc hzToNote(hz: float): int =
  return (69.0 + 12.0 * log2(hz / 440.0)).int

proc noteToNoteName(note: int): string =
  let oct = note div 12 - 1
  case note mod 12:
  of 0:
    return "C-" & $oct
  of 1:
    return "C#" & $oct
  of 2:
    return "D-" & $oct
  of 3:
    return "D#" & $oct
  of 4:
    return "E-" & $oct
  of 5:
    return "F-" & $oct
  of 6:
    return "F#" & $oct
  of 7:
    return "G-" & $oct
  of 8:
    return "G#" & $oct
  of 9:
    return "A-" & $oct
  of 10:
    return "A#" & $oct
  of 11:
    return "B-" & $oct
  else:
    return "???"

proc hzToNoteName(hz: float): string =
  return noteToNoteName(hzToNote(hz))

var buffer = newSeq[float32](1024)

proc synthAudio(userdata: pointer, stream: ptr uint8, len: cint) {.cdecl.} =
  zeroMem(stream, len)
  var samples = cast[ptr array[int.high,float32]](stream)
  var nSamples = len div sizeof(float32)
  for i in 0..<buffer.len:
    samples[i] = (osc1.update() * osc1Amount + osc2.update() * osc2Amount) * env1.update()
    filter1.cutoffMod = cutoffMod.update() * cutoffModAmount + (env2.update() * envMod)
    filter1.resonanceMod = resonanceMod.update() * resonanceModAmount
    filter1.calc()
    samples[i] = filter1.process(samples[i])
    samples[i] = delay.update(samples[i])
    samples[i] = distortion.update(samples[i])

  for i in 0..<buffer.len:
    if i > nSamples:
      break
    buffer[i] = samples[i]

proc synthKey(key: KeyboardEventPtr, down: bool): bool =
  let scancode = key.keysym.scancode

  if (int16(key.keysym.modstate) and int16(KMOD_CTRL)) != 0:
    return false

  if key.repeat:
    return false

  case scancode:
  of SDL_SCANCODE_Z:
    osc1.freq = noteToHz(baseOctave * 12 + 0)
  of SDL_SCANCODE_S:
    osc1.freq = noteToHz(baseOctave * 12 + 1)
  of SDL_SCANCODE_X:
    osc1.freq = noteToHz(baseOctave * 12 + 2)
  of SDL_SCANCODE_D:
    osc1.freq = noteToHz(baseOctave * 12 + 3)
  of SDL_SCANCODE_C:
    osc1.freq = noteToHz(baseOctave * 12 + 4)
  of SDL_SCANCODE_V:
    osc1.freq = noteToHz(baseOctave * 12 + 5)
  of SDL_SCANCODE_G:
    osc1.freq = noteToHz(baseOctave * 12 + 6)
  of SDL_SCANCODE_B:
    osc1.freq = noteToHz(baseOctave * 12 + 7)
  of SDL_SCANCODE_H:
    osc1.freq = noteToHz(baseOctave * 12 + 8)
  of SDL_SCANCODE_N:
    osc1.freq = noteToHz(baseOctave * 12 + 9)
  of SDL_SCANCODE_J:
    osc1.freq = noteToHz(baseOctave * 12 + 10)
  of SDL_SCANCODE_M:
    osc1.freq = noteToHz(baseOctave * 12 + 11)
  of SDL_SCANCODE_COMMA:
    osc1.freq = noteToHz(baseOctave * 12 + 12)
  of SDL_SCANCODE_Q:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 0)
  of SDL_SCANCODE_2:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 1)
  of SDL_SCANCODE_W:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 2)
  of SDL_SCANCODE_3:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 3)
  of SDL_SCANCODE_E:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 4)
  of SDL_SCANCODE_R:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 5)
  of SDL_SCANCODE_5:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 6)
  of SDL_SCANCODE_T:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 7)
  of SDL_SCANCODE_6:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 8)
  of SDL_SCANCODE_Y:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 9)
  of SDL_SCANCODE_7:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 10)
  of SDL_SCANCODE_U:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 11)
  of SDL_SCANCODE_I:
    osc1.freq = noteToHz(baseOctave * 12 + 12 + 12)
  else:
    return false

  if down:
    env1.trigger()
    env2.trigger()
  else:
    env1.release()
    env2.release()

  return true


proc synthInit() =
  loadSpriteSheet("spritesheet.png")
  osc1.phase = 0.0
  osc1.freq = 440.0
  osc2.phase = 0.0
  osc2.freq = 440.0

  delay.setLen((sampleRate * 0.333).int)
  delay.wet = 0.5
  delay.dry = 0.9
  delay.feedback = 0.5

  filter1.cutoff = 0.01
  filter1.resonance = 1.0
  filter1.peakGain = 1.0
  filter1.calc()
  setAudioCallback(synthAudio)
  setKeyFunc(synthKey)

  addKnob("cut", 32,32, 1.0, 1.499, 0.01) do(newValue: float):
    filter1.cutoff = log2(newValue)
  do(value: float) -> string:
    return $(filter1.cutoff * sampleRate).int
  addKnob("q", 32+16,32, 0.001, 5.0, 1.0) do(newValue: float):
    filter1.resonance = newValue
  do(value: float) -> string:
    return $(filter1.resonance).formatFloat(ffDecimal, 2)
  addKnob("cent", 32+32,32, -100.0, 100.0, 1.0) do(newValue: float):
    centOffset = newValue.int.float
  do(value: float) -> string:
    return $centOffset.int
  addKnob("mod", 32+32,8, -1.0, 1.0, 0.0) do(newValue: float):
    pitchModAmount = newValue
  do(value: float) -> string:
    return pitchModAmount.formatFloat(ffDecimal, 2)
  addKnob("semi", 32+32+16,32, -12.0, 12.0, 1.0) do(newValue: float):
    semiOffset = newValue.int.float
  do(value: float) -> string:
    return $semiOffset.int
  addKnob("osc1", 32+32+32,32, 0.0, 6.0, 0.0) do(newValue: float):
    osc1.kind = cast[OscKind](newValue.int)
  do(value: float) -> string:
    return $osc1.kind
  addKnob("osc2", 32+32+32+16,32, 0.0, 6.0, 0.0) do(newValue: float):
    osc2.kind = cast[OscKind](newValue.int)
  do(value: float) -> string:
    return $osc2.kind
  addKnob("vol", 32+32+32+32,32, 0.0, 1.0, 1.0) do(newValue: float):
    osc2Amount = newValue
  do(value: float) -> string:
    return osc2Amount.formatFloat(ffDecimal, 2)

  addKnob("mod", 32, 64, -1.0, 1.0, 0.0) do(newValue: float):
    cutoffModAmount = newValue
  do(value: float) -> string:
    return cutoffModAmount.formatFloat(ffDecimal, 2)
  addKnob("mod", 32+16, 64, -1.0, 1.0, 0.0) do(newValue: float):
    resonanceModAmount = newValue
  do(value: float) -> string:
    return resonanceModAmount.formatFloat(ffDecimal, 2)


  addKnob("spd", 32, 64+32, 0.001, 30.0, 0.01) do(newValue: float):
    cutoffMod.freq = newValue
  do(value: float) -> string:
    return cutoffMod.freq.formatFloat(ffDecimal, 2)
  addKnob("spd", 32+16,64+32, 0.001, 30.0, 0.01) do(newValue: float):
    resonanceMod.freq = newValue
  do(value: float) -> string:
    return resonanceMod.freq.formatFloat(ffDecimal, 2)

  addKnob("a", 32+32,64, 0.001, 1.0, 0.001) do(newValue: float):
    env1.a = newValue
  addKnob("d", 32+32+16,64, 0.001, 1.0, 0.001) do(newValue: float):
    env1.d = newValue
  addKnob("s", 32+32+32,64, 0.001, 1.0, 0.5) do(newValue: float):
    env1.s = newValue
  addKnob("r", 32+32+32+16,64, 0.001, 1.0, 0.01) do(newValue: float):
    env1.r = newValue

  addKnob("a", 32+32,64+32, 0.001, 1.0, 0.001) do(newValue: float):
    env2.a = newValue
  addKnob("d", 32+32+16,64+32, 0.001, 1.0, 0.001) do(newValue: float):
    env2.d = newValue
  addKnob("s", 32+32+32,64+32, 0.001, 1.0, 0.5) do(newValue: float):
    env2.s = newValue
  addKnob("r", 32+32+32+16,64+32, 0.001, 1.0, 0.01) do(newValue: float):
    env2.r = newValue
  addKnob("mod", 32+32+32+32,64+32, -1.0, 1.0, 0.0) do(newValue: float):
    envMod = newValue

  addKnob("del", 64,64+64, 0.01, 2.0, 0.333) do(newValue: float):
    delay.setLen((sampleRate * newValue).int)
  do(value: float) -> string:
    return value.formatFloat(ffDecimal, 2)
  addKnob("wet", 64+16,64+64, 0.0, 2.0, 0.5) do(newValue: float):
    delay.wet = newValue
  do(value: float) -> string:
    return value.formatFloat(ffDecimal, 2)
  addKnob("dry", 64+32,64+64, 0.0, 2.0, 0.5) do(newValue: float):
    delay.dry = newValue
  do(value: float) -> string:
    return value.formatFloat(ffDecimal, 2)
  addKnob("fb", 64+48,64+64, 0.0, 1.0, 0.1) do(newValue: float):
    delay.feedback = newValue
  do(value: float) -> string:
    return value.formatFloat(ffDecimal, 2)

  addKnob("dist", 64+64,64+64, 0.0, 1.0, 1.0) do(newValue: float):
    distortion.threshold = newValue
  do(value: float) -> string:
    return value.formatFloat(ffDecimal, 2)
  addKnob("gain", 64+64+16,64+64, 0.0, 2.0, 1.0) do(newValue: float):
    distortion.gain = newValue
  do(value: float) -> string:
    return value.formatFloat(ffDecimal, 2)


proc synthUpdate(dt: float) =
  if btnp(0):
    baseOctave -= 1
  if btnp(1):
    baseOctave += 1

  let mv = mouse()
  if mousebtnp(0):
    for knob in mitems(knobs):
      if pointInAABB(mv,knob.getAABB()):
        currentKnob = addr(knob)

  if mousebtn(0) and currentKnob != nil:
    let dy = mv.y - lastmv.y
    let range = currentKnob.max - currentKnob.min
    currentKnob.value -= dy.float * 0.01 * range
    currentKnob.value = clamp(currentKnob.value, currentKnob.min, currentKnob.max)
    currentKnob.onchange(currentKnob.value)
  else:
    currentKnob = nil
  lastmv = mv

  osc2.freq = osc1.freq * pow(2.0, centOffset / 1200.0 + semiOffset / 12.0)

proc synthDraw() =
  cls()
  setColor(7)

  for x in 1..<buffer.len:
    let y0 = clamp(buffer[x-1], -1.0, 1.0)
    let y1 = clamp(buffer[x]  , -1.0, 1.0)
    line(x-1, screenHeight div 2 + (y0 * screenHeight).int, x, screenHeight div 2 + (y1 * screenHeight).int)

  printShadow("synth: " & hzToNoteName(osc1.freq), 0, 0)
  printShadow("cutoff: " & ((filter1.cutoff + filter1.cutoffMod) * sampleRate).formatFloat(ffDecimal, 2), 0, 8)

  for knob in mitems(knobs):
    knob.draw()

  var mv = mouse()
  spr(20, mv.x, mv.y)

pico.init(false)
pico.run(synthInit, synthUpdate, synthDraw)

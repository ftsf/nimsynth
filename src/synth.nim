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
import distortion
import delay
import sequencer

import common

{.this:self.}

type
  SynthVoice = ref object of Voice
    pitch: float
    note: int
    osc1,osc2,osc3,osc4: Osc
    env1,env2,env3,env4: Envelope
    filter: BiquadFilter
    glissando: OnePoleFilter
  Synth = ref object of Machine
    osc1Amount: float
    osc1Kind: OscKind
    osc1Pw: float
    osc2Amount: float
    osc2Kind: OscKind
    osc2Pw: float
    osc2Semi: float
    osc2Cent: float
    osc3Amount: float
    osc4Amount: float
    glissando: float
    cutoff: float
    resonance: float
    env: array[4, tuple[a,d,s,r: float]]
    env2CutoffMod: float
    env3PitchMod: float

method init*(self: SynthVoice, machine: Synth) =
  echo "synth voice init"
  procCall init(Voice(self), machine)
  osc1.kind = Saw
  osc2.kind = Saw
  osc3.kind = Tri
  osc4.kind = Noise
  env1.a = 0.0001
  env1.d = 0.1
  env1.s = 0.75
  env1.r = 0.01
  filter.kind = Lowpass
  filter.cutoff = 0.25
  filter.resonance = 1.0
  filter.init()
  glissando.init()

method addVoice*(self: Synth) =
  var voice = new(SynthVoice)
  voice.init(self)
  voices.add(voice)

method init*(self: Synth) =
  procCall init(Machine(self))
  name = "synth"
  nInputs = 0
  nOutputs = 1

  self.globalParams.add([
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.cutoff = exp(lerp(-8.0, -0.8, newValue)), getValueString: proc(value: float, voice: int): string =
      return $(self.cutoff * sampleRate).int & " hZ"
    ),
    Parameter(name: "resonance", kind: Float, min: 0.0001, max: 5.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.resonance = newValue
    ),
    Parameter(name: "osc1", kind: Int, min: 0.0, max: OscKind.high.int.float, default: Saw.int.float, onchange: proc(newValue: float, voice: int) =
      self.osc1Kind = newValue.OscKind
    ),
    Parameter(name: "pw", kind: Float, min: 0.01, max: 0.99, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.osc1Pw = newValue
    ),
    Parameter(name: "osc1gain", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.osc1Amount = newValue
    ),
    Parameter(name: "osc2", kind: Int, min: 0.0, max: OscKind.high.int.float, default: Saw.int.float, onchange: proc(newValue: float, voice: int) =
      self.osc2Kind = newValue.OscKind
    ),
    Parameter(name: "pw", kind: Float, min: 0.01, max: 0.99, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.osc2Pw = newValue
    ),
    Parameter(name: "osc2gain", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.osc2Amount = newValue
    ),
    Parameter(name: "osc2semi", kind: Int, min: -12.0, max: 12.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.osc2Semi = newValue.int.float
    ),
    Parameter(name: "osc2cent", kind: Int, min: -100.0, max: 100.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.osc2Cent = newValue.int.float
    ),
    Parameter(name: "sub", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.osc3Amount = newValue
    ),
    Parameter(name: "noise", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.osc4Amount = newValue
    ),
    Parameter(name: "env1 a", kind: Float, min: 0.0, max: 1.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      self.env[0].a = newValue
    ),
    Parameter(name: "env1 d", kind: Float, min: 0.0, max: 1.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.env[0].d = newValue
    ),
    Parameter(name: "env1 s", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.env[0].s = newValue
    ),
    Parameter(name: "env1 r", kind: Float, min: 0.0, max: 1.0, default: 0.01, onchange: proc(newValue: float, voice: int) =
      self.env[0].r = newValue
    ),
    Parameter(name: "env2 a", kind: Float, min: 0.0, max: 1.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      self.env[1].a = newValue
    ),
    Parameter(name: "env2 d", kind: Float, min: 0.0, max: 1.0, default: 0.05, onchange: proc(newValue: float, voice: int) =
      self.env[1].d = newValue
    ),
    Parameter(name: "env2 s", kind: Float, min: 0.0, max: 1.0, default: 0.25, onchange: proc(newValue: float, voice: int) =
      self.env[1].s = newValue
    ),
    Parameter(name: "env2 r", kind: Float, min: 0.0, max: 1.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      self.env[1].r = newValue
    ),
    Parameter(name: "env2 cutoff", kind: Float, min: -1.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.env2CutoffMod = newValue
    ),
    Parameter(name: "env3 a", kind: Float, min: 0.0, max: 1.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.env[2].a = newValue
    ),
    Parameter(name: "env3 d", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.env[2].d = newValue
    ),
    Parameter(name: "env3 s", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.env[2].s = newValue
    ),
    Parameter(name: "env3 r", kind: Float, min: 0.0, max: 1.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      self.env[2].r = newValue
    ),
    Parameter(name: "env3 pmod", kind: Float, min: -24.0, max: 24.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.env3PitchMod = newValue
    ),
    Parameter(name: "glissando", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.glissando = exp(lerp(-12.0, 0.0, 1.0-newValue))
    ),
  ])
  self.voiceParams.add(
    Parameter(name: "note", kind: Note, min: 0.0, max: 255.0, onchange: proc(newValue: float, voice: int) =
      var voice: SynthVoice = SynthVoice(self.voices[voice])
      voice.pitch = noteToHz(newValue)
      voice.env1.trigger()
      voice.env2.trigger()
      voice.env3.trigger()
      voice.env4.trigger()
    , getValueString: proc(value: float, voice: int): string =
      var voice: SynthVoice = SynthVoice(self.voices[voice])
      return hzToNoteName(voice.pitch)
    )
  )
  for param in mitems(self.globalParams):
    param.value = param.default
    param.onchange(param.value, -1)
  self.addVoice()

method trigger(self: Synth, note: int) =
  for voice in mitems(voices):
    var v2 = SynthVoice(voice)
    if v2.env1.state == End:
      v2.note = note
      v2.pitch = noteToHz(note.float)
      v2.env1.trigger()
      v2.env2.trigger()
      v2.env3.trigger()
      v2.env4.trigger()
      return
  # no free note, play it anyway on voice 0 (if it exists)
  if voices.len > 0:
    var v2 = SynthVoice(voices[0])
    v2.note = note
    v2.pitch = noteToHz(note.float)
    v2.env1.trigger()
    v2.env2.trigger()
    v2.env3.trigger()
    v2.env4.trigger()


method release(self: Synth, note: int) =
  # find the voice playing that note, this is very ugly
  for voice in mitems(voices):
    var v2 = SynthVoice(voice)
    if v2.note == note:
      v2.env1.release()
      v2.env2.release()
      v2.env3.release()
      v2.env4.release()

proc newSynth*(): Machine =
  result = new(Synth)
  result.init()

registerMachine("synth", newSynth)

method process*(self: Synth): float32 {.inline.} =
  for voice in mitems(self.voices):
    var v = SynthVoice(voice)
    v.env1.a = env[0].a
    v.env1.d = env[0].d
    v.env1.s = env[0].s
    v.env1.r = env[0].r

    v.env2.a = env[1].a
    v.env2.d = env[1].d
    v.env2.s = env[1].s
    v.env2.r = env[1].r

    v.env3.a = env[2].a
    v.env3.d = env[2].d
    v.env3.s = env[2].s
    v.env3.r = env[2].r

    v.osc1.kind = osc1Kind
    v.glissando.setCutoff(glissando)
    v.glissando.calc()
    v.osc1.freq = v.glissando.process(v.pitch)
    v.osc1.freq *= pow(2.0, (v.env3.process() * env3PitchMod) / 12.0)
    v.osc1.pulseWidth = osc1Pw
    v.osc2.kind = osc2Kind
    v.osc2.freq = v.osc1.freq * pow(2.0, osc2Cent / 1200.0 + osc2Semi / 12.0)
    v.osc2.pulseWidth = osc2Pw
    v.osc3.kind = osc1Kind
    v.osc3.pulseWidth = osc1Pw
    v.osc3.freq = v.osc1.freq * 0.5
    var vs = (v.osc1.process() * osc1Amount + v.osc2.process() * osc2Amount + v.osc3.process() * osc3Amount + v.osc4.process() * osc4Amount) * v.env1.process()
    v.filter.cutoff = clamp(cutoff + v.env2.process() * env2CutoffMod, 0.001, 0.499)
    v.filter.resonance = resonance
    v.filter.calc()
    vs = v.filter.process(vs)
    result += vs

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
  setColor(1)
  circ(x,y,5)
  setColor(1)
  let range = max - min

  setColor(7)
  let angle = lerp(degToRad(-180 - 45), degToRad(45), ((value - min) / range))
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
  knob.value = clamp(default, min, max)
  knob.onchange = onchange
  knob.getValueString = getValueString
  knobs.add(knob)

  if knob.onchange != nil:
    knob.onchange(knob.value)

var osc1: Osc
var osc2: Osc
var subOsc: Osc
subOsc.kind = Tri
var noiseOsc: Osc
noiseOsc.kind = Noise

var filter1: BiquadFilter
filter1.init()
var hpf: BiquadFilter
hpf.init()
hpf.kind = Highpass
hpf.setCutoff(10.0 * invSampleRate)
hpf.setResonance(1.0)
hpf.calc()

var delay1: Delay
var dist: Distortion

dist.threshold = 0.8
dist.preGain = 1.1
dist.postGain = 1.0

var centOffset = 0.0
var semiOffset = 0.0
var cutoffMod: Osc
cutoffMod.kind = Tri
cutoffMod.freq = 0.5
var resonanceMod: Osc
resonanceMod.kind = Tri
resonanceMod.freq = 0.5
var pitchMod: Osc
pitchMod.kind = Tri
pitchMod.freq = 0.1
var pwMod: Osc
pwMod.kind = Tri
pwMod.freq = 1.0

var osc1Amount = 1.0
var osc2Amount = 0.5
var subOscAmount = 0.0
var noiseOscAmount = 0.0

var cutoffModAmount = 0.0
var resonanceModAmount = 0.0
var pitchModAmount = 0.0
var pwMod1Amount = 0.0
var pwMod2Amount = 0.0
var keytrackAmount = 0.0

var targetFreq = 0.0
var glissando: OnePoleFilter
glissando.init()
glissando.setCutoff(1.0)

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
#                    +--> filter1 * env1 --> dist --> delay --> output
#  osc2 * osc2Amount +    lfo1 /
#
]#

when false:
  var buffer = newSeq[float32](1024)

  proc synthAudio(userdata: pointer, stream: ptr uint8, len: cint) {.cdecl.} =
    zeroMem(stream, len)
    var samples = cast[ptr array[int.high,float32]](stream)
    var nSamples = len div sizeof(float32)
    for i in 0..<buffer.len:
      osc1.freq = glissando.process(targetFreq)
      let oldFreq2 = osc2.freq
      subOsc.freq = osc1.freq * 0.5
      subOsc.kind = osc1.kind
      subOsc.pulseWidth = osc1.pulseWidth
      osc2.freq = osc1.freq * pow(2.0, (centOffset + pitchMod.update() * pitchModAmount) / 1200.0 + semiOffset / 12.0)
      let oldPw1 = osc1.pulseWidth
      let oldPw2 = osc2.pulseWidth
      osc1.pulseWidth += pwMod.update() * pwMod1Amount
      osc2.pulseWidth += pwMod.update() * pwMod2Amount
      samples[i] = (osc1.update() * osc1Amount + osc2.update() * osc2Amount + subOsc.update() * subOscAmount + noiseOsc.update() * noiseOscAmount) * env1.update()
      osc1.pulseWidth = oldPw1
      osc2.pulseWidth = oldPw2
      osc2.freq = oldFreq2

      let filter1Cutoff = filter1.cutoff
      let filter1Resonance = filter1.resonance
      filter1.setCutoff(filter1.cutoff + cutoffMod.update() * cutoffModAmount + (env2.update() * envMod) + (osc1.freq * invSampleRate) * keytrackAmount)
      filter1.setResonance(filter1.resonance + resonanceMod.update() * resonanceModAmount)
      filter1.calc()
      filter1.cutoff = filter1Cutoff
      filter1.resonance = filter1Resonance
      samples[i] = filter1.process(samples[i])
      samples[i] = hpf.process(samples[i])
      samples[i] = dist.update(samples[i])
      samples[i] = delay1.update(samples[i])

    for i in 0..<buffer.len:
      if i > nSamples:
        break
      buffer[i] = samples[i]

  proc unused() =
    osc1.phase = 0.0
    osc1.freq = 440.0
    osc2.phase = 0.0
    osc2.freq = 440.0

    delay1.setLen((sampleRate * 0.333).int)

    addKnob("flt", 16,32, 0.0, FilterKind.high.float, 0.0) do(newValue: float):
      filter1.kind = newValue.FilterKind
    do(value: float) -> string:
      return $filter1.kind
    addKnob("cut", 32,32, 0.0, 1.0, 0.5) do(newValue: float):
      filter1.setCutoff(exp(lerp(-8.0, -0.8, newValue)))
    do(value: float) -> string:
      return $(filter1.cutoff * sampleRate).int
    addKnob("q", 32+16,32, 0.0001, 5.0, 1.0) do(newValue: float):
      filter1.setResonance(newValue)
    do(value: float) -> string:
      return $(filter1.resonance).formatFloat(ffDecimal, 2)
    addKnob("cent", 32+32,32, -100.0, 100.0, 10.0) do(newValue: float):
      centOffset = newValue.int.float
    do(value: float) -> string:
      return $centOffset.int

    addKnob("viba", 32+32,8, -100.0, 100.0, 0.0) do(newValue: float):
      pitchModAmount = newValue
    do(value: float) -> string:
      return pitchModAmount.formatFloat(ffDecimal, 2)
    addKnob("vibs", 32+32+16,8, 0.001, 60.0, 0.001) do(newValue: float):
      pitchMod.freq = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)

    addKnob("semi", 32+32+16,32, -12.0, 12.0, 0.0) do(newValue: float):
      semiOffset = newValue.int.float
    do(value: float) -> string:
      return $semiOffset.int
    addKnob("osc1", 32+32+32,32, 0.0, 3.0, 3.0) do(newValue: float):
      osc1.kind = cast[OscKind](newValue.int)

    do(value: float) -> string:
      return $osc1.kind
    addKnob("osc2", 32+32+32+16,32, 0.0, 3.0, 3.0) do(newValue: float):
      osc2.kind = cast[OscKind](newValue.int)
    do(value: float) -> string:
      return $osc2.kind
    addKnob("vol", 32+32+32+32,32, 0.0, 1.0, 0.5) do(newValue: float):
      osc2Amount = newValue
    do(value: float) -> string:
      return osc2Amount.formatFloat(ffDecimal, 2)
    addKnob("gls", 32+32+32+32+32+16,32, 0.0, 1.0, 0.0) do(newValue: float):
      glissando.cutoff = exp(lerp(-12.0, 0.0, 1.0-newValue))
      glissando.calc()
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)
    addKnob("sub", 32+32+32+32+32+32,32, 0.0, 1.0, 0.25) do(newValue: float):
      subOscAmount = newValue
    do(value: float) -> string:
      return subOscAmount.formatFloat(ffDecimal, 2)
    addKnob("noiz", 32+32+32+32+32+32+16,32, 0.0, 1.0, 0.0) do(newValue: float):
      noiseOscAmount = newValue
    do(value: float) -> string:
      return noiseOscAmount.formatFloat(ffDecimal, 2)

    addKnob("pw1", 32+32+32+32+16,32, 0.0, 1.0, 0.5) do(newValue: float):
      osc1.pulseWidth = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)
    addKnob("pw2", 32+32+32+32+32,32, 0.0, 1.0, 0.5) do(newValue: float):
      osc2.pulseWidth = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)
    addKnob("pwm", 32+32+32+32+16, 8, 0.0, 1.0, 0.0) do(newValue: float):
      pwMod1Amount = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)
    addKnob("pwm", 32+32+32+32+32, 8, 0.0, 1.0, 0.0) do(newValue: float):
      pwMod2Amount = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)
    addKnob("spd", 32+32+32+32+32+16, 8, 0.001, 60.0, 0.001) do(newValue: float):
      pwMod.freq = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)


    addKnob("mod", 32, 64, -0.1, 0.1, 0.0) do(newValue: float):
      cutoffModAmount = newValue
    do(value: float) -> string:
      return cutoffModAmount.formatFloat(ffDecimal, 2)
    addKnob("mod", 32+16, 64, -0.1, 0.1, 0.0) do(newValue: float):
      resonanceModAmount = newValue
    do(value: float) -> string:
      return resonanceModAmount.formatFloat(ffDecimal, 2)
    addKnob("ktrk", 16, 64, -1.0, 1.0, 0.1) do(newValue: float):
      keytrackAmount = newValue
    do(value: float) -> string:
      return keytrackAmount.formatFloat(ffDecimal, 2)

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
    addKnob("d", 32+32+16,64, 0.001, 1.0, 0.1) do(newValue: float):
      env1.d = newValue
    addKnob("s", 32+32+32,64, 0.001, 1.0, 0.5) do(newValue: float):
      env1.s = newValue
    addKnob("r", 32+32+32+16,64, 0.001, 1.0, 0.01) do(newValue: float):
      env1.r = newValue

    addKnob("a", 32+32,64+32, 0.001, 1.0, 0.001) do(newValue: float):
      env2.a = newValue
    addKnob("d", 32+32+16,64+32, 0.001, 1.0, 0.05) do(newValue: float):
      env2.d = newValue
    addKnob("s", 32+32+32,64+32, 0.001, 1.0, 0.25) do(newValue: float):
      env2.s = newValue
    addKnob("r", 32+32+32+16,64+32, 0.001, 1.0, 0.01) do(newValue: float):
      env2.r = newValue
    addKnob("mod", 32+32+32+32,64+32, -0.1, 0.1, 0.025) do(newValue: float):
      envMod = newValue

    addKnob("cut", 64-16, 64+48, 0.0, 1.0, 0.75) do(newValue: float):
      delay1.cutoff = exp(lerp(-8.0, 0.0, newValue))
    do(value: float) -> string:
      return (delay1.cutoff * sampleRate).formatFloat(ffDecimal, 2)
    addKnob("del", 64, 64+48, 0.01, 2.0, 0.333) do(newValue: float):
      delay1.setLen((sampleRate * newValue).int)
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)
    addKnob("wet", 64+16,64+48, -2.0, 2.0, 0.5) do(newValue: float):
      delay1.wet = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)
    addKnob("dry", 64+32,64+48, -2.0, 2.0, 0.5) do(newValue: float):
      delay1.dry = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)
    addKnob("fb", 64+48,64+48, -1.0, 1.0, 0.1) do(newValue: float):
      delay1.feedback = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)

    addKnob("dist", 64+64, 64+48, 0.0, 3.0, 1.0) do(newValue: float):
      dist.kind = newValue.DistortionKind
    do(value: float) -> string:
      return $value.DistortionKind
    addKnob("thrs", 64+64+16, 64+48, 0.0, 1.0, 1.0) do(newValue: float):
      dist.threshold = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)
    addKnob("pre", 64+64+32, 64+48, 0.0, 2.0, 0.5) do(newValue: float):
      dist.preGain = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)
    addKnob("post", 64+64+48, 64+48, 0.0, 2.0, 1.0) do(newValue: float):
      dist.postGain = newValue
    do(value: float) -> string:
      return value.formatFloat(ffDecimal, 2)

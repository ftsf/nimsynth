import basic2d
import math
import strutils

import sdl2
import sdl2.audio

import pico

import common
import util

import core.oscillator
import core.filter
import core.envelope


{.this:self.}

type
  SynthVoice = ref object of Voice
    pitch: float
    note: int
    velocity: float
    osc1,osc2,osc3,osc4: Osc
    env1,env2,env3: Envelope
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
    filterKind: FilterKind
    cutoff: float
    resonance: float
    env: array[3, tuple[a,d,decayExp,s,r: float]]
    env2CutoffMod: float
    env3PitchMod: float
    env3QMod: float
    env3O2GainMod: float
    keytracking: float
    keytrkReference: int
    retrigger: bool

method init*(self: SynthVoice, machine: Synth) =
  procCall init(Voice(self), machine)
  osc1.kind = Saw
  osc2.kind = Saw
  osc3.kind = Sin
  osc4.kind = Noise
  env1.init()
  env1.a = 0.0001
  env1.d = 0.1
  env1.decayKind = Exponential
  env1.s = 0.75
  env1.r = 0.01
  env2.init()
  env2.decayKind = Exponential
  env3.init()
  env3.decayKind = Exponential
  filter.kind = Lowpass
  filter.setCutoff(440.0)
  filter.resonance = 1.0
  filter.init()
  glissando.kind = Lowpass
  glissando.init()
  pitch = 0.0


method addVoice*(self: Synth) =
  pauseAudio(1)
  var voice = new(SynthVoice)
  voices.add(voice)
  voice.init(self)
  pauseAudio(0)

method init*(self: Synth) =
  procCall init(Machine(self))
  name = "synth"
  nInputs = 0
  nOutputs = 1

  self.globalParams.add([
    Parameter(name: "osc1", kind: Int, min: 0.0, max: OscKind.high.int.float, default: Saw.int.float, onchange: proc(newValue: float, voice: int) =
      self.osc1Kind = newValue.OscKind
    , getValueString: proc(value: float, voice: int): string =
        return $(value.OscKind)
    ),
    Parameter(name: "pw", kind: Float, min: 0.01, max: 0.99, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.osc1Pw = newValue
    ),
    Parameter(name: "osc1gain", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.osc1Amount = newValue
    ),
    Parameter(name: "osc2", kind: Int, separator: true, min: 0.0, max: OscKind.high.int.float, default: Saw.int.float, onchange: proc(newValue: float, voice: int) =
      self.osc2Kind = newValue.OscKind
    , getValueString: proc(value: float, voice: int): string =
        return $(value.OscKind)
    ),
    Parameter(name: "pw", kind: Float, min: 0.01, max: 0.99, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.osc2Pw = newValue
    ),
    Parameter(name: "osc2gain", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.osc2Amount = newValue
    ),
    Parameter(name: "osc2semi", kind: Int, min: -24.0, max: 24.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.osc2Semi = newValue.int.float
    ),
    Parameter(name: "osc2cent", kind: Int, min: -100.0, max: 100.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.osc2Cent = newValue.int.float
    ),
    Parameter(name: "sub", kind: Float, separator: true, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.osc3Amount = newValue
    ),
    Parameter(name: "noise", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.osc4Amount = newValue
    ),
    Parameter(name: "filt", kind: Int, separator: true, min: FilterKind.low.float, max: FilterKind.high.float, default: Lowpass.float, onchange: proc(newValue: float, voice: int) =
      self.filterKind = newValue.FilterKind
    , getValueString: proc(value: float, voice: int): string =
        return $(value.FilterKind)
    ),
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.cutoff = exp(lerp(-8.0, -0.8, newValue)), getValueString: proc(value: float, voice: int): string =
      return $(exp(lerp(-8.0, -0.8, value)) * sampleRate).int & " hZ"
    ),
    Parameter(name: "q", kind: Float, min: 0.0001, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.resonance = newValue
    ),
    Parameter(name: "env1 a", kind: Float, separator: true, min: 0.0, max: 5.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      self.env[0].a = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env1 d", kind: Float, min: 0.0, max: 5.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.env[0].d = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env1 ds", kind: Float, min: 0.1, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.env[0].decayExp = newValue
    ),
    Parameter(name: "env1 s", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.env[0].s = newValue
    ),
    Parameter(name: "env1 r", kind: Float, min: 0.0, max: 5.0, default: 0.01, onchange: proc(newValue: float, voice: int) =
      self.env[0].r = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env2 a", kind: Float, separator: true, min: 0.0, max: 5.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      self.env[1].a = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env2 d", kind: Float, min: 0.0, max: 5.0, default: 0.05, onchange: proc(newValue: float, voice: int) =
      self.env[1].d = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env2 ds", kind: Float, min: 0.1, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.env[1].decayExp = newValue
    ),
    Parameter(name: "env2 s", kind: Float, min: 0.0, max: 1.0, default: 0.25, onchange: proc(newValue: float, voice: int) =
      self.env[1].s = newValue
    ),
    Parameter(name: "env2 r", kind: Float, min: 0.0, max: 5.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      self.env[1].r = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env2 cut", kind: Float, min: -10.0, max: 10.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.env2CutoffMod = newValue
    ),
    Parameter(name: "env3 a", kind: Float, separator: true, min: 0.0, max: 5.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.env[2].a = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env3 d", kind: Float, min: 0.0, max: 5.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.env[2].d = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env3 ds", kind: Float, min: 0.1, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.env[2].decayExp = newValue
    ),
    Parameter(name: "env3 s", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.env[2].s = newValue
    ),
    Parameter(name: "env3 r", kind: Float, min: 0.0, max: 5.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      self.env[2].r = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env3 pmod", kind: Float, min: -24.0, max: 24.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.env3PitchMod = newValue
    ),
    Parameter(name: "env3 qmod", kind: Float, min: -10.0, max: 10.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.env3QMod = newValue
    ),
    Parameter(name: "env3 o2gain", kind: Float, min: -1.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.env3O2GainMod = newValue
    ),
    Parameter(name: "glissando", kind: Float, separator: true, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.glissando = exp(lerp(-12.0, 0.0, 1.0-newValue))
    ),
    Parameter(name: "ktrk", kind: Float, min: -2.0, max: 2.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.keytracking = newValue
    ),
    Parameter(name: "ref", kind: Note, min: 0, max: 256.0, default: 60.0, onchange: proc(newValue: float, voice: int) =
      self.keytrkReference = newValue.int
    ),
    Parameter(name: "retrig", kind: Bool, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.retrigger = newValue.bool
    ),
  ])
  self.voiceParams.add([
    Parameter(name: "note", kind: Note, deferred: true, separator: true, min: OffNote, max: 255.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      var voice: SynthVoice = SynthVoice(self.voices[voice])
      voice.note = newValue.int
      if newValue == OffNote:
        voice.env1.release()
        voice.env2.release()
        voice.env3.release()
      else:
        voice.pitch = noteToHz(newValue)
        if not self.retrigger:
          voice.env1.triggerIfReady(voice.velocity)
          voice.env2.triggerIfReady(voice.velocity)
          voice.env3.triggerIfReady(voice.velocity)
        else:
          voice.env1.trigger(voice.velocity)
          voice.env2.trigger(voice.velocity)
          voice.env3.trigger(voice.velocity)

    , getValueString: proc(value: float, voice: int): string =
      if value == OffNote:
        return "Off"
      else:
        return noteToNoteName(value.int)

    ),
    Parameter(name: "vel", kind: Float, min: 0.0, max: 1.0, seqkind: skInt8, default: 1.0, onchange: proc(newValue: float, voice: int) =
      var voice: SynthVoice = SynthVoice(self.voices[voice])
      voice.velocity = newValue
    ),
  ])

  setDefaults()

  self.addVoice()

proc newSynth*(): Machine =
  result = new(Synth)
  result.init()

registerMachine("synth", newSynth, "generator")

method process*(self: Synth) {.inline.} =
  outputSamples[0] = 0
  for voice in mitems(self.voices):
    var v = SynthVoice(voice)
    v.env1.a = env[0].a
    v.env1.d = env[0].d
    v.env1.decayExp = env[0].decayExp
    v.env1.s = env[0].s
    v.env1.r = env[0].r

    v.env2.a = env[1].a
    v.env2.d = env[1].d
    v.env2.decayExp = env[1].decayExp
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
    v.osc3.kind = Sin
    #v.osc3.pulseWidth = osc1Pw
    v.osc3.freq = v.osc1.freq * 0.5

    let env1v = v.env1.process()
    let env2v = v.env2.process()
    let env3v = v.env3.process()

    var vs = (v.osc1.process() * osc1Amount + v.osc2.process() * (osc2Amount + env3v * env3O2GainMod) + v.osc3.process() * osc3Amount + v.osc4.process() * osc4Amount) * env1v
    v.filter.kind = filterKind
    v.filter.cutoff = cutoff * (1.0 + (env2v * env2CutoffMod)) * (1.0 + pow(2.0, (((hzToNote(v.pitch) - keytrkReference.float) / 12.0) * keytracking)))
    v.filter.resonance = max(0.0001, resonance + env3v * env3QMod)
    v.filter.calc()
    vs = v.filter.process(vs)
    outputSamples[0] += vs

method drawExtraData(self: Synth, x,y,w,h: int) =
  var y = y
  setColor(1)
  line(x, y + 48, x + w, y + 48)
  setColor(5)
  drawEnvs(env, x,y,w,48)
  y += 64

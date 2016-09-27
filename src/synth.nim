import pico
import math
import sdl2
import util
import basic2d
import strutils
import ringbuffer
import sdl2.audio

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
    filterKind: FilterKind
    cutoff: float
    resonance: float
    env: array[4, tuple[a,d,s,r: float]]
    env2CutoffMod: float
    env3PitchMod: float
    keytracking: float

method init*(self: SynthVoice, machine: Synth) =
  procCall init(Voice(self), machine)
  osc1.kind = Saw
  osc2.kind = Saw
  osc3.kind = Sin
  osc4.kind = Noise
  env1.a = 0.0001
  env1.d = 0.1
  env1.s = 0.75
  env1.r = 0.01
  filter.kind = Lowpass
  filter.setCutoff(440.0)
  filter.resonance = 1.0
  filter.init()
  glissando.init()
  pitch = 0.0

method addVoice*(self: Synth) =
  pauseAudio(1)
  var voice = new(SynthVoice)
  voice.init(self)
  voices.add(voice)
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
    Parameter(name: "osc2", kind: Int, min: 0.0, max: OscKind.high.int.float, default: Saw.int.float, onchange: proc(newValue: float, voice: int) =
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
    Parameter(name: "filt", kind: Int, min: FilterKind.low.float, max: FilterKind.high.float, default: Lowpass.float, onchange: proc(newValue: float, voice: int) =
      self.filterKind = newValue.FilterKind
    , getValueString: proc(value: float, voice: int): string =
        return $(value.FilterKind)
    ),
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.cutoff = exp(lerp(-8.0, -0.8, newValue)), getValueString: proc(value: float, voice: int): string =
      return $(exp(lerp(-8.0, -0.8, value)) * sampleRate).int & " hZ"
    ),
    Parameter(name: "res", kind: Float, min: 0.0001, max: 5.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.resonance = newValue
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
    Parameter(name: "env2 cutoff", kind: Float, min: -0.1, max: 0.1, default: 0.01, onchange: proc(newValue: float, voice: int) =
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
    Parameter(name: "ktrk", kind: Float, min: -0.1, max: 0.1, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.keytracking = newValue
    ),
  ])
  self.voiceParams.add(
    Parameter(name: "note", kind: Note, min: 0.0, max: 255.0, onchange: proc(newValue: float, voice: int) =
      var voice: SynthVoice = SynthVoice(self.voices[voice])
      if newValue == OffNote:
        voice.env1.release()
        voice.env2.release()
        voice.env3.release()
        voice.env4.release()
      else:
        voice.pitch = noteToHz(newValue)
        voice.env1.trigger()
        voice.env2.trigger()
        voice.env3.trigger()
        voice.env4.trigger()
    , getValueString: proc(value: float, voice: int): string =
      if value == OffNote:
        return "Off"
      else:
        return noteToNoteName(value.int)
    )
  )

  setDefaults()

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

method process*(self: Synth) {.inline.} =
  outputSamples[0] = 0
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
    v.osc3.kind = Sin
    #v.osc3.pulseWidth = osc1Pw
    v.osc3.freq = v.osc1.freq * 0.5
    var vs = (v.osc1.process() * osc1Amount + v.osc2.process() * osc2Amount + v.osc3.process() * osc3Amount + v.osc4.process() * osc4Amount) * v.env1.process()
    v.filter.kind = filterKind
    v.filter.cutoff = clamp(cutoff + v.env2.process() * env2CutoffMod + (hzToNote(v.pitch) - 69.0) * keytracking, 0.001, 0.499)
    v.filter.resonance = resonance
    v.filter.calc()
    vs = v.filter.process(vs)
    outputSamples[0] += vs

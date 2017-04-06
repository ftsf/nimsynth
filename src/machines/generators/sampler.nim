import math
import strutils

import sdl2
import sdl2.audio

import pico

import common

import core.envelope
import core.sample
import ui.menu


type
  Sampler = ref object of Machine
  SamplerVoice = ref object of Voice
    playing: bool
    osc: SampleOsc
    env: Envelope

{.this:self.}

method addVoice*(self: Sampler) =
  var voice = new(SamplerVoice)
  voices.add(voice)
  voice.init(self)
  voice.env.init()
  voice.osc.stereo = true

  for param in mitems(voice.parameters):
    param.value = param.default
    param.onchange(param.value, voices.high)

method init(self: Sampler) =
  procCall init(Machine(self))
  name = "sampler"
  nOutputs = 1
  nInputs = 0
  stereo = true

  voiceParams.add([
    Parameter(name: "note", separator: true, deferred: true, kind: Note, min: OffNote, max: 127.0, onchange: proc(newValue: float, voice: int) =
      if newValue == OffNote:
        var v = SamplerVoice(self.voices[voice])
        v.env.release()
      else:
        var v = SamplerVoice(self.voices[voice])
        if v.osc.sample != nil:
          v.playing = true
          v.osc.reset()
          v.osc.speed = noteToHz(newValue) / v.osc.sample.rootPitch
          v.env.trigger()
    ),
    Parameter(name: "a", kind: Float, min: 0.0, max: 5.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      var v = SamplerVoice(self.voices[voice])
      v.env.a = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "d", kind: Float, min: 0.0, max: 5.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      var v = SamplerVoice(self.voices[voice])
      v.env.d = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "dexp", kind: Float, min: 0.1, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      var v = SamplerVoice(self.voices[voice])
      v.env.decayExp = newValue
    ),
    Parameter(name: "s", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      var v = SamplerVoice(self.voices[voice])
      v.env.s = newValue
    ),
    Parameter(name: "r", kind: Float, min: 0.0, max: 5.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      var v = SamplerVoice(self.voices[voice])
      v.env.r = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
  ])

  setDefaults()

method process*(self: Sampler) {.inline.} =
  outputSamples[0] = 0.0
  for i in 0..<voices.len:
    var v = SamplerVoice(voices[i])
    if v.osc.sample != nil:
      if v.playing:
        outputSamples[0] += v.osc.process() * v.env.process()
        if v.osc.finished:
          v.playing = false

method drawExtraData(self: Sampler, x,y,w,h: int) =
  var yv = y
  setColor(6)
  print("samples", x, yv)
  yv += 9
  for i in 0..<voices.len:
    var v = SamplerVoice(voices[i])
    print($i & ": " & (if v.osc.sample != nil: v.osc.sample.name else: " - "), x, yv)
    yv += 9

method updateExtraData(self: Sampler, x,y,w,h: int) =
  if mousebtnp(1):
    let mv = mouse()
    let voice = (mv.y - y - 9) div 9
    if voice >= 0 and voice < voices.len:
      # open sample selection menu
      pushMenu(newSampleMenu(mv, basePath & "samples/") do(sample: Sample):
        var v = SamplerVoice(self.voices[voice])
        v.osc.sample = sample
      )

method saveExtraData(self: Sampler): string =
  result = ""
  for voice in mitems(voices):
    var v = SamplerVoice(voice)
    if v.osc.sample != nil:
      result &= v.osc.sample.filename & "|" & v.osc.sample.name & "\n"
    else:
      result &= "\n"

method loadExtraData(self: Sampler, data: string) =
  var voice = 0
  for line in data.splitLines:
    if voice > voices.high:
      break
    let sline = line.strip()
    if sline == "":
      voice += 1
      continue
    var v = SamplerVoice(voices[voice])
    v.osc.sample = loadSample(sline.split("|")[0], sline.split("|")[1])
    voice += 1

proc newMachine(): Machine =
  var m = new(Sampler)
  m.init()
  return m

registerMachine("sampler", newMachine, "generator")

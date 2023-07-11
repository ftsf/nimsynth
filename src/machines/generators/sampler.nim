import math
import strutils

import nico

import ../../common

import ../../core/envelope
import ../../core/sample
import ../../ui/menu

type
  Sampler = ref object of Machine

type
  SamplerVoice = ref object of Voice
    note: int
    playing: bool
    osc: SampleOsc
    env: Envelope

method addVoice*(self: Sampler) =
  var voice = new(SamplerVoice)
  self.voices.add(voice)
  voice.init(self)
  voice.env.init()
  voice.osc.stereo = true

  for param in mitems(voice.parameters):
    param.value = param.default
    param.onchange(param.value, self.voices.high)

proc initNote*(self: Sampler, voiceId: int, note: int) =
  var voice = SamplerVoice(self.voices[voiceId])
  voice.note = note
  if voice.note == OffNote:
    voice.env.release()
    voice.playing = false
  else:
    if voice.osc.sample != nil:
      voice.playing = true
      voice.osc.reset()
      voice.osc.speed = noteToHz(note.float32) / voice.osc.sample.rootPitch
      voice.env.trigger()

method init(self: Sampler) =
  procCall init(Machine(self))
  self.name = "sampler"
  self.nOutputs = 1
  self.nInputs = 0
  self.stereo = true

  self.voiceParams.add([
    Parameter(name: "note", separator: true, deferred: true, kind: Note, min: OffNote, max: 127.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      self.initNote(voice, newValue.int)
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

  self.setDefaults()

method process*(self: Sampler) =
  self.outputSamples[0] = 0'f
  for i in 0..<self.voices.len:
    var v = SamplerVoice(self.voices[i])
    if v.osc.sample != nil:
      if v.playing:
        self.outputSamples[0] += v.osc.process() * v.env.process()
        if v.osc.finished:
          v.playing = false

method drawExtraData(self: Sampler, x,y,w,h: int) =
  var yv = y
  setColor(6)
  print("samples", x, yv)
  yv += 9
  for i in 0..<self.voices.len:
    var v = SamplerVoice(self.voices[i])
    print($i & ": " & (if v.osc.sample != nil: v.osc.sample.name else: " - "), x, yv)
    yv += 9

method updateExtraData(self: Sampler, x,y,w,h: int) =
  if mousebtnp(0):
    let (mx,my) = mouse()
    let voice = (my - y - 9) div 9
    if voice >= 0 and voice < self.voices.len:
      # open sample selection menu
      pushMenu(newSampleMenu(vec2f(mx,my), "samples/") do(sample: Sample):
        var v = SamplerVoice(self.voices[voice])
        v.osc.sample = sample
      )

method saveExtraData(self: Sampler): string =
  result = ""
  for voice in mitems(self.voices):
    var v = SamplerVoice(voice)
    if v.osc.sample != nil:
      result &= v.osc.sample.filename & "|" & v.osc.sample.name & "\n"
    else:
      result &= "\n"

method loadExtraData(self: Sampler, data: string) =
  var voice = 0
  for line in data.splitLines:
    if voice > self.voices.high:
      break
    let sline = line.strip()
    if sline == "":
      voice += 1
      continue
    var v = SamplerVoice(self.voices[voice])
    v.osc.sample = loadSample(sline.split("|")[0], sline.split("|")[1])
    voice += 1

method trigger*(self: Sampler, note: int) =
  for i,voice in mpairs(self.voices):
    var v = SamplerVoice(voice)
    if v.note == OffNote:
      self.initNote(i, note)
      let param = v.getParameter(0)
      param.value = note.float
      return

method release*(self: Sampler, note: int) =
  for i,voice in mpairs(self.voices):
    var v = SamplerVoice(voice)
    if v.note == note:
      self.initNote(i, OffNote)
      let param = v.getParameter(0)
      param.value = OffNote.float

proc newMachine(): Machine =
  var m = new(Sampler)
  m.init()
  return m

registerMachine("sampler", newMachine, "generator")

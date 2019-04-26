import math
import strutils

import nico
import nico/vec

import common

import core/envelope
import core/sample
import ui/menu


type
  Kit = ref object of Machine
  KitVoice = ref object of Voice
    playing: bool
    osc: SampleOsc
    env: Envelope
    useEnv: bool
    gain: float

{.this:self.}

method addVoice*(self: Kit) =
  var voice = new(KitVoice)
  voices.add(voice)
  voice.init(self)
  voice.env.init()
  voice.osc.stereo = true

  for param in mitems(voice.parameters):
    param.value = param.default
    param.onchange(param.value, voices.high)

method init(self: Kit) =
  procCall init(Machine(self))
  name = "kit"
  nOutputs = 1
  nInputs = 0
  stereo = true

  voiceParams.add([
    Parameter(name: "trigger", separator: true, deferred: true, kind: Float, min: 0.0, max: 1.0, onchange: proc(newValue: float, voice: int) =
      var v = KitVoice(self.voices[voice])
      if v.osc.sample != nil:
        v.playing = true
        v.osc.reset()
        v.gain = newValue
        v.env.trigger()
    ),
    Parameter(name: "pitch", kind: Float, min: 0.5, max: 2.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      var v = KitVoice(self.voices[voice])
      v.osc.speed = newValue
    ),
    Parameter(name: "decay", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      var v = KitVoice(self.voices[voice])
      v.env.d = newValue
    ),
    Parameter(name: "use env", kind: Bool, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      var v = KitVoice(self.voices[voice])
      v.useEnv = newValue.bool
    ),
  ])

  setDefaults()

method process*(self: Kit) {.inline.} =
  outputSamples[0] = 0.0
  for i in 0..<voices.len:
    var v = KitVoice(voices[i])
    if v.osc.sample != nil:
      if v.playing:
        outputSamples[0] += v.osc.process() * (if v.useEnv: v.env.process() else: 1.0) * v.gain
        if v.osc.finished:
          v.playing = false

method drawExtraData(self: Kit, x,y,w,h: int) =
  var yv = y
  setColor(6)
  print("samples", x, yv)
  yv += 9
  for i in 0..<voices.len:
    var v = KitVoice(voices[i])
    print($i & ": " & (if v.osc.sample != nil: v.osc.sample.name else: " - "), x, yv)
    yv += 9

method updateExtraData(self: Kit, x,y,w,h: int) =
  if mousebtnp(1):
    let (mx,my) = mouse()
    let voice = (my - y - 9) div 9
    if voice >= 0 and voice < voices.len:
      # open sample selection menu
      pushMenu(newSampleMenu(vec2f(mx,my), basePath & "samples/") do(sample: Sample):
        var v = KitVoice(self.voices[voice])
        v.osc.sample = sample
      )

method saveExtraData(self: Kit): string =
  result = ""
  for voice in mitems(voices):
    var v = KitVoice(voice)
    if v.osc.sample != nil:
      result &= v.osc.sample.filename & "|" & v.osc.sample.name & "\n"
    else:
      result &= "\n"

method loadExtraData(self: Kit, data: string) =
  var voice = 0
  for line in data.splitLines:
    if voice > voices.high:
      break
    let sline = line.strip()
    if sline == "":
      voice += 1
      continue
    var v = KitVoice(voices[voice])
    v.osc.sample = loadSample(sline.split("|")[0], sline.split("|")[1])
    voice += 1

proc newKit(): Machine =
  var kit = new(Kit)
  kit.init()
  return kit

registerMachine("kit", newKit, "generator")

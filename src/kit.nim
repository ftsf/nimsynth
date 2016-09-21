import sdl2
import sdl2.audio
import common
import math
import env
import sample
import pico

type
  Kit = ref object of Machine
    samples: array[16, Sample]
  KitVoice = ref object of Voice
    playing: bool
    osc: SampleOsc
    env: Envelope
    gain: float
    pitch: float

{.this:self.}

method addVoice*(self: Kit) =
  pauseAudio(1)
  var voice = new(KitVoice)
  voice.init(self)
  voices.add(voice)

  voice.osc.sample = addr(self.samples[voices.high])
  voice.env.d = voice.osc.sample[].data.len.float * invSampleRate.float * 1.0

  for param in mitems(voice.parameters):
    param.value = param.default
    param.onchange(param.value, voices.high)
  pauseAudio(0)

method init(self: Kit) =
  procCall init(Machine(self))
  name = "kit"
  self.samples[0] = loadSample("samples/Kick.wav")
  self.samples[1] = loadSample("samples/Snare4.wav")
  self.samples[2] = loadSample("samples/HatClosed1.wav")
  self.samples[3] = loadSample("samples/HatOpen.wav")

  nOutputs = 1
  nInputs = 0
  stereo = true

  voiceParams.add([
    Parameter(name: "trigger", kind: Trigger, min: 0.0, max: 1.0, onchange: proc(newValue: float, voice: int) =
      if newValue == 1.0:
        var v = KitVoice(self.voices[voice])
        v.playing = true
        v.env.trigger()
    ),
    Parameter(name: "gain", kind: Float, min: 0.0, max: 2.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      var v = KitVoice(self.voices[voice])
      v.gain = newValue
    ),
    Parameter(name: "pitch", kind: Float, min: 0.001, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      var v = KitVoice(self.voices[voice])
      v.pitch = newValue
    ),
    Parameter(name: "decay", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      var v = KitVoice(self.voices[voice])
      v.env.d = v.osc.sample[].data.len.float * invSampleRate.float * newValue
    ),
  ])

  # initialise 8 voices
  for i in 0..7:
    self.addVoice()

method process*(self: Kit) {.inline.} =
  outputSamples[0] = 0.0
  for i in 0..7:
    var v = KitVoice(voices[i])
    if v.playing:
      outputSamples[0] += v.osc.process() * v.env.process() * v.gain
      if v.osc.finished:
        v.playing = false

method trigger(self: Kit, note: int) =
  echo note, " ", noteToNoteName(note)
  if note == 48:
    var v = KitVoice(voices[0])
    v.playing = true
    v.osc.reset()
  if note == 50:
    var v = KitVoice(voices[1])
    v.playing = true
    v.osc.reset()
  if note == 52:
    var v = KitVoice(voices[2])
    v.playing = true
    v.osc.reset()
  if note == 53:
    var v = KitVoice(voices[3])
    v.playing = true
    v.osc.reset()

method drawExtraInfo(self: Kit, x,y,w,h: int) =
  var yv = y
  setColor(6)
  print("samples", x, yv)
  yv += 9
  for i, sample in samples:
    print($i & ": " & (if sample.name != nil: sample.name else: " - "), x, yv)
    yv += 9

proc newKit(): Machine =
  var kit = new(Kit)
  kit.init()
  return kit

registerMachine("kit", newKit)

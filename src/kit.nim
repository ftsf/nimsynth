import sdl2
import sdl2.audio
import common
import math
import env

import sndfile

type
  Sample = seq[float32]
  Kit = ref object of Machine
    samples: array[16, Sample]
  KitVoice = ref object of Voice
    playing: bool
    sample: int
    samplePos: int
    env: Envelope
    gain: float

{.this:self.}

method addVoice*(self: Kit) =
  pauseAudio(1)
  var voice = new(KitVoice)
  voice.init(self)
  voices.add(voice)
  voice.env.d = 1.0

  for param in mitems(voice.parameters):
    param.value = param.default
    param.onchange(param.value, voices.high)
  pauseAudio(0)

proc loadSample(filename: string): Sample =
  var info: Tinfo
  var fp = sndfile.open(filename.cstring, READ, addr(info))
  if fp == nil:
    echo "error loading sample"
    return

  echo "frames: ", info.frames

  result = newSeq[float32](info.frames)

  let count = fp.read_float(addr(result[0]), info.frames)
  if count != info.frames:
    echo "only read ", count, " not ", info.frames


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
        v.samplePos = 0
        v.sample = voice
        v.env.trigger()
    ),
    Parameter(name: "gain", kind: Float, min: 0.0, max: 2.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      var v = KitVoice(self.voices[voice])
      v.gain = newValue
    ),
    Parameter(name: "decay", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      var v = KitVoice(self.voices[voice])
      v.env.d = self.samples[v.sample].len.float * invSampleRate.float * newValue
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
      if v.samplePos > samples[v.sample].high:
        v.playing = false
      else:
        outputSamples[0] += (samples[v.sample][v.samplePos] * v.env.process() * v.gain)
        v.samplePos += 1

method trigger(self: Kit, note: int) =
  echo note, " ", noteToNoteName(note)
  if note == 48:
    var v = KitVoice(voices[0])
    v.sample = 0
    v.playing = true
    v.samplePos = 0
  if note == 50:
    var v = KitVoice(voices[1])
    v.sample = 1
    v.playing = true
    v.samplePos = 0
  if note == 52:
    var v = KitVoice(voices[2])
    v.sample = 2
    v.playing = true
    v.samplePos = 0
  if note == 53:
    var v = KitVoice(voices[3])
    v.sample = 3
    v.playing = true
    v.samplePos = 0

proc newKit(): Machine =
  var kit = new(Kit)
  kit.init()
  return kit

registerMachine("kit", newKit)

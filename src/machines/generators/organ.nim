import math

import common
import util

import core.oscillator
import core.filter
import core.envelope

import machines.master


# 9 osc Organ

const nOperators = 9

const tunings = [
  0.5,
  1.0 + (8 / 12.0),
  1.0,
  2.0,
  2.0 + (7 / 12.0),
  3.0,
  3.0 + (4 / 12.0),
  3.0 + (7 / 12.0),
  4.0,
]
const names = [
  "16'",
  "5 1/3'",
  "8'",
  "4'",
  "2 2/3'",
  "2'",
  "1 3/5'",
  "1 1/3'",
  "1'",
]

type

  OrganVoice = ref object of Voice
    pitch: float
    note: int
    oscs: array[nOperators, Osc]
    env: Envelope

  Organ = ref object of Machine
    amps: array[nOperators, float]
    envSettings: tuple[a,d,s,r: float]
    tremolo: Osc
    tremoloAmount: float

{.this:self.}

method init(self: OrganVoice, machine: Organ) =
  procCall init(Voice(self), machine)

  for osc in mitems(oscs):
    osc.kind = Sin

method addVoice*(self: Organ) =
  pauseAudio(1)
  var voice = new(OrganVoice)
  voices.add(voice)
  voice.init(self)
  pauseAudio(0)

proc initNote(self: Organ, voiceId: int, note: int) =
  var voice = OrganVoice(voices[voiceId])
  if note == OffNote:
    voice.note = note
    voice.env.release()
  else:
    voice.note = note
    voice.pitch = noteToHz(note.float)
    voice.env.a = self.envSettings.a
    voice.env.d = self.envSettings.d
    voice.env.s = self.envSettings.s
    voice.env.r = self.envSettings.r
    voice.env.trigger()

method init(self: Organ) =
  procCall init(Machine(self))

  nInputs = 0
  nOutputs = 1
  stereo = false

  name = "organ"

  self.globalParams.add([
    Parameter(name: "a", kind: Float, min: 0.0, max: 1.0, default: 0.01, onchange: proc(newValue: float, voice: int) =
      self.envSettings.a = newValue
    ),
    Parameter(name: "d", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.envSettings.d = newValue
    ),
    Parameter(name: "s", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.envSettings.s = newValue
    ),
    Parameter(name: "r", kind: Float, min: 0.0, max: 1.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.envSettings.r = newValue
    ),
    Parameter(name: "tremolo spd", kind: Float, min: 0.0, max: 60.0, default: 10.0, onchange: proc(newValue: float, voice: int) =
      self.tremolo.freq = newValue
    ),
    Parameter(name: "tremolo amt", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.tremoloAmount = newValue
    ),
  ])


  for i in 0..nOperators-1:
    (proc() =
      let opId = i
      self.globalParams.add([
        Parameter(name: names[opId], kind: Int, min: 0.0, max: 8.0, default: if opId == 2: 1.0 else: 0.0, onchange: proc(newValue: float, voice: int) =
          self.amps[opId] = newValue / 8.0
        ),
      ])
    )()

  self.voiceParams.add([
    Parameter(name: "note", kind: Note, min: 0.0, max: 255.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      self.initNote(voice, newValue.int)
    , getValueString: proc(value: float, voice: int): string =
      if value == OffNote:
        return "Off"
      else:
        return noteToNoteName(value.int)
    )
  ])

  setDefaults()

  addVoice()

method process(self: Organ) {.inline.} =
  outputSamples[0] = 0

  let t = tremolo.process()

  for voice in mitems(self.voices):
    var v = OrganVoice(voice)
    for i,osc in mpairs(v.oscs):
      osc.freq = v.pitch * tunings[i]
      outputSamples[0] += osc.process() * amps[i] * v.env.process() * lerp(1.0, t, tremoloAmount)

proc newOrgan(): Machine =
  var organ = new(Organ)
  organ.init()
  return organ

registerMachine("organ", newOrgan, "generator")

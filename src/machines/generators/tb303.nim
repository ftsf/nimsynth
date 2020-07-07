import math

import common
import util

import core.oscillator
import core.filter
import core.envelope

import machines.master


type
  TB303 = ref object of Machine
    osc: Osc
    filter: BiquadFilter
    envAmp: Envelope
    envFlt: Envelope

    note: int
    slideNote: int
    nextSlideNote: int
    accentNextNote: bool
    cutoff: float
    resonance: float
    envMod: float
    accentAmount: float
    slideAmount: float
    slideTime: float


{.this:self.}

proc initNote(self: TB303, note: int) =
    self.note = note
    if self.note == OffNote:
      self.envAmp.release()
      self.envFlt.release()
      self.slideTime = Master(masterMachine).beatsPerMinute / 60.0
    else:
      self.osc.freq = noteToHz(note.float)
      self.envAmp.trigger(if self.accentNextNote: 1'f else: 0.75'f)
      self.envFlt.trigger(if self.accentNextNote: 1'f else: 0.75'f)
      self.accentNextNote = false
      self.slideAmount = 0.0
      self.slideTime = Master(masterMachine).beatsPerMinute / 60.0
      if self.nextSlideNote != self.note and self.nextSlideNote != OffNote:
        self.slideNote = self.nextSlideNote
      else:
        self.slideNote = self.note
      self.nextSlideNote = OffNote

method init(self: TB303) =
  procCall init(Machine(self))

  nInputs = 0
  nOutputs = 1
  stereo = false
  name = "303"

  osc.kind = Saw
  osc.pulseWidth = 0.5

  envAmp.a = 0.01
  envAmp.d = 0.5
  envAmp.decayKind = Exponential
  envAmp.decayExp = 50.0
  envAmp.s = 0.0
  envAmp.r = 0

  envFlt.a = 0.01
  envFlt.d = 0.5
  envFlt.decayKind = Exponential
  envFlt.decayExp = 50.0
  envFlt.s = 0.0
  envFlt.r = 0

  filter.kind = Lowpass
  filter.init()
  envAmp.init()
  envFlt.init()

  self.globalParams.add([
    Parameter(name: "note", kind: Note, min: 0.0, max: 255.0, deferred: true, default: OffNote, onchange: proc(newValue: float, voice: int) =
      self.initNote(newValue.int)
    ),
    Parameter(name: "slide", kind: Note, min: 0.0, max: 255.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      self.nextSlideNote = newValue.int
    ),
    Parameter(name: "accent", kind: Bool, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.accentNextNote = newValue.bool
    ),
    Parameter(name: "decay", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.envFlt.d = newValue.float
    ),
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.cutoff = exp(lerp(-8.0, -0.8, newValue))
    ),
    Parameter(name: "res", kind: Float, min: 0.01, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.resonance = newValue
    ),
    Parameter(name: "envMod", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.envMod = newValue
    ),
    Parameter(name: "accentMod", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.accentAmount = newValue.float
    ),
    Parameter(name: "wave", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.osc.kind = if newValue == 0: Saw else: Sqr
    ),

  ])

  setDefaults()

method process(self: TB303) =
  if slideNote != OffNote:
    slideAmount += invSampleRate
    slideAmount = clamp(slideAmount, 0.0, slideTime)
    osc.freq = lerp(noteToHz(note.float), noteToHz(slideNote.float), invLerp(0.0, slideTime, slideAmount))
  else:
    osc.freq = noteToHz(note.float)
  let amp = envAmp.process()
  filter.cutoff = cutoff + (envFlt.process() * envMod * 0.1)
  filter.resonance = resonance
  filter.calc()
  outputSamples[0] = filter.process(osc.process()) * amp

method trigger*(self: TB303, note: int) =
  self.initNote(note)

method release*(self: TB303, note: int) =
  self.initNote(OffNote)

proc newTB303(): Machine =
  var my303 = new(TB303)
  my303.init()
  return my303

registerMachine("303", newTB303, "generator")

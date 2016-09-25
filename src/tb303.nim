import common
import math
import util

import osc
import filter
import env
import master

type
  TB303 = ref object of Machine
    osc: Osc
    filter: BiquadFilter
    envAmp: Envelope
    envFlt: Envelope

    note: int
    slideNote: int
    accent: bool
    cutoff: float
    resonance: float
    envMod: float
    accentAmount: float
    slideAmount: float
    slideTime: float


{.this:self.}

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


  filter.init()

  self.globalParams.add([
    Parameter(name: "note", kind: Note, min: 0.0, max: 255.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      self.note = newValue.int
      if self.note == OffNote:
        self.envAmp.release()
        self.envFlt.release()
      else:
        self.envAmp.trigger()
        self.envFlt.trigger()
        self.slideAmount = 0.0
        self.slideTime = Master(masterMachine).beatsPerMinute / 60.0
    ),
    Parameter(name: "slide", kind: Note, min: 0.0, max: 255.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      self.slideNote = newValue.int
    ),
    Parameter(name: "accent", kind: Int, min: 0.0, max: 10.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.accent = newValue.bool
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
    Parameter(name: "accent", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
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

proc newTB303(): Machine =
  var my303 = new(TB303)
  my303.init()
  return my303

registerMachine("303", newTB303)

import math
import strutils

import random

import nico
import nico/vec

import common
import util

import core/scales

import core/basemachine
import ui/machineview
import machines/master

type
  KayoubiAlgorithm = enum
    kaTriTrance
    kaStomper
    kaMrMarkov
    kaWobble
    kaChipArp1
    kaChipArp2
    kaSampleAndHoldOn
    kaSaikoClassic
    kaSaikoLead
    kaScaleWalker
    kaTooEasy
    kaTestPattern

  KayoubiScale = enum
    ksMajor
    ksMinor
    ksDorian
    ksPentatonic
    ksMajorTriad
    ksMinorTriad
    ksBlues
    ksChromatic

  Kayoubi = ref object of Machine
    algorithm: KayoubiAlgorithm
    scale: KayoubiScale
    ticksPerBeat: int
    beatsPerLoop: int
    x,y: float32
    density: float32
    seed: int
    baseNote: int
    playing: bool

    tickTimer: int
    tickCounter: int
    beatCounter: int

    rand1: Rand
    rand2: Rand
    b1,b2,b3,b4: int

    outNote: int
    outOct: int

proc initAlgorithmTriTrance(self: Kayoubi) =
  self.rand1 = initRand(self.seed + 1)
  self.rand2 = initRand(self.seed + 2)

  self.b1 = self.rand1.next().int and 0x7
  self.b2 = self.rand1.next().int and 0x7
  self.b3 = self.rand2.next().int and 0x15
  if self.b3 >= 7:
    self.b3 -= 7
  else:
    self.b3 = 0
  self.b3 -= 4

  self.b4 = 0

proc initAlgorithm(self: Kayoubi) =
  case self.algorithm:
  of kaTriTrance:
    self.initAlgorithmTriTrance()
  else:
    discard

proc scaleToNote(self: Kayoubi): int =
  var octOffset = self.outOct
  var scaleIdx = self.outNote

  let scale = case self.scale:
  of ksMajor:
    scaleMajor
  of ksMinor:
    scaleMinor
  of ksMajorTriad:
    scaleMajorTriad
  of ksMinorTriad:
    scaleMinorTriad
  of ksDorian:
    scaleDorian
  of ksPentatonic:
    scalePentatonic
  of ksBlues:
    scaleBlues
  else:
    scaleMajor

  while scaleIdx < 0:
    scaleIdx += scale.notes.len
    octOffset -= 1

  while scaleIdx >= scale.notes.len:
    scaleIdx -= scale.notes.len
    octOffset += 1

  return self.baseNote + 12 * octOffset + scale.notes[scaleIdx mod scale.notes.len]

proc setNote(self: Kayoubi, aoct, anote: int) =
  self.outOct = aoct
  self.outNote = anote

proc processTriTrance(self: Kayoubi, I: int) =
  case (I + self.b2) mod 3:
  of 0:
    if self.rand2.rand(1) == 1 and self.rand2.rand(1) == 1:
      self.b3 = self.rand2.next().int and 0x15
      if self.b3 >= 7:
        self.b3 -= 7
      else:
        self.b3 = 0
      self.b3 -= 4
    self.setNote(0, self.b3)
  of 1:
    self.setNote(1, self.b3)
    if self.rand1.rand(1) == 1:
      self.b2 = self.rand1.next().int and 0x7
  of 2:
    self.setNote(2, self.b1)
    if self.rand1.rand(1) == 1:
      self.b1 = (self.rand1.next().int shr 5) and 0x7
  else:
    discard

  let n = self.scaleToNote()

  if self.rand1.rand(1.0) < self.density:
    if self.bindings[0].isBound():
      var (voice,param) = self.bindings[0].getParameter()
      param.value = n.float
      param.onchange(param.value, voice)


method init(self: Kayoubi) =
  procCall init(Machine(self))

  self.name = "kayoubi"
  self.nOutputs = 0
  self.nInputs = 0
  self.nBindings = 1
  self.bindings.setLen(1)

  self.globalParams.add([
    Parameter(kind: Int, name: "algorithm", min: 0.0, max: KayoubiAlgorithm.high.float, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.algorithm = newValue.int.KayoubiAlgorithm
      self.initAlgorithm()
    , getValueString: proc(value: float, voice: int): string =
        return $value.KayoubiAlgorithm
    ),
    Parameter(kind: Note, name: "base", min: OffNote, max: 255.0, default: 48.0, onchange: proc(newValue: float, voice: int) =
      self.baseNote = newValue.int
    ),
    Parameter(kind: Trigger, name: "trigger", min: 0.0, max: 1.0, ignoreSave: true, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.playing = newValue.int != 0
      self.tickTimer = 0
      self.tickCounter = 0
      self.beatCounter = 0
    ),
    Parameter(kind: Int, name: "scale", min: 0.0, max: KayoubiScale.high.float, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.scale = newValue.int.KayoubiScale
    , getValueString: proc(value: float, voice: int): string =
      return $value.KayoubiScale
    ),
    Parameter(kind: Int, name: "TPB", min: 1, max: 16.0, default: 5.0, onchange: proc(newValue: float, voice: int) =
      self.ticksPerBeat = newValue.int
    ),
    Parameter(kind: Int, name: "BPL", min: 4.0, max: 32.0, default: 4.0, onchange: proc(newValue: float, voice: int) =
      self.beatsPerLoop = newValue.int
    ),
    Parameter(kind: Float, name: "X", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.x = newValue
    ),
    Parameter(kind: Float, name: "Y", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.y = newValue
    ),
    Parameter(kind: Float, name: "density", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.density = newValue
    ),
    Parameter(kind: Int, name: "seed", min: 0.0, max: (2^15).float, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.seed = newValue.int
      self.initAlgorithm()
    ),
  ])

  self.setDefaults()

method process(self: Kayoubi) =
  if self.baseNote == OffNote or not self.playing:
    return
  self.tickTimer -= 1
  if self.tickTimer <= 0:
    self.tickTimer += (sampleRate.int / (beatsPerSecond() * self.ticksPerBeat)).int
    self.tickCounter += 1
    if self.tickCounter >= self.ticksPerBeat:
      self.tickCounter = 0
      self.beatCounter += 1

    case self.algorithm:
    of kaTriTrance:
      self.processTriTrance(self.tickCounter + self.beatCounter)
    else:
      discard

proc newKayoubi(): Machine =
  var m = new(Kayoubi)
  m.init()
  return m

registerMachine("kayoubi", newKayoubi, "generator")

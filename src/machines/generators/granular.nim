import math
import strutils

import nico
import nico/vec

import common
import util

import core/sample
import core/filter
import core/envelope

import random

import ui/menu

func smoothstep(x, edge0, edge1: float32): float32 =
  var X = clamp((x - edge0) / (edge1 - edge0))
  return X * X * (3.0f - 2.0f * X)

type
  Grain = object
    alive: bool
    pos: float32
    speed: float32
    duration: int
    time: int
    pan: float32

  GranularVoice = ref object of Voice
    pitch: float32
    note: int
    velocity: float32
    oscIndex: int
    nextGrainClock: int
    env: Envelope
    filterL: BiquadFilter
    filterR: BiquadFilter
    glissando: OnePoleFilter
    grains: seq[Grain]
    pos: float32

  GranularSynth = ref object of Machine
    glissando: float32
    filterKind: FilterKind
    cutoff: float32
    resonance: float32
    envSettings: EnvelopeSettings

    keytracking: float32
    keytrkReference: int

    sourceSample: Sample
    sampleStart,sampleEnd: float32

    pitchRange: float32
    posRange: float32
    panRange: float32
    size: float32
    sizeRange: float32
    rate: float32
    rateRange: float32

    maxGrains: int

    scanSpeed: float32

proc spawnGrain(self: GranularVoice, machine: GranularSynth) =
  # find free grain
  var index = -1
  for i, g in self.grains:
    if not g.alive:
      index = i
      break
    if i >= machine.maxGrains:
      break
  if index != -1:
    var grain: Grain
    grain.alive = true
    grain.pos = self.pos + ((rand(machine.posRange) - machine.posRange * 0.5f) * machine.sourceSample.length.float32)
    grain.duration = max(((machine.size * 1.0f + (rand(machine.sizeRange) - machine.sizeRange * 0.5f)) * sampleRate).int, 10)
    grain.speed = self.pitch / machine.sourceSample.rootPitch
    grain.speed *= 1.0f + (rand(machine.pitchRange) - machine.pitchRange * 0.5f)
    grain.time = 0
    grain.pan = 0f + rand(machine.panRange) - machine.panRange * 0.5f
    #echo "spawning grain ", index, " duration: ", grain.duration, " pos: ", grain.pos, " speed: ", grain.speed
    self.grains[index] = grain

method init*(self: GranularVoice, machine: Machine) =
  procCall init(Voice(self), machine)

  var machine = GranularSynth(machine)

  self.env.init()
  self.env.a = machine.envSettings.a
  self.env.d = machine.envSettings.d
  self.env.decayKind = Exponential
  self.env.decayExp = machine.envSettings.decayExp
  self.env.s = machine.envSettings.s
  self.env.r = machine.envSettings.r

  self.filterL.kind = Lowpass
  self.filterL.setCutoff(machine.cutoff)
  self.filterL.resonance = machine.resonance
  self.filterL.init()
  self.filterR.kind = Lowpass
  self.filterR.setCutoff(machine.cutoff)
  self.filterR.resonance = machine.resonance
  self.filterR.init()

  self.glissando.kind = Lowpass
  self.glissando.init()

  self.nextGrainClock = 0
  self.pitch = 0.0

  self.grains = newSeq[Grain](machine.maxGrains)

method addVoice*(self: GranularSynth) =
  var voice = new(GranularVoice)
  self.voices.add(voice)
  voice.init(self)

proc initNote(self: GranularSynth, voiceId: int, note: int) =
    var voice = GranularVoice(self.voices[voiceId])
    voice.note = note
    if note == OffNote:
      voice.env.release()
    else:
      voice.pitch = noteToHz(note.float32)
      voice.env.trigger(voice.velocity)
      voice.nextGrainClock = 0


method init*(self: GranularSynth) =
  procCall init(Machine(self))
  self.name = "granular"
  self.nInputs = 0
  self.nOutputs = 1
  self.stereo = true
  self.useKeyboard = true


  self.globalParams.add([
    Parameter(name: "filt", kind: Int, separator: true, min: FilterKind.low.float32, max: FilterKind.high.float32, default: Lowpass.float32, onchange: proc(newValue: float32, voice: int) =
      self.filterKind = newValue.FilterKind
    , getValueString: proc(value: float32, voice: int): string =
        return $(value.FilterKind)
    ),
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float32, voice: int) =
      self.cutoff = exp(lerp(-8.0, -0.8, newValue)), getValueString: proc(value: float32, voice: int): string =
      return $(exp(lerp(-8.0, -0.8, value)) * sampleRate).int & " hZ"
    ),
    Parameter(name: "q", kind: Float, min: 0.0001, max: 10.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.resonance = newValue
    ),
    Parameter(name: "env a", kind: Float, separator: true, min: 0.0, max: 5.0, default: 0.001, onchange: proc(newValue: float32, voice: int) =
      self.envSettings.a = exp(newValue) - 1.0
    , getValueString: proc(value: float32, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env d", kind: Float, min: 0.0, max: 5.0, default: 0.1, onchange: proc(newValue: float32, voice: int) =
      self.envSettings.d = exp(newValue) - 1.0
    , getValueString: proc(value: float32, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env ds", kind: Float, min: 0.1, max: 10.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.envSettings.decayExp = newValue
    ),
    Parameter(name: "env s", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float32, voice: int) =
      self.envSettings.s = newValue
    ),
    Parameter(name: "env r", kind: Float, min: 0.0, max: 5.0, default: 0.01, onchange: proc(newValue: float32, voice: int) =
      self.envSettings.r = exp(newValue) - 1.0
    , getValueString: proc(value: float32, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "sampleStart", kind: Float, min: 0.0, max: 0.9, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.sampleStart = newValue
    ),
    Parameter(name: "sampleEnd", kind: Float, min: 0.1, max: 1.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.sampleEnd = newValue
    ),
    Parameter(name: "scan", kind: Float, min: -5.0, max: 5.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.scanSpeed = newValue
    ),
    Parameter(name: "size", kind: Float, separator: true, min: 0.01, max: 1f, default: 0.1, onchange: proc(newValue: float32, voice: int) =
      self.size = newValue
    ),
    Parameter(name: "sizeRange", kind: Float, separator: true, min: 0f, max: 1f, default: 0.1, onchange: proc(newValue: float32, voice: int) =
      self.sizeRange = newValue
    ),
    Parameter(name: "posRange", kind: Float, separator: true, min: 0f, max: 1f, default: 0.01, onchange: proc(newValue: float32, voice: int) =
      self.posRange = newValue
    ),
    Parameter(name: "pitchRange", kind: Float, separator: true, min: 0.00, max: 10.0, default: 0.1, onchange: proc(newValue: float32, voice: int) =
      self.pitchRange = newValue
    ),
    Parameter(name: "panRange", kind: Float, separator: true, min: 0.00, max: 1.0, default: 0.1, onchange: proc(newValue: float32, voice: int) =
      self.panRange = newValue
    ),
    Parameter(name: "rate", kind: Float, separator: true, min: 0f, max: 2000f, default: 100f, onchange: proc(newValue: float32, voice: int) =
      self.rate = newValue
    ),
    Parameter(name: "rateRange", kind: Float, separator: true, min: 0f, max: 100f, default: 1f, onchange: proc(newValue: float32, voice: int) =
      self.rateRange = newValue
    ),
    Parameter(name: "maxGrains", kind: Int, separator: true, min: 1, max: 10000, default: 1000, onchange: proc(newValue: float32, voice: int) =
      self.maxGrains = newValue.int
    ),
    Parameter(name: "glissando", kind: Float, separator: true, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.glissando = exp(lerp(-12.0, 0.0, 1.0-newValue))
    ),
    Parameter(name: "ktrk", kind: Float, min: -2.0, max: 2.0, default: 0.5, onchange: proc(newValue: float32, voice: int) =
      self.keytracking = newValue
    ),
    Parameter(name: "ref", kind: Note, min: 0, max: 256.0, default: 60.0, onchange: proc(newValue: float32, voice: int) =
      self.keytrkReference = newValue.int
    ),
  ])
  self.voiceParams.add([
    Parameter(name: "note", kind: Note, deferred: true, separator: true, min: OffNote, max: 255.0, default: OffNote, onchange: proc(newValue: float32, voice: int) =
      self.initNote(voice, newValue.int)
    , getValueString: proc(value: float32, voice: int): string =
      if value == OffNote:
        return "Off"
      else:
        return noteToNoteName(value.int)

    ),
    Parameter(name: "vel", kind: Float, min: 0.0, max: 1.0, seqkind: skInt8, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      var voice = GranularVoice(self.voices[voice])
      voice.velocity = newValue
    ),
  ])

  self.setDefaults()

  self.addVoice()

proc newGranular*(): Machine =
  result = new(GranularSynth)
  result.init()

registerMachine("granular", newGranular, "generator")

method process*(self: GranularSynth) {.inline.} =
  self.outputSamples[0] = 0

  if self.sourceSample == nil:
    return

  for voice in mitems(self.voices):
    var v = GranularVoice(voice)
    v.env.updateFromSettings(self.envSettings)

    v.glissando.setCutoff(self.glissando)
    v.glissando.calc()

    if sampleId mod 2 == 0:
      v.pos += self.scanSpeed * (self.sourceSample.rate * invSampleRate)
      if v.pos > self.sourceSample.length.float32:
        v.pos -= self.sourceSample.length.float32
      if v.pos < 0f:
        v.pos += self.sourceSample.length.float32

      let baseFreq = v.glissando.process(v.pitch)

      if v.nextGrainClock <= 0:
        v.spawnGrain(self)
        let rate = self.rate + (rand(self.rateRange) - self.rateRange * 0.5f)
        v.nextGrainClock = max((sampleRate / rate).int, 1)
      elif v.nextGrainClock > 0:
        v.nextGrainClock -= 1

      discard v.env.process()

    var vs = 0'f

    for g in v.grains.mitems:
      if g.alive:
        if sampleId mod 2 == 0:
          g.time += 1
          g.pos += g.speed * (self.sourceSample.rate * invSampleRate)
          if g.time > g.duration:
            g.alive = false

        var gs = self.sourceSample.getInterpolatedSampleLoop(g.pos, if self.sourceSample.channels == 1: 0 else: sampleId mod 2)
        gs = panSample(gs, g.pan, sampleId mod 2)
        var genvPos = clamp(g.time.float32 / g.duration.float32, 0f, 1f)
        var genv = smoothstep(0f, 0.5f, genvPos) - smoothstep(0.5f, 1f, genvPos)
        gs *= genv
        vs += gs

    let envValue = v.env.level

    if sampleId mod 2 == 0:
      v.filterL.kind = self.filterKind
      v.filterL.cutoff = self.cutoff * (1.0'f + pow(2.0'f, (((hzToNote(v.pitch) - self.keytrkReference.float32) / 12.0'f) * self.keytracking)))
      v.filterL.resonance = max(0.0001, self.resonance)
      v.filterL.calc()
      vs = v.filterL.process(vs)
    else:
      v.filterR.kind = self.filterKind
      v.filterR.cutoff = self.cutoff * (1.0'f + pow(2.0'f, (((hzToNote(v.pitch) - self.keytrkReference.float32) / 12.0'f) * self.keytracking)))
      v.filterR.resonance = max(0.0001, self.resonance)
      v.filterR.calc()
      vs = v.filterR.process(vs)

    vs *= envValue

    self.outputSamples[0] += vs

method drawExtraData(self: GranularSynth, x,y,w,h: int) =
  var yv = y
  setColor(6)
  print("sample", x, yv)
  yv += 9
  print(if self.sourceSample != nil: self.sourceSample.name else: " - ", x, yv)
  yv += 9

  if self.sourceSample != nil:
    self.sourceSample.drawSample(x,yv,w,64, self.sampleStart, self.sampleEnd)

    for voice in self.voices:
      var v = GranularVoice(voice)
      for g in v.grains:
        if g.alive:
          let gSamplePos = floorMod(g.pos, self.sourceSample.length).float32 / self.sourceSample.length.float32
          let gEnvPos = clamp(g.time.float32 / g.duration.float32, 0f, 1f)
          var genv = smoothstep(0f, 0.5f, genvPos) - smoothstep(0.5f, 1f, genvPos)
          let xpos = x + (gSamplePos * w.float32).int
          let ymid = ((yv+64) - yv)
          let yheight = (genv * 32f).int
          setColor(11)
          vline(xpos, ymid - yheight, ymid + yheight)

  yv += 64

  yv += 10

  setColor(1)
  line(x, yv + 48, x + w, yv + 48)
  setColor(5)
  drawEnvs([self.envSettings], x,yv,w,48)
  yv += 64

method updateExtraData(self: GranularSynth, x,y,w,h: int) =
  if mousebtnp(0):
    let (mx,my) = mouse()
    if mx > x + w div 2:
      # open sample selection menu
      pushMenu(newDefaultSampleMenu(vec2f(mx,my)) do(sample: Sample):
        self.sourceSample = sample
      )

method saveExtraData(self: GranularSynth): string =
  if self.sourceSample == nil:
    return ""
  return self.sourceSample.filename

method loadExtraData(self: GranularSynth, data: string) =
  if data == "":
    return
  self.sourceSample = loadSample(data, "")

method trigger*(self: GranularSynth, note: int) =
  for i,voice in mpairs(self.voices):
    var v = GranularVoice(voice)
    if v.note == OffNote:
      self.initNote(i, note)
      let param = v.getParameter(0)
      param.value = note.float32
      return

method release*(self: GranularSynth, note: int) =
  for i,voice in mpairs(self.voices):
    var v = GranularVoice(voice)
    if v.note == note:
      self.initNote(i, OffNote)
      let param = v.getParameter(0)
      param.value = OffNote.float32

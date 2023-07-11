import math
import strutils

import nico
import nico/vec

import ../../common
import ../../util

import ../../core/sample
import ../../core/filter
import ../../core/envelope

import ../../ui/menu

type
  GranularVoice = ref object of Voice
    pitch: float32
    note: int
    velocity: float32
    grainPhase: float32
    grainIndices: array[2, int]
    oscIndex: int
    nextGrainClock: int
    sampleOscs: array[2,SampleOsc]
    env: Envelope
    filter: BiquadFilter
    glissando: OnePoleFilter

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
    grainStart: float32
    grainRandom: float32
    grainSize: float32
    grains: seq[Sample]
    crossfade: float32
    chaos: float32
    speed: float32

method init*(self: GranularVoice, machine: GranularSynth) =
  procCall init(Voice(self), machine)

  self.env.init()
  self.env.a = machine.envSettings.a
  self.env.d = machine.envSettings.d
  self.env.decayKind = Exponential
  self.env.decayExp = machine.envSettings.decayExp
  self.env.s = machine.envSettings.s
  self.env.r = machine.envSettings.r

  self.filter.kind = Lowpass
  self.filter.setCutoff(machine.cutoff)
  self.filter.resonance = machine.resonance
  self.filter.init()

  self.glissando.kind = Lowpass
  self.glissando.init()

  self.nextGrainClock = 0
  self.pitch = 0.0

method addVoice*(self: GranularSynth) =
  var voice = new(GranularVoice)
  self.voices.add(voice)
  voice.init(self)

proc generateGrains(self: GranularSynth) =
  self.grains = @[]
  if self.sourceSample == nil:
    return
  let samplesPerGrain = (self.grainSize * sampleRate).int
  let crossfadeSamples = (self.grainSize * self.crossfade * sampleRate).int

  var startSample = (self.sampleStart * (self.sourceSample.length-1).float32).int
  var endSample = (self.sampleEnd * (self.sourceSample.length-1).float32).int

  if startSample > endSample:
    return
  let length = endSample - startSample
  for i in 0..<length div samplesPerGrain:
    # create new samples out of each chunk
    let start = startSample + i * samplesPerGrain - crossfadeSamples
    let size = samplesPerGrain + crossfadeSamples * 2
    self.grains.add(self.sourceSample.subSample(start, size, crossfadeSamples))

proc initNote(self: GranularSynth, voiceId: int, note: int) =
    var voice = GranularVoice(self.voices[voiceId])
    voice.note = note
    if note == OffNote:
      voice.env.release()
    else:
      voice.pitch = noteToHz(note.float)
      voice.env.trigger(voice.velocity)
      voice.grainPhase = floorMod(self.grainStart + ((rnd(2'f) - 1'f) * self.grainRandom), 1'f)
      voice.nextGrainClock = 0


method init*(self: GranularSynth) =
  procCall init(Machine(self))
  self.name = "granular"
  self.nInputs = 0
  self.nOutputs = 1
  self.useKeyboard = true


  self.globalParams.add([
    Parameter(name: "filt", kind: Int, separator: true, min: FilterKind.low.float, max: FilterKind.high.float, default: Lowpass.float, onchange: proc(newValue: float, voice: int) =
      self.filterKind = newValue.FilterKind
    , getValueString: proc(value: float, voice: int): string =
        return $(value.FilterKind)
    ),
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.cutoff = exp(lerp(-8.0, -0.8, newValue)), getValueString: proc(value: float, voice: int): string =
      return $(exp(lerp(-8.0, -0.8, value)) * sampleRate).int & " hZ"
    ),
    Parameter(name: "q", kind: Float, min: 0.0001, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.resonance = newValue
    ),
    Parameter(name: "env a", kind: Float, separator: true, min: 0.0, max: 5.0, default: 0.001, onchange: proc(newValue: float, voice: int) =
      self.envSettings.a = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env d", kind: Float, min: 0.0, max: 5.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.envSettings.d = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "env ds", kind: Float, min: 0.1, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.envSettings.decayExp = newValue
    ),
    Parameter(name: "env s", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.envSettings.s = newValue
    ),
    Parameter(name: "env r", kind: Float, min: 0.0, max: 5.0, default: 0.01, onchange: proc(newValue: float, voice: int) =
      self.envSettings.r = exp(newValue) - 1.0
    , getValueString: proc(value: float, voice: int): string =
      return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
    ),
    Parameter(name: "sampleStart", kind: Float, min: 0.0, max: 0.9, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.sampleStart = newValue
      self.generateGrains()
    ),
    Parameter(name: "sampleEnd", kind: Float, min: 0.1, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.sampleEnd = newValue
      self.generateGrains()
    ),
    Parameter(name: "speed", kind: Float, min: -5.0, max: 5.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.speed = newValue
    ),
    Parameter(name: "grainSize", kind: Float, separator: true, min: 0.01, max: 0.5, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.grainSize = newValue
      self.generateGrains()
    ),
    Parameter(name: "grainStart", kind: Float, separator: true, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.grainStart = newValue
    ),
    Parameter(name: "grainRandom", kind: Float, separator: true, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.grainRandom = newValue
    ),
    Parameter(name: "crossfade", kind: Float, min: 0.0, max: 0.5, default: 0.01, onchange: proc(newValue: float, voice: int) =
      self.crossfade = newValue
      self.generateGrains()
    ),
    Parameter(name: "chaos", kind: Float, min: 0.0, max: 1.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.chaos = newValue
    ),
    Parameter(name: "glissando", kind: Float, separator: true, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.glissando = exp(lerp(-12.0, 0.0, 1.0-newValue))
    ),
    Parameter(name: "ktrk", kind: Float, min: -2.0, max: 2.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.keytracking = newValue
    ),
    Parameter(name: "ref", kind: Note, min: 0, max: 256.0, default: 60.0, onchange: proc(newValue: float, voice: int) =
      self.keytrkReference = newValue.int
    ),
  ])
  self.voiceParams.add([
    Parameter(name: "note", kind: Note, deferred: true, separator: true, min: OffNote, max: 255.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      self.initNote(voice, newValue.int)
    , getValueString: proc(value: float, voice: int): string =
      if value == OffNote:
        return "Off"
      else:
        return noteToNoteName(value.int)

    ),
    Parameter(name: "vel", kind: Float, min: 0.0, max: 1.0, seqkind: skInt8, default: 1.0, onchange: proc(newValue: float, voice: int) =
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

  for voice in mitems(self.voices):
    var v = GranularVoice(voice)
    v.env.a = self.envSettings.a
    v.env.d = self.envSettings.d
    v.env.decayExp = self.envSettings.decayExp
    v.env.s = self.envSettings.s
    v.env.r = self.envSettings.r

    v.glissando.setCutoff(self.glissando)
    v.glissando.calc()

    let baseFreq = v.glissando.process(v.pitch)

    if v.nextGrainClock <= 0:
      if self.grains.len > 0:
        v.grainIndices[v.oscIndex] = (floorMod(v.grainPhase + ((rnd(2'f) - 1'f) * self.chaos), 1'f) * self.grains.len.float32).int
        v.sampleOscs[v.oscIndex].sample = self.grains[v.grainIndices[v.oscIndex]]
        v.sampleOscs[v.oscIndex].reset()
        v.sampleOscs[v.oscIndex].speed = v.pitch / self.sourceSample.rootPitch
        v.sampleOscs[v.oscIndex].loop = false
        v.sampleOscs[v.oscIndex].stereo = false
        v.nextGrainClock = ((v.sampleOscs[v.oscIndex].sample.length - (self.grainSize * self.crossfade * sampleRate).int).float32 / v.sampleOscs[v.oscIndex].speed).int
        v.oscIndex = (v.oscIndex + 1) mod v.sampleOscs.len
    elif v.nextGrainClock > 0:
      v.nextGrainClock -= 1

    v.grainPhase += self.speed * invSampleRate
    v.grainPhase = floorMod(v.grainPhase, 1'f)

    #var vs = (osc1out * osc1Amount + osc2out * (osc2Amount + env3v * env3O2GainMod) + v.osc3.process() * osc3Amount + v.osc4.process() * osc4Amount) * env1v

    var vs = 0'f

    let envValue = v.env.process()

    for i in 0..<v.sampleOscs.len:
      vs += v.sampleOscs[i].process()

    v.filter.kind = self.filterKind
    v.filter.cutoff = self.cutoff * (1.0'f + pow(2.0'f, (((hzToNote(v.pitch) - self.keytrkReference.float32) / 12.0'f) * self.keytracking)))
    v.filter.resonance = max(0.0001, self.resonance)
    v.filter.calc()
    vs = v.filter.process(vs)

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

    let samplesPerGrain = (self.grainSize * sampleRate).int

    var startSample = (self.sampleStart * (self.sourceSample.length-1).float32).int
    var endSample = (self.sampleEnd * (self.sourceSample.length-1).float32).int
    let crossfadeSamples = (self.grainSize * self.crossfade * sampleRate).int

    if startSample < endSample:
      if self.grains.len > 0:
        let length = endSample - startSample

        for i in 0..<length div samplesPerGrain:
          # create new samples out of each chunk
          let start = startSample + i * samplesPerGrain - crossfadeSamples
          let size = samplesPerGrain + crossfadeSamples * 2
          setColor(1)
          for v in self.voices:
            var gv = (GranularVoice)v
            if gv.grainIndices[0] == i:
              setColor(11)
              break
            elif gv.grainIndices[1] == i:
              setColor(12)
              break

          if i mod 2 == 0:
            rect(
              lerp(x.float32, (x+w-1).float32, (start - startSample).float32 / length.float32),
              yv,
              lerp(x.float32, (x+w-1).float32, ((start - startSample)+size-1).float32 / length.float32),
              yv + 64
            )
          else:
            rect(
              lerp(x.float32, (x+w-1).float32, (start - startSample).float32 / length.float32),
              yv + 10,
              lerp(x.float32, (x+w-1).float32, ((start - startSample)+size-1).float32 / length.float32),
              yv + 54
            )


    setColor(6)
    for v in self.voices:
      var gv = (GranularVoice)v
      vline(lerp(x.float32, (x+w-1).float32, gv.grainPhase), yv, yv + 64)

  yv += 64

  yv += 10

  for v in self.voices:
    var gv = (GranularVoice)v
    setColor(6)
    print(gv.grainPhase.formatFloat(ffDecimal, 4), x, yv)
    yv += 10

  yv += 10

  setColor(1)
  line(x, yv + 48, x + w, yv + 48)
  setColor(5)
  drawEnvs([self.envSettings], x,yv,w,48)
  yv += 64

method updateExtraData(self: GranularSynth, x,y,w,h: int) =
  if mousebtnp(0):
    let (mx,my) = mouse()
    # open sample selection menu
    pushMenu(newSampleMenu(vec2f(mx,my), "samples/") do(sample: Sample):
      self.sourceSample = sample.toMono()
      self.generateGrains()
    )

method saveExtraData(self: GranularSynth): string =
  if self.sourceSample == nil:
    return ""
  return self.sourceSample.filename

method loadExtraData(self: GranularSynth, data: string) =
  if data == "":
    return
  self.sourceSample = loadSample(data, "").toMono()

method trigger*(self: GranularSynth, note: int) =
  for i,voice in mpairs(self.voices):
    var v = GranularVoice(voice)
    if v.note == OffNote:
      self.initNote(i, note)
      let param = v.getParameter(0)
      param.value = note.float
      return

method release*(self: GranularSynth, note: int) =
  for i,voice in mpairs(self.voices):
    var v = GranularVoice(voice)
    if v.note == note:
      self.initNote(i, OffNote)
      let param = v.getParameter(0)
      param.value = OffNote.float

import common
import math
import util

{.this:self.}

type
  LFSR = object
    start: int
    lfsr: int
    period: uint
    output: float32

proc process(self: var LFSR): float32 =
  let lsb: uint = (lfsr and 1)
  lfsr = lfsr shr 1
  if lsb == 1:
    lfsr = lfsr xor 0xb400;
  result = if lsb == 1: 1.0 else: -1.0
  output = result


type
  GBPulseOsc = object
    freq: float
    phase: float
    pulse: int

  GBWaveOsc = object
    freq: float
    wave: int
    phase: float

  GBNoiseOsc = object
    freq: float
    lfsr: LFSR
    nextClick: int

const pulseRom = [
  [0,0,0,0, 1,0,0,0],
  [0,0,0,0, 1,1,0,0],
  [0,0,1,1, 1,1,0,0],
  [1,1,1,1, 0,0,1,1],
]

const waveRom = [
  [0,1,2,3, 4,5,6,7, 8,9,10,11, 12,13,14,15, 15,14,13,12, 11,10,9,8, 7,6,5,4, 3,2,1,0], # tri
  [0,0,1,1, 2,2,3,3, 4,4,5,5, 6,6,7,7, 8,8,9,9, 10,10,11,11, 12,12,13,13, 14,14,15,15], # saw
]

proc process(self: var GBPulseOsc): float32 =
  result = (if pulseRom[pulse][floor(invLerp(0.0, TAU, phase) * 8.0).int] == 1: 1.0 else: -1.0)
  phase += (freq * invSampleRate) * TAU
  phase = phase mod TAU

proc process(self: var GBWaveOsc): float32 =
  phase += (freq * invSampleRate) * TAU
  if phase >= TAU:
    phase -= TAU
  result = (waveRom[wave][floor(invLerp(0.0, TAU, phase) * 32.0).int].float / 7.5) - 1.0

type
  GBSynthVoice = object
    note: int
    noteLength: int

    sweepTime: int
    sweepMode: int
    sweepShift: int

    envInit: int
    envMode: int
    envChange: int

    left: bool
    right: bool

    # internal
    enabled: bool
    volume: int
    nextEnvUpdate: int
    nextSweepUpdate: int
    samplesLeft: int
    output: float32

  GBSynth = ref object of Machine
    gbVoices: array[4, GBSynthVoice]
    gbOsc0: GBPulseOsc
    gbOsc1: GBPulseOsc
    gbOsc2: GBWaveOsc
    gbOsc3: GBNoiseOsc

method init*(self: GBSynth) =
  procCall init(Machine(self))

  name = "gb"
  nInputs = 0
  nOutputs = 1
  stereo = true

  gbOsc0.pulse = 2
  gbOsc1.pulse = 1
  gbOsc3.lfsr.lfsr = 0xfeed

  for i in 0..3:
    (proc() =
      let voiceId = i
      self.globalParams.add([
        Parameter(name: $voiceId & ":note", separator: true, kind: Note, min: OffNote, max: 255.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
          var v = self.gbVoices[voiceId].addr
          if newValue == OffNote:
            v.samplesLeft = 0
            v.enabled = false
          else:
            v.note = newValue.int
            case voiceId:
            of 0:
              self.gbOsc0.freq = noteToHz(newValue)
              v.nextSweepUpdate = 375 * v.sweepTime
            of 1:
              self.gbOsc1.freq = noteToHz(newValue)
            of 2:
              self.gbOsc2.freq = noteToHz(newValue)
            of 3:
              self.gbOsc3.freq = noteToHz(newValue)
              self.gbOsc3.nextclick = ((1.0 / self.gbOsc3.freq) * sampleRate).int
            else:
              discard

            v.nextEnvUpdate = 750
            v.samplesLeft = v.noteLength
            v.volume = if voice == 2: 15 else: v.envInit
            v.enabled = true

        , getValueString: proc(value: float, voice: int): string =
          if value == OffNote:
            return "Off"
          else:
            return noteToNoteName(value.int)
        ),
        Parameter(name: $voiceId & ":len", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          var v = self.gbVoices[voiceId].addr
          v.noteLength = (newValue * sampleRate.float).int
        ),
        Parameter(name: $voiceId & ":left", kind: Int, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
          var v = self.gbVoices[voiceId].addr
          v.left = newValue.bool
        ),
        Parameter(name: $voiceId & ":right", kind: Int, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
          var v = self.gbVoices[voiceId].addr
          v.right = newValue.bool
        ),
      ])
      if voiceId != 2:
        self.globalParams.add([
          Parameter(name: $voiceId & ":env init", kind: Int, min: 0.0, max: 15.0, default: 15.0, onchange: proc(newValue: float, voice: int) =
            var v = self.gbVoices[voiceId].addr
            v.envInit = newValue.int
          ),
          Parameter(name: $voiceId & ":env mode", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
            var v = self.gbVoices[voiceId].addr
            v.envMode = newValue.int
          ),
          Parameter(name: $voiceId & ":env change", kind: Int, min: 0.0, max: 7.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
            var v = self.gbVoices[voiceId].addr
            v.envChange = newValue.int
          ),
        ])
      else:
        # wave select
        self.globalParams.add([
          Parameter(name: $voiceId & ":wave", kind: Int, min: 0.0, max: waveRom.high.float, default: 0.0, onchange: proc(newValue: float, voice: int) =
            self.gbOsc2.wave = newValue.int
          ),
        ])
      if i == 0:
        # sweep params
        self.globalParams.add([
          Parameter(name: $voiceId & ":sweep time", kind: Int, min: 0.0, max: 7.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
            var v = self.gbVoices[voiceId].addr
            v.sweepTime = newValue.int
          ),
          Parameter(name: $voiceId & ":sweep mode", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
            var v = self.gbVoices[voiceId].addr
            v.sweepMode = newValue.int
          ),
          Parameter(name: $voiceId & ":sweep shift", kind: Int, min: 0.0, max: 7.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
            var v = self.gbVoices[voiceId].addr
            v.sweepShift = newValue.int
          ),
        ])
      if i == 0 or i == 1:
        # pulse specific params
        self.globalParams.add([
          Parameter(name: $voiceId & ":pw", kind: Int, min: 0.0, max: 3.0, default: 2.0, onchange: proc(newValue: float, voice: int) =
            if voiceId == 0:
              self.gbOsc0.pulse = newValue.int
            elif voiceId == 1:
              self.gbOsc1.pulse = newValue.int
          , getValueString: proc(value: float, voice: int): string =
            case value.int:
            of 0:
              return "0.125"
            of 1:
              return "0.25"
            of 2:
              return "0.50"
            of 3:
              return "0.75"
            else:
              return "0.50"
          ),
        ])
    )()

  setDefaults()

proc to4bit(input: float32): float32 =
  result = floor(input * 8.0) / 8.0

method process*(self: GBSynth) {.inline.} =
  outputSamples[0] = 0.0

  if sampleId mod 2 == 0:
    for i in 0..3:
      var v = addr(gbVoices[i])
      if v.enabled:
        v.nextEnvUpdate -= 1
        if v.nextEnvUpdate <= 0:
          if v.envMode == 0:
            v.volume -= v.envChange
          if v.envMode == 1:
            v.volume += v.envChange
          v.volume = clamp(v.volume, 0, 15)
          v.nextEnvUpdate = 750

        if i == 0 and v.sweepTime > 0:
            v.nextSweepUpdate -= 1
            if v.nextSweepUpdate <= 0:
              # TODO: adjust frequency
              v.nextSweepUpdate = 375 * v.sweepTime

        if i == 3:
          gbOsc3.nextclick -= 1
          if gbOsc3.nextclick == 0:
            v.output = gbOsc3.lfsr.process() * (v.volume.float / 15.0)
            gbOsc3.nextclick = ((1.0 / gbOsc3.freq) * sampleRate).int
          else:
            v.output = gbOsc3.lfsr.output * (v.volume.float / 15.0)
        else:
          if i == 0:
            v.output = gbOsc0.process() * (v.volume.float / 15.0)
          elif i == 1:
            v.output = gbOsc1.process() * (v.volume.float / 15.0)
          elif i == 2:
            v.output = gbOsc2.process()

        if v.noteLength != 0:
          v.samplesLeft -= 1
          if v.samplesLeft == 0:
            v.enabled = false
      else:
        v.output = 0.0

      if v.left:
        outputSamples[0] += v.output
  else:
    for i in 0..3:
      var v = addr(gbVoices[i])
      if v.right:
        outputSamples[0] += v.output
  # convert to 4 bit audio
  outputSamples[0] = to4bit(outputSamples[0])

proc newGBSynth(): Machine =
  var gbs = new(GBSynth)
  gbs.init()
  return gbs

registerMachine("gb", newGBSynth, "generator")

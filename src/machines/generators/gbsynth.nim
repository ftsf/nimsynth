import math

import common
import util
import nico

import ui/machineview
import core/lfsr


{.this:self.}

type
  GBPulseOsc = object
    freq: float
    phase: float
    pulse: int

  GBWaveOsc = object
    freq: float
    wave: int
    phase: float
    waveRam: array[16, array[32, uint8]]

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
  [0'u8,1,2,3, 4,5,6,7, 8,9,10,11, 12,13,14,15, 15,14,13,12, 11,10,9,8, 7,6,5,4, 3,2,1,0], # tri
  [0'u8,0,1,1, 2,2,3,3, 4,4,5,5, 6,6,7,7, 8,8,9,9, 10,10,11,11, 12,12,13,13, 14,14,15,15], # saw
]

proc process(self: var GBPulseOsc): float32 =
  result = (if pulseRom[pulse][floor(invLerp(0.0, TAU, phase) * 8.0).int] == 1: 1.0 else: -1.0)
  phase += (freq * invSampleRate) * TAU
  phase = phase mod TAU

proc process(self: var GBWaveOsc): float32 =
  phase += (freq * invSampleRate) * TAU
  if phase >= TAU:
    phase -= TAU
  result = (waveRam[wave][floor(invLerp(0.0, TAU, phase) * 32.0).int].float / 7.5) - 1.0

proc gbFreqToHz(n: int): float =
  return (4194304/(4*2^3*(2048-n))).float

proc hzToGbFreq(hz: float): int =
  return 2048 - 2^17 div hz.int

type
  GBSynthVoice = object
    note: int
    noteLength: int

    sweepTime: int
    sweepMode: int
    sweepShift: int
    freqShadowRegister: int
    sweepEnabled: bool

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

  GBSynthView = ref object of MachineView

method init*(self: GBSynth) =
  procCall init(Machine(self))

  name = "gb"
  nInputs = 0
  nOutputs = 1
  stereo = true

  gbOsc0.pulse = 2
  gbOsc1.pulse = 1
  gbOsc3.lfsr.init(0xfeed)

  gbOsc2.waveRam[0] = waveRom[0]
  gbOsc2.waveRam[1] = waveRom[1]

  for i in 0..3:
    (proc() =
      let voiceId = i
      self.globalParams.add([
        Parameter(name: $voiceId & ":note", separator: true, deferred: true, kind: Note, min: OffNote, max: 255.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
          var v = self.gbVoices[voiceId].addr
          if newValue == OffNote:
            v.samplesLeft = 0
            v.enabled = false
          else:
            v.note = newValue.int
            case voiceId:
            of 0:
              self.gbOsc0.freq = noteToHz(newValue)
              v.freqShadowRegister = hzToGbFreq(self.gbOsc0.freq)
              v.nextSweepUpdate = (0.0078 * sampleRate.float * v.sweepTime.float).int
              v.sweepEnabled = v.sweepShift > 0 or v.sweepTime > 0
            of 1:
              self.gbOsc1.freq = noteToHz(newValue)
            of 2:
              self.gbOsc2.freq = noteToHz(newValue)
            of 3:
              self.gbOsc3.freq = noteToHz(newValue)
              self.gbOsc3.nextclick = ((1.0 / self.gbOsc3.freq) * sampleRate).int
            else:
              discard

            v.nextEnvUpdate = sampleRate.int div 32
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
          Parameter(name: $voiceId & ":wave", kind: Int, min: 0.0, max: 15.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
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
          v.nextEnvUpdate = sampleRate.int div 32

        if i == 0 and v.sweepTime > 0:
            v.nextSweepUpdate -= 1
            if v.nextSweepUpdate <= 0:
              v.nextSweepUpdate = (0.0078 * sampleRate.float * v.sweepTime.float).int
              if v.sweepEnabled and v.sweepShift > 0:
                var x = v.freqShadowRegister shr v.sweepShift
                if v.sweepMode == 1:
                  x = -x
                let newFreq = v.freqShadowRegister + x
                if newFreq > 2047 or newFreq == 0:
                  v.sweepEnabled = false
                gbOsc0.freq = gbFreqToHz(newFreq)

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

method drawExtraData(self: GBSynth, x,y,w,h: int) =
  var yv = y
  let wave = gbOsc2.waveRam[gbOsc2.wave]
  setColor(1)
  rectfill(x, yv + 4, x + 32 * 4, yv + 64 + 4)
  setColor(6)
  for s in 0..31:
    let amp = wave[s].int
    rectfill(x + s * 4, yv + 64 - amp * 4, x + s * 4 + 3, yv + 64 - amp * 4 + 3)
  yv += 8

proc newGBSynthView(machine: Machine): View =
  var v = new(GBSynthView)
  v.machine = machine
  return v

method getMachineView*(self: GBSynth): View =
  return newGBSynthView(self)

#method event(self: GBSynthView, e: Event): bool =
#  var gb = GBSynth(self.machine)
#  case e.kind:
#  of MouseButtonDown, MouseButtonUp:
#    let mv = intPoint2d(e.button.x, e.button.y)
#    let paramWidth = screenWidth div 3 + paramNameWidth
#    if mv.x > paramWidth:
#      let x = mv.x - paramWidth
#      let s = x div 4
#      if s >= 0 and s < 16:
#        gb.gbOsc2.waveRam[gb.gbOsc2.wave][s] = ((64 - mv.y) div 4).uint8
#      return true
#  of MouseMotion:
#    discard
#  else:
#    discard
#  return procCall event(MachineView(self), e)
#
proc newGBSynth(): Machine =
  var gbs = new(GBSynth)
  gbs.init()
  return gbs

registerMachine("gb", newGBSynth, "generator")

import unittest

suite "gbsynth":
  test "freq":
    check(gbFreqToHz(0) == 64.0)
    check(gbFreqToHz(1024) == 128.0)
    check(gbFreqToHz(2047) == 131072.0)
  test "freq":
    check(hzToGbFreq(64.0) == 0)
    check(hzToGbFreq(128.0) == 1024)
    check(hzToGbFreq(131072.0) == 2047)

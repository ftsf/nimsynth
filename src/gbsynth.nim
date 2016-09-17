import common
import osc
import math

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
  GBSynthVoice = object
    note: int
    osc: Osc
    samplesLeft: int
    noteLength: int
    sweepTime: int
    sweepMode: int
    sweepShift: int
    channels: int
    lfsr: LFSR
    nextclick: int
    envInit: int
    envMode: int
    envChange: int
    nextEnvUpdate: int
    nextSweepUpdate: int
    volume: int
  GBSynth = ref object of Machine
    gbVoices: array[4, GBSynthVoice]

method init*(self: GBSynth) =
  procCall init(Machine(self))

  name = "gb"
  nInputs = 0
  nOutputs = 1
  stereo = false

  gbVoices[0].osc.kind = Sqr
  gbVoices[1].osc.kind = Sqr
  gbVoices[2].osc.kind = Saw
  gbVoices[3].osc.kind = Noise
  gbVoices[3].lfsr.lfsr = 0xfeed

  for i in 0..3:
    (proc() =
      let voiceId = i
      self.globalParams.add([
        Parameter(name: $voiceId & ":note", kind: Note, min: 0.0, max: 255.0, onchange: proc(newValue: float, voice: int) =
          var v = self.gbVoices[voiceId].addr
          if newValue == OffNote:
            v.samplesLeft = 0
          else:
            v.note = newValue.int
            v.osc.freq = noteToHz(newValue)
            v.nextclick = ((1.0 / v.osc.freq) * sampleRate).int
            v.samplesLeft = v.noteLength
            v.nextEnvUpdate = 750
            v.nextSweepUpdate = 375 * v.sweepTime
            v.volume = v.envInit
        , getValueString: proc(value: float, voice: int): string =
          if value == OffNote:
            return "Off"
          else:
            return noteToNoteName(value.int)
        ),
        Parameter(name: $voiceId & ":len", kind: Float, min: 0.0, max: 1.0, default: 0.2, onchange: proc(newValue: float, voice: int) =
          var v = self.gbVoices[voiceId].addr
          v.noteLength = (newValue * sampleRate.float).int
        ),
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
            var v = self.gbVoices[voiceId].addr
            case newValue.int:
            of 0:
              v.osc.pulseWidth = 0.125
            of 1:
              v.osc.pulseWidth = 0.25
            of 2:
              v.osc.pulseWidth = 0.50
            of 3:
              v.osc.pulseWidth = 0.75
            else:
              v.osc.pulseWidth = 0.50
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
  cachedOutputSample = 0.0
  for i in 0..3:
    var v = addr(gbVoices[i])
    if v.samplesLeft > 0:

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
            if v.sweepMode == 0:
              # down
              v.osc.freq = clamp(v.osc.freq * (1.0/(v.sweepShift + 1).float), 0.0, sampleRate / 2.0)
            if v.sweepMode == 1:
              # up
              v.osc.freq = clamp(v.osc.freq * (v.sweepShift + 1).float, 0.0, sampleRate / 2.0)
            v.nextSweepUpdate = 375 * v.sweepTime
      if i == 3:
        v.nextclick -= 1
        if v.nextclick == 0:
          cachedOutputSample += v.lfsr.process() * (v.volume.float / 15.0)
          v.nextclick = ((1.0 / v.osc.freq) * sampleRate).int
        else:
          cachedOutputSample += v.lfsr.output * (v.volume.float / 15.0)
      else:
        cachedOutputSample += v.osc.process() * (v.volume.float / 15.0)
      v.samplesLeft -= 1
  # convert to 4 bit audio
  cachedOutputSample = to4bit(cachedOutputSample)

proc newGBSynth(): Machine =
  var gbs = new(GBSynth)
  gbs.init()
  return gbs

method trigger(self: GBSynth, note: int) =
  gbVoices[0].note = note
  gbVoices[0].osc.freq = noteToHz(note.float)
  gbVoices[0].samplesLeft = gbVoices[0].noteLength

method release(self: GBSynth, note: int) =
  if gbVoices[0].note == note:
    gbVoices[0].samplesLeft = 0

registerMachine("gb", newGBSynth)

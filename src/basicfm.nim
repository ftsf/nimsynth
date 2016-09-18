import common
import math
import util

import osc
import filter
import env
import master

# 3 osc FM synth

const nOperators = 3

# map of source to dest for modulation
# http://www.hitfoundry.com/issue_12/images/F07-algo.JPG

const algorithms = [
  @[ # 1
    (2,1),
    (3,1),

    (1,0),
  ],
  @[ # 2
    (2,1),
    (3,2),

    (1,0),
  ],
  @[ # 3
    (3,2),

    (2,0),
    (1,0),
  ],
  @[ # 4
    (3,2),
    (3,1),

    (2,0),
    (1,0),
  ],
]

type
  BasicFMSynthOperator = object of RootObj
    osc: Osc
    env: Envelope
    output: float32
  BasicFMSynthVoice = ref object of Voice
    pitch: float
    note: int
    operators: array[nOperators, BasicFMSynthOperator]
    pitchEnv: Envelope
    pitchEnvMod: float

  BasicFMSynth = ref object of Machine
    octOffsets: array[nOperators, int]     # adds to the base pitch
    semiOffsets: array[nOperators, int]     # adds to the base pitch
    centOffsets: array[nOperators, int]     # adds to the base pitch
    multipliers: array[nOperators, float] # multiplies the base pitch
    amps: array[nOperators, float]
    fixed: array[nOperators, bool]
    envSettings: array[nOperators, tuple[a,d,s,r: float]]
    algorithm: int # 0..31 which layout of operators to use
    feedback: float

{.this:self.}

method init(self: BasicFMSynthVoice, machine: BasicFMSynth) =
  procCall init(Voice(self), machine)

  for operator in mitems(operators):
    operator.osc.kind = Sin
    operator.env.d = 1.0

method addVoice*(self: BasicFMSynth) =
  pauseAudio(1)
  var voice = new(BasicFMSynthVoice)
  voice.init(self)
  voices.add(voice)
  pauseAudio(0)

proc initNote(self: BasicFMSynth, voiceId: int, note: int) =
  var voice = BasicFMSynthVoice(voices[voiceId])
  if note == OffNote:
    voice.note = note
    voice.pitch = noteToHz(note.float)
    for i in 0..nOperators-1:
      voice.operators[i].env.release()
  else:
    voice.note = note
    voice.pitch = noteToHz(note.float)
    for i in 0..nOperators-1:
      voice.operators[i].env.a = self.envSettings[i].a
      voice.operators[i].env.d = self.envSettings[i].d
      voice.operators[i].env.s = self.envSettings[i].s
      voice.operators[i].env.r = self.envSettings[i].r
      voice.operators[i].env.trigger()

method init(self: BasicFMSynth) =
  procCall init(Machine(self))

  nInputs = 0
  nOutputs = 1
  stereo = false

  for i in 0..multipliers.high:
    multipliers[i] = 1.0

  name = "BASICfm"
  algorithm = 0

  self.globalParams.add([
    Parameter(name: "algoritm", kind: Int, min: 0.0, max: algorithms.high.float, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.algorithm = newValue.int
    , getValueString: proc(value: float, voice: int): string =
      return $(self.algorithm.int + 1)
    ),
    Parameter(name: "feedback", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.feedback = newValue
    ),
  ])


  for i in 0..nOperators-1:
    (proc() =
      let opId = i
      self.globalParams.add([
        Parameter(name: $(opId+1) & ":AMP", kind: Float, min: 0.0, max: 1.0, default: if opId == 0: 1.0 else: 0.0, onchange: proc(newValue: float, voice: int) =
          self.amps[opId] = newValue
        ),
        Parameter(name: $(opId+1) & ":FIXED", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.fixed[opId] = newValue.bool
        ),
        Parameter(name: $(opId+1) & ":OCT", kind: Int, min: -8.0, max: 8.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.octOffsets[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":SEMI", kind: Int, min: -12.0, max: 12.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.semiOffsets[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":CENT", kind: Int, min: -100.0, max: 100.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.centOffsets[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":MULT", kind: Float, min: 0.5, max: 8.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
          self.multipliers[opId] = newValue
        ),
        Parameter(name: $(opId+1) & ":A", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.envSettings[opId].a = newValue
        ),
        Parameter(name: $(opId+1) & ":D", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
          self.envSettings[opId].d = newValue
        ),
        Parameter(name: $(opId+1) & ":S", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.envSettings[opId].s = newValue
        ),
        Parameter(name: $(opId+1) & ":R", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.envSettings[opId].r = newValue
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

method process(self: BasicFMSynth) {.inline.} =
  cachedOutputSample = 0
  for voice in mitems(self.voices):
    var v = BasicFMSynthVoice(voice)
    for i,operator in mpairs(v.operators):
      operator.osc.freq = (if fixed[i]: 440.0 else: v.pitch) * multipliers[i] * pow(2.0, centOffsets[i].float / 1200.0 + semiOffsets[i].float / 12.0 + octOffsets[i].float)
      let opId = i+1
      operator.output = operator.osc.process() * operator.env.process() * amps[i]
      for map in algorithms[algorithm]:
        if map[0] == opId:
          if map[1] == 0:
            cachedOutputSample += operator.output
          else:
            let phaseOffset = operator.output
            v.operators[map[1]-1].osc.phase += (phaseOffset * PI)

method trigger(self: BasicFMSynth, note: int) =
  for i,voice in mpairs(voices):
    var v = BasicFMSynthVoice(voice)
    if v.pitchEnv.state == Release:
      initNote(i, note)
      return

method release(self: BasicFMSynth, note: int) =
  for i,voice in mpairs(voices):
    var v = BasicFMSynthVoice(voice)
    if v.note == note:
      initNote(i, OffNote)

proc newBasicFMSynth(): Machine =
  var fm = new(BasicFMSynth)
  fm.init()
  return fm

registerMachine("BASICfm", newBasicFMSynth)

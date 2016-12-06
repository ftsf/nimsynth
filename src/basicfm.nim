import common
import math
import util

import osc
import filter
import env
import master

import strutils

import locks

# 3 osc FM synth

const nOperators = 3

# map of source to dest for modulation
# http://www.hitfoundry.com/issue_12/images/F07-algo.JPG

const algorithms = [
  @[ # 1
    (2,1),
    (3,1),
    (3,3),

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
    velocity: float
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
    pitchEnvSettings: tuple[a,d,s,r: float]
    pitchEnvMod: float
    algorithm: int # 0..31 which layout of operators to use
    feedback: float

{.this:self.}

method init(self: BasicFMSynthVoice, machine: BasicFMSynth) =
  procCall init(Voice(self), machine)

  for operator in mitems(operators):
    operator.osc.kind = Sin
    operator.env.init()
    operator.env.d = 1.0

  pitchEnv.init()

method addVoice*(self: BasicFMSynth) =
  withLock machineLock:
    pauseAudio(1)
    var voice = new(BasicFMSynthVoice)
    voices.add(voice)
    voice.init(self)
    pauseAudio(0)

proc initNote(self: BasicFMSynth, voiceId: int, note: int) =
  var voice = BasicFMSynthVoice(voices[voiceId])
  if note == OffNote:
    voice.note = note
    voice.pitchEnv.release()
    for i in 0..nOperators-1:
      voice.operators[i].env.release()
  else:
    voice.note = note
    voice.pitch = noteToHz(note.float)
    voice.pitchEnv.a = self.pitchEnvSettings.a
    voice.pitchEnv.d = self.pitchEnvSettings.d
    voice.pitchEnv.s = self.pitchEnvSettings.s
    voice.pitchEnv.r = self.pitchEnvSettings.r
    voice.pitchEnv.trigger()
    for i in 0..nOperators-1:
      voice.operators[i].env.a = self.envSettings[i].a
      voice.operators[i].env.d = self.envSettings[i].d
      voice.operators[i].env.s = self.envSettings[i].s
      voice.operators[i].env.r = self.envSettings[i].r
      voice.operators[i].env.trigger(voice.velocity)

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
    Parameter(name: "feedback", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.feedback = newValue
    ),
    Parameter(name: "pmod", kind: Float, min: -24.0, max: 24.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.pitchEnvMod = newValue
    ),
    Parameter(name: "pmod:a", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.pitchEnvSettings.a = newValue
    ),
    Parameter(name: "pmod:d", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.pitchEnvSettings.d = newValue
    ),
    Parameter(name: "pmod:s", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.pitchEnvSettings.s = newValue
    ),
    Parameter(name: "pmod:r", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.pitchEnvSettings.r = newValue
    ),
  ])


  for i in 0..nOperators-1:
    (proc() =
      let opId = i
      self.globalParams.add([
        Parameter(name: $(opId+1) & ":AMP", separator: true, kind: Float, min: 0.0, max: 1.0, default: if opId == 0: 1.0 else: 0.0, onchange: proc(newValue: float, voice: int) =
          self.amps[opId] = newValue
        ),
        Parameter(name: $(opId+1) & ":FIXED", kind: Bool, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
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
        Parameter(name: $(opId+1) & ":A", kind: Float, min: 0.0, max: 5.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.envSettings[opId].a = exp(newValue) - 1.0
        , getValueString: proc(value: float, voice: int): string =
          return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
        ),
        Parameter(name: $(opId+1) & ":D", kind: Float, min: 0.0, max: 5.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
          self.envSettings[opId].d = exp(newValue) - 1.0
        , getValueString: proc(value: float, voice: int): string =
          return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
        ),
        Parameter(name: $(opId+1) & ":S", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.envSettings[opId].s = newValue
        ),
        Parameter(name: $(opId+1) & ":R", kind: Float, min: 0.0, max: 5.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.envSettings[opId].r = exp(newValue) - 1.0
        , getValueString: proc(value: float, voice: int): string =
          return (exp(value) - 1.0).formatFloat(ffDecimal, 2) & " s"
        ),
      ])
    )()

  self.voiceParams.add([
    Parameter(name: "note", kind: Note, separator: true, deferred: true, min: OffNote, max: 255.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      self.initNote(voice, newValue.int)
    ),
    Parameter(name: "vel", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      var v = BasicFMSynthVoice(self.voices[voice])
      v.velocity = newValue
    ),
  ])

  setDefaults()

  addVoice()

method process(self: BasicFMSynth) {.inline.} =
  outputSamples[0] = 0
  for voice in mitems(self.voices):
    var v = BasicFMSynthVoice(voice)
    let pitchMod = pow(2.0, (v.pitchEnv.process() * pitchEnvMod) / 12.0)
    for i,operator in mpairs(v.operators):
      operator.osc.freq = (if fixed[i]: 440.0 else: v.pitch * pitchMod) * multipliers[i] * pow(2.0, centOffsets[i].float / 1200.0 + semiOffsets[i].float / 12.0 + octOffsets[i].float)
      let opId = i+1
      operator.output = operator.osc.process() * operator.env.process() * amps[i]
      for map in algorithms[algorithm]:
        if map[0] == opId:
          if map[1] == 0:
            outputSamples[0] += operator.output
          else:
            let phaseOffset = if map[1] == map[0]: operator.output * feedback else: operator.output
            v.operators[map[1]-1].osc.phase += phaseOffset

proc newBasicFMSynth(): Machine =
  var fm = new(BasicFMSynth)
  fm.init()
  return fm

import pico

method drawExtraData(self: BasicFMSynth, x,y,w,h: int) =
  # draw algorithm layout
  let algorithm = algorithms[algorithm]

  const rectSize = 13
  const padding = 8
  var carrier = 0
  var modulator = 0
  var modDepth = 0

  var ops = newSeq[tuple[id: int, x,y: int, targets: seq[int]]]()
  # find carriers
  var y = y + 32
  var x = x + padding
  for map in algorithm:
    if map[1] == 0:
      ops.add((id: map[0], x: x + carrier * (rectSize + padding), y: y, targets: nil))
      carrier += 1
    # find modulators
    for map2 in algorithm:
      if map2[1] == map[0]:
        var thisOp: ptr tuple[id: int, x,y: int, targets: seq[int]]
        for op in mitems(ops):
          if op.id == map2[0]:
            thisOp = op.addr
            break
        if thisOp == nil:
          ops.add((id: map2[0], x: x + modulator * (rectSize + padding), y: y - (rectSize + padding), targets: newSeq[int]()))
          thisOp = ops[ops.high].addr
          modulator += 1
        thisOp.targets.add(map2[1])

  # draw lines
  for op in ops:
    if op.targets != nil:
      for target in op.targets:
        if target == op.id:
          # feedback
          pico.rect(op.x - rectSize div 3, op.y - rectSize div 3, op.x + rectSize div 2, op.y + rectSize div 2)
        else:
          for op2 in ops:
            if op2.id == target:
              line(op.x + rectSize div 2, op.y + rectSize div 2, op2.x + rectSize div 2, op2.y + rectSize div 2)
              break

  # draw boxes
  for op in ops:
    setColor(0)
    rectfill(op.x, op.y, op.x + rectSize, op.y + rectSize)
    setColor(7)
    pico.rect(op.x, op.y, op.x + rectSize, op.y + rectSize)
    printc($op.id, op.x + 6, op.y + 6)




registerMachine("BASICfm", newBasicFMSynth, "generator")

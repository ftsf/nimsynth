import math

import common
import util

import nico
import nico/vec

import core/oscillator
import core/filter
import core/envelope

import machines/master


# 6 osc FM synth

const nOperators = 6

# map of source to dest for modulation
# http://www.hitfoundry.com/issue_12/images/F07-algo.JPG

const algorithms = [
  @[ # 1
    (3,2),
    (6,4),
    (6,5),
    (6,6),

    (1,0),
    (2,0),
    (4,0),
    (5,0)
  ],
  @[ # 2
    (3,1),
    (6,2),
    (6,4),
    (6,5),
    (6,6),

    (1,0),
    (2,0),
    (4,0),
    (5,0),
  ],
  @[ # 3
    (3,3),
    (3,1),
    (3,2),
    (6,4),
    (6,5),

    (1,0),
    (2,0),
    (4,0),
    (5,0),
  ],
  @[ # 4
    (4,3),
    (5,3),
    (6,6),
    (6,3),
    (2,1),

    (3,0),
    (1,0),
  ],
  @[ # 5
    (4,3),
    (5,3),
    (6,3),
    (2,2),
    (2,1),

    (3,0),
    (1,0),
  ],
  @[ # 6
    (2,1),
    (3,3),
    (3,1),
    (6,5),
    (5,4),
    (4,1),

    (1,0),
  ],
  @[ # 7
    (2,1),
    (4,3),
    (3,1),
    (6,6),
    (6,5),
    (6,1),

    (1,0),
  ],
  @[ # 8
    (2,2),
    (2,1),
    (4,3),
    (3,1),
    (6,5),
    (5,1),

    (1,0),
  ],
  @[ # 9
    (5,4),
    (6,6),
    (6,4),
    (3,2),
    (2,1),

    (4,0),
    (1,0),
  ],
  @[ # 10
    (5,4),
    (6,4),
    (3,3),
    (3,2),
    (2,1),

    (4,0),
    (1,0),
  ],
  @[ # 11
    (2,2),
    (2,1),
    (4,3),
    (6,5),
    (5,3),

    (3,0),
    (1,0),
  ],
  @[ # 12
    (2,1),
    (4,4),
    (4,3),
    (6,5),
    (5,3),

    (3,0),
    (1,0),
  ],
  @[ # 13
    (2,1),
    (4,3),
    (6,6),
    (6,5),
    (5,3),

    (3,0),
    (1,0),
  ],
  @[ # 14
    (3,3),
    (3,1),
    (3,2),
    (5,2),
    (6,4),

    (1,0),
    (2,0),
    (4,0),
  ],
  @[ # 15
    (2,1),
    (4,3),
    (6,5),
    (5,6),

    (1,0),
    (3,0),
    (5,0),
  ],
  @[ # 16
    (2,1),
    (4,3),
    (6,6),
    (6,5),

    (1,0),
    (3,0),
    (5,0),
  ],
  @[ # 17
    (5,4),
    (6,4),
    (4,3),
    (2,2),
    (2,1),

    (1,0),
    (3,0),
  ],
  @[ # 18
    (5,4),
    (6,6),
    (6,4),
    (4,3),
    (2,1),

    (1,0),
    (3,0),
  ],
  @[ # 19
    (3,2),
    (2,1),
    (6,5),
    (5,4),
    (4,6),

    (1,0),
    (4,0),
  ],
  @[ # 20
    (3,2),
    (2,1),
    (6,6),
    (6,5),
    (5,4),

    (1,0),
    (4,0),
  ],
  @[ # 21
    (2,2),
    (2,1),
    (6,5),
    (5,4),
    (4,3),

    (1,0),
    (3,0),
  ],
  @[ # 22
    (2,1),
    (6,6),
    (6,5),
    (5,4),
    (4,3),

    (1,0),
    (3,0),
  ],
  @[ # 23
    (6,6),

    (1,0),
    (2,0),
    (3,0),
    (4,0),
    (5,0),
    (6,0),
  ],
  @[ # 24
    (3,2),
    (2,1),
    (6,4),
    (6,5),

    (1,0),
    (4,0),
    (5,0),
  ],
  @[ # 25
    (2,1),
    (5,5),
    (5,4),
    (4,3),

    (1,0),
    (3,0),
    (6,0),
  ],
  @[ # 26
    (5,5),
    (5,4),
    (4,3),

    (1,0),
    (2,0),
    (3,0),
    (6,0),
  ],
  @[ # 27
    (6,6),
    (6,5),
    (4,3),

    (1,0),
    (2,0),
    (3,0),
    (5,0),
    (6,0),
  ],
  @[ # 28
    (6,6),
    (6,5),

    (1,0),
    (2,0),
    (3,0),
    (4,0),
    (5,0),
  ],
  @[ # 29
    (2,1),
    (5,5),
    (5,4),
    (4,3),

    (1,0),
    (3,0),
    (6,0),
  ],
  @[ # 30
    (6,6),
    (6,3),
    (6,4),
    (6,5),

    (1,0),
    (2,0),
    (3,0),
    (4,0),
    (5,0),
  ],
  @[ # 31
    (3,3),
    (3,2),
    (5,4),
    (6,4),

    (1,0),
    (2,0),
    (4,0),
  ],
  @[ # 32
    (3,2),
    (5,4),
    (6,6),
    (6,4),

    (1,0),
    (2,0),
    (4,0),
  ],
]

type
  FMSynthOperator = object
    osc: Osc
    env: Envelope
    output: float32
  FMSynthVoice = ref object of Voice
    pitch: float32
    note: int
    velocity: float32
    operators: array[nOperators, FMSynthOperator]
    pitchEnv: Envelope
    pitchEnvMod: float32

  FMSynth = ref object of Machine
    octOffsets: array[nOperators, int]     # adds to the base pitch
    semiOffsets: array[nOperators, int]     # adds to the base pitch
    centOffsets: array[nOperators, int]     # adds to the base pitch
    multipliers: array[nOperators, float32] # multiplies the base pitch
    amps: array[nOperators, float32]
    fixed: array[nOperators, bool]
    envSettings: array[nOperators, EnvelopeSettings]
    algorithm: int # 0..31 which layout of operators to use
    feedback: float32

{.this:self.}

method init(self: FMSynthVoice, machine: FMSynth) =
  procCall init(Voice(self), machine)

  for operator in mitems(operators):
    operator.osc.kind = Sin
    operator.osc.init()
    operator.env.d = 1.0

method addVoice*(self: FMSynth) =
  var voice = new(FMSynthVoice)
  voices.add(voice)
  voice.init(self)

proc initNote(self: FMSynth, voiceId: int, note: int) =
  var voice = FMSynthVoice(voices[voiceId])
  if note == OffNote:
    voice.note = note
    for i in 0..nOperators-1:
      voice.operators[i].env.release()
  else:
    voice.note = note
    voice.pitch = noteToHz(note.float32)
    for i in 0..nOperators-1:
      voice.operators[i].env.a = self.envSettings[i].a
      voice.operators[i].env.d = self.envSettings[i].d
      voice.operators[i].env.s = self.envSettings[i].s
      voice.operators[i].env.r = self.envSettings[i].r
      voice.operators[i].env.trigger()

method init(self: FMSynth) =
  procCall init(Machine(self))

  nInputs = 0
  nOutputs = 1
  stereo = false

  for i in 0..multipliers.high:
    multipliers[i] = 1.0

  name = "fmSYNTH"

  self.globalParams.add([
    Parameter(name: "algoritm", kind: Int, min: 0.0, max: algorithms.high.float32, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.algorithm = newValue.int
    , getValueString: proc(value: float32, voice: int): string =
      return $(self.algorithm.int + 1)
    ),
    Parameter(name: "feedback", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.feedback = newValue
    ),
  ])

  for i in 0..nOperators-1:
    (proc() =
      let opId = i
      self.globalParams.add([
        Parameter(name: $(opId+1) & ":AMP", kind: Float, min: 0.0, max: 1.0, default: if opId == 0: 1.0 else: 0.0, separator: true, onchange: proc(newValue: float32, voice: int) =
          self.amps[opId] = newValue
        ),
        Parameter(name: $(opId+1) & ":FIXED", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
          self.fixed[opId] = newValue.bool
        ),
        Parameter(name: $(opId+1) & ":OCT", kind: Int, min: -8.0, max: 8.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
          self.octOffsets[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":SEMI", kind: Int, min: -12.0, max: 12.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
          self.semiOffsets[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":CENT", kind: Int, min: -100.0, max: 100.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
          self.centOffsets[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":MULT", kind: Float, min: 0.5, max: 8.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
          self.multipliers[opId] = newValue
        ),
        Parameter(name: $(opId+1) & ":A", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
          self.envSettings[opId].a = newValue
        ),
        Parameter(name: $(opId+1) & ":D", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float32, voice: int) =
          self.envSettings[opId].d = newValue
        ),
        Parameter(name: $(opId+1) & ":S", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
          self.envSettings[opId].s = newValue
        ),
        Parameter(name: $(opId+1) & ":R", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
          self.envSettings[opId].r = newValue
        ),
      ])
    )()

  self.voiceParams.add([
    Parameter(name: "note", kind: Note, min: 0.0, max: 255.0, default: OffNote, separator: true, onchange: proc(newValue: float32, voice: int) =
      self.initNote(voice, newValue.int)
    , getValueString: proc(value: float32, voice: int): string =
      if value == OffNote:
        return "Off"
      else:
        return noteToNoteName(value.int)
    ),
    Parameter(name: "vel", kind: Float, min: 0.0, max: 1.0, seqkind: skInt8, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      var voice = FMSynthVoice(self.voices[voice])
      voice.velocity = newValue
    ),
  ])

  setDefaults()

  addVoice()

method process(self: FMSynth) {.inline.} =
  outputSamples[0] = 0
  for voice in mitems(self.voices):
    var v = FMSynthVoice(voice)
    for i,operator in mpairs(v.operators):
      operator.osc.freq = (if fixed[i]: 440.0 else: v.pitch) * multipliers[i] * pow(2.0, centOffsets[i].float32 / 1200.0 + semiOffsets[i].float32 / 12.0 + octOffsets[i].float32)
      let opId = i+1
      operator.output = operator.osc.process() * operator.env.process() * amps[i]
      for map in algorithms[algorithm]:
        if map[0] == opId:
          if map[1] == 0:
            outputSamples[0] += operator.output
          else:
            let phaseOffset = if map[1] == map[0]: operator.output * feedback else: operator.output
            v.operators[map[1]-1].osc.phase += phaseOffset
      outputSamples[0] *= v.velocity

method trigger*(self: FMSynth, note: int) =
  for i,voice in mpairs(voices):
    var v = FMSynthVoice(voice)
    if v.pitchEnv.state == Release:
      initNote(i, note)
      return

method release*(self: FMSynth, note: int) =
  for i,voice in mpairs(voices):
    var v = FMSynthVoice(voice)
    if v.note == note:
      initNote(i, OffNote)

method drawExtraData(self: FMSynth, x,y,w,h: int) =
  let s = self
  # draw algorithm layout
  let algorithm = algorithms[s.algorithm]

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
      ops.add((id: map[0], x: x + carrier * (rectSize + padding), y: y, targets: @[]))
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
    for target in op.targets:
      if target == op.id:
        # feedback
        setColor(if s.amps[op.id-1] > 0 and s.feedback > 0: 7 else: 1)
        nico.rect(op.x - rectSize div 3, op.y - rectSize div 3, op.x + rectSize div 2, op.y + rectSize div 2)
      else:
        setColor(if s.amps[op.id-1] > 0: 7 else: 1)
        for op2 in ops:
          if op2.id == target:
            line(op.x + rectSize div 2, op.y + rectSize div 2, op2.x + rectSize div 2, op2.y + rectSize div 2)
            break

  # draw boxes
  for op in ops:
    setColor(0)
    rectfill(op.x, op.y, op.x + rectSize, op.y + rectSize)
    setColor(if s.amps[op.id-1] > 0: 7 else: 1)
    nico.rect(op.x, op.y, op.x + rectSize, op.y + rectSize)
    setColor(if s.amps[op.id-1] > 0: 7 else: 1)

    setColor(7)
    printc($op.id, op.x + 6, op.y + 6)

  y += 64

  # draw envelopes
  #drawEnvs(s.envSettings, x,y,w,48)


proc newFMSynth(): Machine =
  var fm = new(FMSynth)
  fm.init()
  return fm

registerMachine("fmsynth", newFMSynth, "generator")

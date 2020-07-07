import common

import util
import nico
import math

# http://www.smspower.org/maxim/Documents/YM2612
# https://github.com/ekeeke/Genesis-Plus-GX/blob/ae28f874021d92f0abd37113a56dcec89b570777/core/sound/ym2612.c

# not implementing digital audio channel
# one sine LFO
# 4 operators per voice
# 8 algorithms
#   0 = 1->2->3->4            # Distorted Guitar
#   1 = (1,2)->3->4           # Harp, PSG
#   2 = (1,(2->3))->4         # Bass, Electric Guitar, Brass, Piano, Woods
#   3 = ((1->2),3)->4          # Strings, Folk Guitar, Chimes
#   4 = (1->2),(3->4)         # Flute, Bells, Chorus
#   5 = (1->2),(1->3),(1->4)  # Brass, Organ
#   6 = (1->2),3,4            # Xylophone, Vibes
#   7 = 1,2,3,4               # Pipe Organ

{.this:self.}

const algorithms = [ # 0 = master
  @[ # 0
    (1,1),
    (1,2),
    (2,3),
    (3,4),
    (4,0),
  ],
  @[ # 1
    (1,1),
    (1,3),
    (2,3),
    (3,4),
    (4,0),
  ],
  @[ # 2
    (1,1),
    (1,4),
    (2,3),
    (3,4),
    (4,0),
  ],
  @[ # 3
    (1,1),
    (1,2),
    (2,4),
    (3,4),
    (4,0),
  ],
  @[ # 4
    (1,1),
    (1,2),
    (3,4),
    (2,0),
    (4,0),
  ],
  @[ # 5
    (1,1),
    (1,2),
    (1,3),
    (1,4),
    (2,0),
    (3,0),
    (4,0),
  ],
  @[ # 6
    (1,1),
    (1,2),
    (2,0),
    (3,0),
    (4,0),
  ],
  @[ # 7
    (1,1),
    (1,0),
    (2,0),
    (3,0),
    (4,0),
  ],
]

let lfoFrequencies = [
  3.98,
  5.56,
  6.02,
  6.37,
  6.88,
  9.63,
  41.1,
  72.2,
]

let AMSAmount = [
  1.0,
  1.0/1.174,
  1.0/1.972,
  1.0/(1.972 + 1.174),
  1.0/3.890,
  1.0/(3.890 + 1.174),
  1.0/(3.890 + 1.972),
  1.0/(3.890 + 1.972 + 1.174),
]

let envBits = 10
let envLen = 1 shl envBits
let envStep = 128.0 / envLen.float32

let maxAttenuationIndex = envLen-1
let minAttenuationIndex = 0

const epsilon = 0.0001'f

let egInc = [
  0,1, 0,1, 0,1, 0,1,
  0,1, 0,1, 1,1, 0,1,
  0,1, 1,1, 0,1, 1,1,
  0,1, 1,1, 1,1, 1,1,

  1,1, 1,1, 1,1, 1,1,
  1,1, 1,2, 1,1, 1,2,
  1,2, 1,2, 1,2, 1,2,
  1,2, 2,2, 1,2, 2,2,

  2,2, 2,2, 2,2, 2,2,
  2,2, 2,4, 2,2, 2,4,
  2,4, 2,4, 2,4, 2,4,
  2,4, 4,4, 2,4, 4,4,

  4,4, 4,4, 4,4, 4,4,
  4,4, 4,8, 4,4, 4,8,
  4,8, 4,8, 4,8, 4,8,
  4,8, 8,8, 4,8, 8,8,

  8,8, 8,8, 8,8, 8,8,
  16,16, 16,16, 16,16, 16,16,
  0,0, 0,0, 0,0, 0,0,
]

const rateSteps = 8

proc O(a: int): int =
  a * rateSteps

let egRateSelect = [
  O(18),O(18),O(18),O(18), O(18),O(18),O(18),O(18),
  O(18),O(18),O(18),O(18), O(18),O(18),O(18),O(18),
  O(18),O(18),O(18),O(18), O(18),O(18),O(18),O(18),
  O(18),O(18),O(18),O(18), O(18),O(18),O(18),O(18),

  O(18),O(18),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),
  O( 0),O( 1),O( 2),O( 3),

  O( 4),O( 5),O( 6),O( 7),

  O( 8),O( 9),O(10),O(11),

  O(12),O(13),O(14),O(15),

  O(16),O(16),O(16),O(16),

  O(16),O(16),O(16),O(16),O(16),O(16),O(16),O(16),
  O(16),O(16),O(16),O(16),O(16),O(16),O(16),O(16),
  O(16),O(16),O(16),O(16),O(16),O(16),O(16),O(16),
  O(16),O(16),O(16),O(16),O(16),O(16),O(16),O(16)
]

let egRateShift = [
  11,11,11,11,11,11,11,11,
  11,11,11,11,11,11,11,11,
  11,11,11,11,11,11,11,11,
  11,11,11,11,11,11,11,11,

  11,11,11,11,
  10,10,10,10,
   9, 9, 9, 9,
   8, 8, 8, 8,
   7, 7, 7, 7,
   6, 6, 6, 6,
   5, 5, 5, 5,
   4, 4, 4, 4,
   3, 3, 3, 3,
   2, 2, 2, 2,
   1, 1, 1, 1,
   0, 0, 0, 0,

   0, 0, 0, 0,

   0, 0, 0, 0,

   0, 0, 0, 0,

   0, 0, 0, 0,

   0, 0, 0, 0, 0, 0, 0, 0,
   0, 0, 0, 0, 0, 0, 0, 0,
   0, 0, 0, 0, 0, 0, 0, 0,
   0, 0, 0, 0, 0, 0, 0, 0
]

const ENV_BITS = 10
const ENV_LEN = 1 shl ENV_BITS
const ENV_STEP = 128'f / ENV_LEN.float32

const MAX_ATT_INDEX = ENV_LEN-1
const MIN_ATT_INDEX = 0

const DT_BITS = 17
const DT_LEN = 1 shl DT_BITS
const DT_MASK = DT_LEN - 1

const SIN_BITS = 10
const SIN_LEN = 1 shl SIN_BITS
const SIN_MASK = SIN_LEN - 1

const TL_RES_LEN = 256
const TL_BITS = 14

const TL_TAB_LEN = 13 * 2 * TL_RES_LEN

var tlTab: array[TL_TAB_LEN, int32]

for x in 0..<TL_RES_LEN:
  var m = floor((1 shl 16).float32 / pow(2'f, (x.float32+1'f) * (ENV_STEP/4'f) / 8'f))

  var n = m.int
  n = n shr 4
  if (n and 1) != 0:
    n = (n shr 1) + 1
  else:
    n = n shr 1
  n = n shl 2

  tlTab[x*2+0] = n
  tlTab[x*2+1] = -n

  for i in 0..<13:
    tlTab[x*2+0 + i*2*TL_RES_LEN] = n shr i
    tlTab[x*2+1 + i*2*TL_RES_LEN] = -(n shr i)

const ENV_QUIET = TL_TAB_LEN shr 3

var sinTable: array[SIN_LEN, int32]

for i in 0..<SIN_LEN:
  var m = sin( ((i*2)+1) * PI / SIN_LEN)

  var o: float32
  if m > 0'f:
    o = 8*ln(1'f/m)/ln(2'f)
  else:
    o = 8*ln(-1'f/m)/ln(2'f)
  o = o / (ENV_STEP/4'f)

  var n = (2'f * o).int
  if (n and 1) != 0:
    n = (n shr 1)+1
  else:
    n = n shr 1

  sinTable[i] = n*2 + (if m > 0'f: 0 else: 1)


type
  YM2612EnvelopeState = enum
    egOff
    egRelease
    egSustain
    egDecay
    egAttack

  YM2612Operator = object
    output: float32
    state: YM2612EnvelopeState
    volEnv: int
    volOut: int
    egShiftAR, egSelectAR: int
    egShiftDR, egSelectDR: int
    egShiftSR, egSelectSR: int
    egShiftRR, egSelectRR: int
    phase: uint32
    incr: int32

  YM2612Voice = ref object of Voice
    fc: int32
    kcode: int32
    operators: array[4, YM2612Operator] # aka SLOT

  YM2612Synth = ref object of Machine
    algorithm: int
    feedback: int

    TL: array[4, int] # total level
    RS: array[4, int] # attack rate
    AR: array[4, int] # attack rate
    AM: array[4, bool] # amp modulation toggle
    DR: array[4, int] # decay rate
    SL: array[4, int] # sustain level
    SR: array[4, int] # sustain rate
    RR: array[4, int] # release rate
    MUL: array[4, int] # frequency multiplier
    DT: array[4, int]
    AMS: int
    FMS: int
    egCounter: int
    egTimer: int

method init(self: YM2612Voice, machine: YM2612Synth) =
  procCall init(Voice(self), machine)

  for operator in mitems(operators):
    operator.volEnv = 0
    operator.volOut = 0
    operator.state = egOff

method addVoice*(self: YM2612Synth) =
  var voice = new(YM2612Voice)
  voices.add(voice)
  voice.init(self)

proc refreshEg(self: YM2612Synth, voice: int, opId: int) =
  let kc = 0
  var v = (YM2612Voice)(self.voices[voice])
  v.operators[opId].egShiftAR = egRateShift[self.AR[opId] + kc]
  v.operators[opId].egSelectAR = egRateSelect[self.AR[opId] + kc]

  v.operators[opId].egShiftDR = egRateShift[self.DR[opId] + kc]
  v.operators[opId].egSelectDR = egRateSelect[self.DR[opId] + kc]

  v.operators[opId].egShiftSR = egRateShift[self.SR[opId] + kc]
  v.operators[opId].egSelectSR = egRateSelect[self.SR[opId] + kc]

  v.operators[opId].egShiftRR = egRateShift[self.RR[opId] + kc]
  v.operators[opId].egSelectRR = egRateSelect[self.RR[opId] + kc]



proc initNote(self: YM2612Synth, voiceId: int, note: int) =
  var voice = YM2612Voice(voices[voiceId])
  if note == OffNote:
    voice.note = note
  else:
    voice.note = note
    voice.pitch = noteToHz(note.float)
    for i in 0..<4:

      var rate = self.AR[i]
      if rate != 0:
        # TODO: rate scaling
        discard

      if rate >= 62:
        voice.operators[i].state = egDecay
        voice.operators[i].volEnv = 0
      else:
        voice.operators[i].state = egAttack

      voice.operators[i].volOut = voice.operators[i].volEnv + self.TL[i]
      self.refreshEg(voiceId, i)

method init(self: YM2612Synth) =
  procCall init(Machine(self))

  nInputs = 0
  nOutputs = 1
  stereo = false

  for i in 0..MUL.high:
    MUL[i] = 1

  for i in 0..TL.high:
    TL[i] = 1023

  name = "YM2612"

  self.globalParams.add([
    Parameter(name: "algoritm", kind: Int, min: 0.0, max: algorithms.high.float, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.algorithm = newValue.int
    , getValueString: proc(value: float, voice: int): string =
      return $(self.algorithm.int)
    ),
    Parameter(name: "feedback", kind: Int, min: 0.0, max: 7.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.feedback = newValue.int
    ),
    Parameter(name: "LFO freq", kind: Int, min: 0.0, max: 7.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.lfo.freq = lfoFrequencies[newValue.int]
    ),
    Parameter(name: "AMS", kind: Int, min: 0, max: 7.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.AMS = newValue.int
    ),
    Parameter(name: "FMS", kind: Int, min: 0, max: 255.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.FMS = newValue.int
    ),
  ])

  for i in 0..<4:
    (proc() =
      let opId = i
      self.globalParams.add([
        Parameter(name: $(opId+1) & ":TL level", kind: Int, min: 0.0, max: 127.0, default: if opId == 3: 127.0 else: 0.0, separator: true, onchange: proc(newValue: float, voice: int) =
          self.TL[opId] = clamp(127 - newValue.int, 0, 127)
        ),
        Parameter(name: $(opId+1) & ":MUL multiple", kind: Int, min: 0.0, max: 15.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
          self.MUL[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":DT detune", kind: Int, min: 0.0, max: 7.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.DT[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":RS rate scaling", kind: Int, min: 0.0, max: 3.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.RS[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":AM amp mod", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          # whether or not the LFO modulates amplitude
          self.AM[opId] = newValue.bool
        ),
        Parameter(name: $(opId+1) & ":AR attack", kind: Int, min: 0.0, max: 31.0, default: 10.0, onchange: proc(newValue: float, voice: int) =
          self.AR[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":DR decay1", kind: Int, min: 0.0, max: 31.0, default: 10.0, onchange: proc(newValue: float, voice: int) =
          self.DR[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":SL sustain", kind: Int, min: 0.0, max: 15.0, default: 7.0, onchange: proc(newValue: float, voice: int) =
          self.SL[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":SR decay2", kind: Int, min: 0.0, max: 31.0, default: 10.0, onchange: proc(newValue: float, voice: int) =
          self.SR[opId] = newValue.int
        ),
        Parameter(name: $(opId+1) & ":RR release", kind: Int, min: 0.0, max: 15.0, default: 7.0, onchange: proc(newValue: float, voice: int) =
          self.RR[opId] = newValue.int
        ),
      ])
    )()

  self.voiceParams.add([
    Parameter(name: "note", kind: Note, min: 0.0, max: 255.0, default: OffNote, separator: true, onchange: proc(newValue: float, voice: int) =
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

proc updateEg(self: YM2612Synth) =
  for v in voices:
    let voice = (YM2612Voice)v
    # note volume is inverted, 0 = max volume
    for i,op in mpairs(voice.operators):
      case op.state:
      of egAttack:
        let rate = self.AR[i]
        # increase volume
        if (not (egCounter and ((1 shl op.egShiftAR)-1))) != 0:
          op.volEnv += ((not op.volEnv) * (egInc[op.egSelectAR + ((egCounter shr op.egShiftAR) and 7)])) shr 4

          if op.volEnv <= MIN_ATT_INDEX:
            op.volEnv = MIN_ATT_INDEX
            op.state = if self.SL[i] == MIN_ATT_INDEX: egSustain else: egDecay

          op.volOut = op.volEnv + self.TL[i]

      of egDecay:
        if ((egCounter and ((1 shl op.egShiftDR)-1))) == 0:
          op.volEnv += egInc[op.egSelectDR + ((egCounter shr op.egShiftDR) and 7)]
          op.volOut = op.volEnv + self.TL[i]

          if op.volEnv >= self.SL[i]:
            op.state = egSustain

      of egSustain:
        if (not (egCounter and ((1 shl op.egShiftSR)-1))) != 0:
          op.volEnv += egInc[op.egSelectSR + ((egCounter shr op.egShiftSR) and 7)]
          if op.volEnv >= 1023:
            op.volEnv = 1023

          op.volOut = op.volEnv + self.TL[i]

      of egRelease:
        if (not (egCounter and ((1 shl op.egShiftRR)-1))) != 0:
          op.volEnv += egInc[op.egSelectRR + ((egCounter shr op.egShiftRR) and 7)]

          if op.volEnv >= 1023:
            op.volEnv = 1023
            op.state = egOff

          op.volOut = op.volEnv + self.TL[i]

      of egOff:
        discard

      if i == 3 and op.state != egOff:
        echo "op", i, " state: ", op.state, " volume: ", op.volEnv

func detune(freqIn: float32, mul: int, dt: int): float32 =
  result = freqIn
  if mul == 0:
    result *= 0.5'f
  else:
    result *= mul.float32

  if (dt and 0b0100) != 0:
    # negative
    if dt == 0b101:
      result *= (1'f - epsilon)
    elif dt == 0b110:
      result *= (1'f - 2'f * epsilon)
    elif dt == 0b111:
      result *= (1'f - 3'f * epsilon)
  else:
    if dt == 0b001:
      result *= (1'f + epsilon)
    elif dt == 0b010:
      result *= (1'f + 2'f * epsilon)
    elif dt == 0b011:
      result *= (1'f + 3'f * epsilon)

proc opCalc(phase: uint32, env: uint32, pm: uint32, opMask: uint32): int32 =
  let p = (env shl 3) + sinTable[ ( (phase shr SIN_BITS) + (pm shr 1) ) and SIN_MASK]
  if p >= TL_TAB_LEN:
    return 0
  return (tlTab[p] and opMask)

proc opCalc1(phase: uint32, env: uint32, pm: uint32, opMask: uint32): int32 =
  let p = (env shl 3) + sinTable[ ( (phase shr SIN_BITS) + pm ) and SIN_MASK]
  if p >= TL_TAB_LEN:
    return 0
  return (tlTab[p] and opMask)

proc updatePhaseIncrementAndEnvelope(self: YM2612Synth) =
  for i in 0..<4:
    let fc = self.

method process(self: YM2612Synth) {.inline.} =
  outputSamples[0] = 0

  updatePhaseIncrementAndEnvelope()

  chanCalc()

  advanceLfo()

  # envelope is updated every 3 samples
  self.egTimer += 1
  if self.egTimer >= 3:
    self.egTimer = 0
    self.egCounter += 1
    if self.egCounter == 4096:
      self.egCounter = 1
    self.updateEg()

  # 14 bit output to float32


method trigger(self: YM2612Synth, note: int) =
  for i,voice in mpairs(voices):
    var v = YM2612Voice(voice)
    if v.note == OffNote:
      initNote(i, note)
      return

method release(self: YM2612Synth, note: int) =
  for i,voice in mpairs(voices):
    var v = YM2612Voice(voice)
    if v.note == note:
      initNote(i, OffNote)

method drawExtraData(self: YM2612Synth, x,y,w,h: int) =
  discard

  #let algorithm = algorithms[self.algorithm]

  #const rectSize = 13
  #const padding = 8
  #var carrier = 0
  #var modulator = 0
  #var modDepth = 0

  #var ops = newSeq[tuple[id: int, x,y: int, targets: seq[int]]]()
  #var y = y
  #y += 64
  #var x = x + padding
  #for map in algorithm:
  #  # find carriers
  #  if map[1] == 0:
  #    ops.add((id: map[0], x: x + carrier * (rectSize + padding), y: y, targets: @[]))
  #    carrier += 1
  #  # find modulators
  #  for map2 in algorithm:
  #    if map2[1] == map[0] and map[0] != map[1]:
  #      var thisOp: ptr tuple[id: int, x,y: int, targets: seq[int]]
  #      for op in mitems(ops):
  #        if op.id == map2[0]:
  #          thisOp = op.addr
  #          break
  #      if thisOp == nil:
  #        ops.add((id: map2[0], x: x + modulator * (rectSize + padding), y: y - (rectSize + padding), targets: newSeq[int]()))
  #        thisOp = ops[ops.high].addr
  #        modulator += 1
  #      thisOp.targets.add(map2[1])

  ## draw lines
  #for op in ops:
  #  for target in op.targets:
  #    if target == op.id:
  #      # feedback
  #      setColor(if self.TL[op.id-1] < 1023 and self.feedback > 0: 7 else: 1)
  #      nico.rrect(op.x - rectSize div 3, op.y - rectSize div 3, op.x + rectSize div 2, op.y + rectSize div 2)
  #    else:
  #      setColor(if self.TL[op.id-1] < 1023: 7 else: 1)
  #      for op2 in ops:
  #        if op2.id == target:
  #          line(op.x + rectSize div 2, op.y + rectSize div 2, op2.x + rectSize div 2, op2.y + rectSize div 2)
  #          break

  ## draw boxes
  #for op in ops:
  #  setColor(0)
  #  rrectfill(op.x, op.y, op.x + rectSize, op.y + rectSize)
  #  setColor(if self.TL[op.id-1] < 1023: 7 else: 1)
  #  nico.rrect(op.x, op.y, op.x + rectSize, op.y + rectSize)
  #  setColor(if self.TL[op.id-1] < 1023: 7 else: 1)

  #  setColor(7)
  #  printc($op.id, op.x + 6, op.y + 6)



proc newYM2612(): Machine =
  var m = new(YM2612Synth)
  m.init()
  return m

registerMachine("YM2612", newYM2612, "generator")

import fenv
import math
import common

const maxFilters = 8

type
  SVFFilterKind = enum
    LP
    HP
    Band
    Notch
  SVFFilter = object of RootObj
    kind: SVFFilterKind
    Fc: float
    Q: float
    drive: float
    notch,lp,hp,band: float
  SVFFilterMachine = ref object of Machine
    filters: array[maxFilters,SVFFilter]
    nFilters: int

{.this:self.}

method init(self: SVFFilterMachine) =
  procCall init(Machine(self))
  name = "svf"
  nInputs = 1
  nOutputs = 1
  stereo = false

  self.globalParams.add([
    Parameter(name: "kind", kind: Int, min: LP.float, max: Notch.float, default: LP.float, onchange: proc(newValue: float, voice: int) =
      for i in 0..<maxFilters:
        self.filters[i].kind = newValue.SVFFilterKind
    ),
    Parameter(name: "f", kind: Float, min: 0.00001, max: 0.5, default: 0.25, onchange: proc(newValue: float, voice: int) =
      for i in 0..<maxFilters:
        self.filters[i].Fc = clamp(newValue, 0.00001, 0.5) * sampleRate
    ),
    Parameter(name: "q", kind: Float, min: 0.00001, max: 0.99999, default: 0.5, onchange: proc(newValue: float, voice: int) =
      for i in 0..<maxFilters:
        self.filters[i].Q = newValue
    ),
    Parameter(name: "drive", kind: Float, min: 0.0, max: 0.1, default: 0.0, onchange: proc(newValue: float, voice: int) =
      for i in 0..<maxFilters:
        self.filters[i].drive = newValue
    ),
    Parameter(name: "poles", kind: Int, min: 1.0, max: maxFilters.float, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.nFilters = clamp(newValue.int, 1, maxFilters)
    ),
  ])

  setDefaults()

proc process(self: var SVFFilter, s: float): float =
  let Fs = sampleRate
  let freq = 2.0 * sin(PI * min(0.25, Fc / (Fs*2.0)))
  let damp = min(2.0*(1.0 - pow(Q, 0.25)), min(2.0, 2.0 / freq - freq * 0.5))

  notch = s - damp * band
  lp = lp + freq * band
  hp = notch - lp
  band = freq * hp + band - drive * band * band * band

  var output: float32

  case kind:
  of LP:
    output = 0.5 * lp
  of HP:
    output = 0.5 * hp
  of Band:
    output = 0.5 * band
  of Notch:
    output = 0.5 * notch

  notch = s - damp * band
  lp = lp + freq * band
  hp = notch - lp
  band = freq * hp + band - drive * band * band * band

  case kind:
  of LP:
    output += 0.5 * lp
  of HP:
    output += 0.5 * hp
  of Band:
    output += 0.5 * band
  of Notch:
    output += 0.5 * notch

  return output

method process(self: SVFFilterMachine) =
  var s = getInput()
  for i in 0..<nFilters:
    s = self.filters[i].process(s)

  outputSamples[0] = s

proc reset(self: var SVFFilter) =
  notch = 0.0
  lp = 0.0
  hp = 0.0
  band = 0.0

method reset(self: SVFFilterMachine) =
  for i in 0..<nFilters:
    self.filters[i].reset()

method getOutputName(self: SVFFilterMachine, outputId: int): string =
  case outputId:
  of 0:
    return "lp"
  of 1:
    return "hp"
  of 2:
    return "bp"
  of 3:
    return "notch"
  else:
    return nil


proc newMachine(): Machine =
  var m = new(SVFFilterMachine)
  m.init()
  return m

registerMachine("svf", newMachine, "fx")

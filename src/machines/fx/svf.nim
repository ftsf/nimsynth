import fenv
import math
import common
import core/basemachine
import core/fft
import nico
import util

const maxFilters = 8

type
  SVFFilterKind = enum
    LP
    HP
    Band
    Notch
  SVFFilter = object of RootObj
    kind: SVFFilterKind
    Fc: float32
    Q: float32
    drive: float32
    notch,lp,hp,band: float32
    limit: float32
  SVFFilterMachine = ref object of Machine
    filters: array[maxFilters,SVFFilter]
    nFilters: int
    hasChanged: bool
    responseGraph: array[1024, float32]

{.this:self.}

proc process(self: var SVFFilter, s: float32): float32
proc reset(self: var SVFFilter)

proc graphResponse(self: SVFFilterMachine) =
  const resolution = 1024
  var impulse = generateImpulse(resolution)

  var filters = filters
  for i in 0..<nFilters:
    filters[i].reset()

  for i in 0..<resolution:
    for j in 0..<nFilters:
      impulse[i] = filters[j].process(impulse[i])

  var response = graphResponse(impulse, resolution)
  for i in 0..<resolution:
    responseGraph[i] = response[i]

method init(self: SVFFilterMachine) =
  procCall init(Machine(self))
  name = "svf"
  nInputs = 1
  nOutputs = 1
  stereo = false

  self.globalParams.add([
    Parameter(name: "kind", kind: Int, min: LP.float32, max: Notch.float32, default: LP.float32, onchange: proc(newValue: float32, voice: int) =
      for i in 0..<maxFilters:
        self.filters[i].kind = newValue.SVFFilterKind
      self.hasChanged = true
    ),
    Parameter(name: "f", kind: Float, min: 0.00001, max: 0.5, default: 0.25, onchange: proc(newValue: float32, voice: int) =
      for i in 0..<maxFilters:
        self.filters[i].Fc = clamp(newValue, 0.00001f, 0.5f) * sampleRate
      self.hasChanged = true
    ),
    Parameter(name: "q", kind: Float, min: 0.00001, max: 0.99999, default: 0.5, onchange: proc(newValue: float32, voice: int) =
      for i in 0..<maxFilters:
        self.filters[i].Q = newValue
      self.hasChanged = true
    ),
    Parameter(name: "drive", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      for i in 0..<maxFilters:
        self.filters[i].drive = newValue
      self.hasChanged = true
    ),
    Parameter(name: "limit", kind: Float, min: 0.5, max: 0.99999, default: 0.9, onchange: proc(newValue: float32, voice: int) =
      for i in 0..<maxFilters:
        self.filters[i].limit = clamp(newValue, 0.5, 0.99999)
      self.hasChanged = true
    ),
    Parameter(name: "series", kind: Int, min: 1.0, max: maxFilters.float32, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.nFilters = clamp(newValue.int, 1, maxFilters)
      self.hasChanged = true
    ),
  ])

  setDefaults()

proc saturate(input: float32, limit: float32): float32 =
  let x1 = abs(input + limit)
  let x2 = abs(input - limit)
  return 0.5 * (x1 - x2)

proc process(self: var SVFFilter, s: float32): float32 =
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
  output = saturate(output, limit)

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
  output = saturate(output, limit)

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
    return ""

method getAABB*(self: SVFFilterMachine): AABB =
  result.min.x = pos.x - 16
  result.min.y = pos.y - 4
  result.max.x = pos.x + 16
  result.max.y = pos.y + 16

method drawBox(self: SVFFilterMachine) =
  setColor(0)
  rectfill(getAABB())
  setColor(5)
  rect(getAABB())


  if hasChanged:
    graphResponse()

  setColor(1)
  vline(
    pos.x - 16 + (globalParams[1].value * 64.0),
    pos.y - 3,
    pos.y + 15
  )

  for i in 1..<32:
    setColor(3)
    let v0 = responseGraph.getSubsample(((i-1).float32 / 32.0) * (responseGraph.len.float32 / 2.0))
    let v1 = responseGraph.getSubsample((i.float32 / 32.0) * (responseGraph.len.float32 / 2.0))
    line(
      pos.x + i - 1 - 16,
      pos.y + 9 - clamp(v0 * 4.0, -6.0, 12.0),
      pos.x + i - 16,
      pos.y + 9 - clamp(v1 * 4.0, -6.0, 12.0)
    )


proc newMachine(): Machine =
  var m = new(SVFFilterMachine)
  m.init()
  return m

registerMachine("svf", newMachine, "fx")

import common
import osc
import util
import strutils
import master
import math
import pico
import basemachine

type
  LFOMode = enum
    MinMax
    CenterAmp
  LFO = ref object of Machine
    osc: LFOOsc
    min,max: float
    center,amp: float
    mode: LFOMode
    freq: float
    bpmSync: bool

{.this:self.}

proc setFreq(self: LFO) =
  if bpmSync:
    osc.freq = ((freq * 16.0).floor / 16.0) * beatsPerSecond()
  else:
    osc.freq = freq

method onBPMChange(self: LFO, bpm: int) =
  setFreq()

method init(self: LFO) =
  procCall init(Machine(self))
  nOutputs = 0
  nInputs = 0
  name = "lfo"
  nBindings = 1
  bindings.setLen(1)

  osc.pulseWidth = 0.5

  globalParams.add([
    Parameter(name: "freq", kind: Float, min: 0.0, max: 10.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.freq = newValue
      self.setFreq()
    , getValueString: proc(value: float, voice: int): string =
      if self.bpmSync:
        return getFractionStr((value * 16.0).int, 16)
      else:
        return $value.formatFloat(ffDecimal, 2) & " hZ"
    ),
    Parameter(name: "mode", kind: Int, min: 0, max: LFOMode.high.float, default: MinMax.float, onchange: proc(newValue: float, voice: int) =
      self.mode = newValue.LFOMode
    , getValueString: proc(value: float, voice: int): string =
      return $value.LFOMode
    ),
    Parameter(name: "shape", kind: Int, min: OscKind.low.float, max: OscKind.high.float, default: Sin.float, onchange: proc(newValue: float, voice: int) =
      self.osc.kind = newValue.OscKind
    , getValueString: proc(value: float, voice: int): string =
      return $value.OscKind
    ),
    Parameter(name: "min", kind: Float, min: 0.0, max: 1.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.min = newValue
    , getValueString: proc(value: float, voice: int): string =
      var binding = self.bindings[0]
      if binding.machine != nil:
        var (voice, param) = binding.machine.getParameter(binding.param)
        return param[].valueString(lerp(param.min, param.max, value))
      else:
        return value.formatFloat(ffDecimal, 2)
    ),
    Parameter(name: "max", kind: Float, min: 0.0, max: 1.0, default: 0.9, onchange: proc(newValue: float, voice: int) =
      self.max = newValue
    , getValueString: proc(value: float, voice: int): string =
      var binding = self.bindings[0]
      if binding.machine != nil:
        var (voice, param) = binding.machine.getParameter(binding.param)
        return param[].valueString(lerp(param.min, param.max, value))
      else:
        return value.formatFloat(ffDecimal, 2)
    ),
    Parameter(name: "center", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.center = newValue
    , getValueString: proc(value: float, voice: int): string =
      var binding = self.bindings[0]
      if binding.machine != nil:
        var (voice, param) = binding.machine.getParameter(binding.param)
        return param[].valueString(lerp(param.min, param.max, value))
      else:
        return value.formatFloat(ffDecimal, 2)
    ),
    Parameter(name: "amp", kind: Float, min: 0.0, max: 1.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.amp = newValue
    , getValueString: proc(value: float, voice: int): string =
        return (value * 100.0).formatFloat(ffDecimal, 2) & "%"
    ),
    Parameter(name: "bpmsync", kind: Bool, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.bpmSync = newValue.bool
      self.setFreq()
    ),
    Parameter(name: "phase", kind: Float, min: 0.0, max: TAU, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.osc.phase = newValue
    ),
  ])

  setDefaults()

method process(self: LFO) {.inline.} =
  if freq == 0.0:
    return
  let oscVal = osc.process()
  for binding in bindings:
    if binding.machine != nil:
      var (voice, param) = binding.machine.getParameter(binding.param)
      case mode:
      of MinMax:
        param.value = lerp(param.min, param.max, lerp(min, max, invLerp(-1.0, 1.0, oscVal)))
      of CenterAmp:
        param.value = lerp(param.min, param.max, lerp(center - amp, center + amp, invLerp(-1.0, 1.0, oscVal)))
      param.onchange(param.value, voice)

  globalParams[8].value = osc.phase

method getAABB*(self: LFO): AABB =
  result.min.x = pos.x - 16
  result.min.y = pos.y - 4
  result.max.x = pos.x + 16
  result.max.y = pos.y + 16

method drawBox*(self: LFO) =
  setColor(2)
  rectfill(getAABB())
  setColor(6)
  rect(getAABB())

  var binding = bindings[0].addr
  if binding.machine != nil:
    var (voice, param) = binding.machine.getParameter(binding.param)
    printc(param.name, pos.x, pos.y - 2)
  else:
    printc(name, pos.x, pos.y - 2)

  setColor(0)
  rectfill(pos.x - 15, pos.y + 4, pos.x + 15, pos.y + 14)
  setColor(5)
  line(pos.x, pos.y + 4, pos.x, pos.y + 14)
  for i in -15..15:
    if i == 0:
      setColor(7)
    else:
      setColor(1)
    let val = osc.peek(osc.phase + ((i.float / 30.float) * TAU))
    pset(pos.x + i, pos.y + 9 - val * 4.0)


method createBinding(self: LFO, slot: int, target: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, target, paramId)
  var binding = bindings[0].addr
  var (voice, param) = binding.machine.getParameter(binding.param)
  self.name = param.name & " lfo"

proc newLFO(): Machine =
  var lfo = new(LFO)
  lfo.init()
  return lfo

method drawExtraData(self: LFO, x,y,w,h: int) =
  var y = y
  setColor(4)
  for binding in bindings:
    if binding.machine != nil:
      var (voice, param) = binding.machine.getParameter(binding.param)
      printr(binding.machine.name & ": " & param.name, x + w, y)
      y += 8
      printr(param[].valueString(param[].value), x + w, y)
      y += 8

  setColor(6)
  printr(osc.freq.formatFloat(ffDecimal, 2), x + w, y)

registerMachine("lfo", newLFO, "util")

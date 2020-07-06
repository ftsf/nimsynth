import math
import strutils

import nico
import nico/vec

import common
import util

import ui/layoutview

const size = 24'f
const halfSize = 12'f
const padding = 6'f

type AxisType = enum
  atFullRange = "full"
  atPositive = "+"
  atNegative = "-"

type XY = ref object of Machine
  gamepad: int
  gamepadXAxis: int
  gamepadYAxis: int
  xAxisType: AxisType
  yAxisType: AxisType
  xAxisMin: float32
  yAxisMin: float32
  xAxisMax: float32
  yAxisMax: float32
  invertXAxis: bool
  invertYAxis: bool
  eventListener: EventListener
  x,y: float32
  tx,ty: float32
  speed: float32

{.this:self.}

proc setX(self: XY, xval: float32) =
  let x = clamp(xval * (if self.invertXAxis: -1'f else: 1'f), -1'f, 1'f)
  if bindings[0].isBound():
    var (voice, param) = bindings[0].getParameter()
    param.value = lerp(self.xAxisMin, self.xAxisMax, clamp(x * 0.5'f + 0.5'f))
    param.onchange(param.value, voice)

proc setY(self: XY, yval: float32) =
  let y = clamp(yval * (if self.invertYAxis: -1'f else: 1'f), -1'f, 1'f)
  if bindings[1].isBound():
    var (voice, param) = bindings[1].getParameter()
    param.value = lerp(self.yAxisMin, self.yAxisMax, clamp(y * 0.5'f + 0.5'f))
    param.onchange(param.value, voice)

method init(self: XY) =
  procCall init(Machine(self))
  nBindings = 2
  bindings.setLen(2)
  name = "xy"
  speed = 5.0'f

  self.globalParams.add([
    Parameter(name: "gamepad", kind: Int, min: 0'f, max: 3'f, default: 0'f, onchange: proc(newValue: float, voice: int) =
      self.gamepad = newValue.int
    ),
    Parameter(name: "xaxis", kind: Int, min: 0'f, max: NicoAxis.high.float, default: 0'f, onchange: proc(newValue: float, voice: int) =
      self.gamepadXAxis = newValue.int
    ),
    Parameter(name: "invert x", kind: Bool, min: 0'f, max: 1'f, default: 0'f, onchange: proc(newValue: float, voice: int) =
      self.invertXAxis = newValue.bool
    ),
    Parameter(name: "xaxis min", kind: Float, min: -1'f, max: 1'f, default: -1'f, onchange: proc(newValue: float, voice: int) =
      self.xAxisMin = newValue.float32
    ),
    Parameter(name: "xaxis max", kind: Float, min: -1'f, max: 1'f, default: 1'f, onchange: proc(newValue: float, voice: int) =
      self.xAxisMax = newValue.float32
    ),
    Parameter(name: "xaxis type", kind: Int, min: 0'f, max: AxisType.high.float, default: 0'f, onchange: proc(newValue: float, voice: int) =
      self.xAxisType = newValue.AxisType
    ),
    Parameter(name: "yaxis", kind: Int, separator: true, min: 0'f, max: NicoAxis.high.float, default: 1'f, onchange: proc(newValue: float, voice: int) =
      self.gamepadYAxis = newValue.int
    ),
    Parameter(name: "invert y", kind: Bool, min: 0'f, max: 1'f, default: 0'f, onchange: proc(newValue: float, voice: int) =
      self.invertYAxis = newValue.bool
    ),
    Parameter(name: "yaxis min", kind: Float, min: -1'f, max: 1'f, default: -1'f, onchange: proc(newValue: float, voice: int) =
      self.yAxisMin = newValue.float32
    ),
    Parameter(name: "yaxis max", kind: Float, min: -1'f, max: 1'f, default: 1'f, onchange: proc(newValue: float, voice: int) =
      self.yAxisMax = newValue.float32
    ),

    Parameter(name: "yaxis type", kind: Int, min: 0'f, max: AxisType.high.float, default: 0'f, onchange: proc(newValue: float, voice: int) =
      self.yAxisType = newValue.AxisType
    ),
    Parameter(name: "speed", kind: Float, min: 0.1'f, max: 100'f, default: 10'f, onchange: proc(newValue: float, voice: int) =
      self.speed = newValue
    ),
  ])

  self.eventListener = addEventListener(proc(e: Event): bool =
    if e.kind == ekAxisMotion and e.which == self.gamepad:
      if e.button == self.gamepadXAxis:
        self.tx = e.xrel
        return true
      if e.button == self.gamepadYAxis:
        self.ty = e.xrel
        return true
    return false
  )

  setDefaults()

method createBinding*(self: XY, slot: int, target: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, target, paramId)

  # match input to be the same as the target param
  if slot == 0:
    var (voice,param) = target.getParameter(paramId)
    var inputParam = globalParams[3].addr
    inputParam.kind = param.kind
    inputParam.min = param.min
    inputParam.max = param.max
    inputParam.getValueString = param.getValueString

    inputParam = globalParams[4].addr
    inputParam.kind = param.kind
    inputParam.min = param.min
    inputParam.max = param.max
    inputParam.getValueString = param.getValueString

  elif slot == 1:
    var (voice,param) = target.getParameter(paramId)
    var inputParam = globalParams[8].addr
    inputParam.kind = param.kind
    inputParam.min = param.min
    inputParam.max = param.max
    inputParam.getValueString = param.getValueString

    inputParam = globalParams[9].addr
    inputParam.kind = param.kind
    inputParam.min = param.min
    inputParam.max = param.max
    inputParam.getValueString = param.getValueString

method cleanup(self: XY) =
  removeEventListener(self.eventListener)

method getAABB(self: XY): AABB =
  result.min.x = self.pos.x - halfSize - padding
  result.min.y = self.pos.y - halfSize - padding
  result.max.x = self.pos.x + halfSize + padding
  result.max.y = self.pos.y + halfSize + padding

proc getButtonAABB(self: XY): AABB =
  result.min.x = self.pos.x - halfSize
  result.min.y = self.pos.y - halfSize
  result.max.x = self.pos.x + halfSize
  result.max.y = self.pos.y + halfSize

method drawBox(self: XY) =
  let x = self.pos.x.int
  let y = self.pos.y.int

  setColor(1)
  rrectfill(getAABB())
  setColor(0)
  rrectfill(getButtonAABB())
  setColor(12)
  circfill(x + self.tx * halfSize, y + self.ty * halfSize, 2)
  setColor(7)
  circfill(x + self.x * halfSize, y + self.y * halfSize, 1)

  setColor(if bypass: 5 elif disabled: 1 else: 6)
  rrect(getAABB())
  printc(name, pos.x, pos.y + halfSize)

method handleClick(self: XY, mouse: Vec2f): bool =
  if pointInAABB(mouse, getButtonAABB()):
    return true
  return false

method update(self: XY, dt: float32) =
  self.x = lerp(self.x, self.tx, speed * dt)
  self.y = lerp(self.y, self.ty, speed * dt)
  self.setX(self.x)
  self.setY(self.y)

method event(self: XY, event: Event, camera: Vec2f): (bool, bool) =
  if event.kind == ekMouseButtonDown:
    return (true, true)

  elif event.kind == ekMouseButtonUp:
    return (false, false)

  elif event.kind == ekMouseMotion:
    self.tx = clamp((event.x.float32 - camera.x.float32 - self.pos.x.float32) / size, -1'f, 1'f)
    self.ty = clamp((event.y.float32 - camera.y.float32 - self.pos.y.float32) / size, -1'f, 1'f)

  return (false, true)

proc newXY(): Machine =
  var m = new(XY)
  m.init()
  return m

registerMachine("xy", newXY, "ui")

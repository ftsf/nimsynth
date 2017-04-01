import basic2d
import math
import strutils

import pico

import common
import util

import ui.layoutview


type Button = ref object of Machine
  state: bool
  onValue: float
  offValue: float
  toggle: bool

{.this:self.}

method init(self: Button) =
  procCall init(Machine(self))
  nBindings = 1
  bindings.setLen(1)
  name = "button"

  self.globalParams.add([
    Parameter(name: "state", kind: Trigger, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.state = newValue.bool
    ),
    Parameter(name: "on", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.onValue = newValue
    ),
    Parameter(name: "off", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.offValue = newValue
    ),
    Parameter(name: "toggle", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.toggle = newValue.bool
    ),
  ])

  setDefaults()

method createBinding*(self: Button, slot: int, target: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, target, paramId)

  # match input to be the same as the target param
  var (voice,param) = target.getParameter(paramId)
  var inputParam = globalParams[1].addr
  inputParam.kind = param.kind
  inputParam.min = param.min
  inputParam.max = param.max
  inputParam.getValueString = param.getValueString

  inputParam = globalParams[2].addr
  inputParam.kind = param.kind
  inputParam.min = param.min
  inputParam.max = param.max
  inputParam.getValueString = param.getValueString


method getAABB(self: Button): AABB =
  result.min.x = self.pos.x - 12.0
  result.min.y = self.pos.y - 12.0
  result.max.x = self.pos.x + 12.0
  result.max.y = self.pos.y + 12.0

proc getButtonAABB(self: Button): AABB =
  result.min.x = self.pos.x - 6.0
  result.min.y = self.pos.y - 6.0
  result.max.x = self.pos.x + 6.0
  result.max.y = self.pos.y + 6.0

method drawBox(self: Button) =
  let x = self.pos.x.int
  let y = self.pos.y.int

  setColor(if state: 5 else: 4)
  rectfill(getButtonAABB())
  setColor(1)
  rect(getButtonAABB())
  setColor(6)


method handleClick(self: Button, mouse: Point2d): bool =
  if pointInAABB(mouse, getButtonAABB()):
    return true
  return false

method layoutUpdate(self: Button, layout: View, dt: float) =
  if not mousebtn(0):
    LayoutView(layout).stolenInput = nil

  if mousebtnp(0) and toggle:
    echo "toggled"
    state = not state
    if bindings[0].isBound():
      var (voice, param) = bindings[0].getParameter()
      param.value = if state: onValue else: offValue
      param.onchange(param.value, voice)
  else:
    if not state and mousebtnp(0):
      echo "on"
      state = true
      if bindings[0].isBound():
        var (voice, param) = bindings[0].getParameter()
        param.value = onValue
        param.onchange(onValue, voice)
    elif state and not mousebtnp(0):
      echo "off"
      if bindings[0].isBound():
        var (voice, param) = bindings[0].getParameter()
        param.value = offValue
        param.onchange(offValue, voice)

proc newButton(): Machine =
  var button = new(Button)
  button.init()
  return button

registerMachine("button", newButton, "ui")

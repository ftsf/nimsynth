import basic2d
import math
import strutils

import pico

import common
import util

import core.basemachine
import ui.layoutview
import ui.menu


type ValueMachine = ref object of Machine
  value: float

{.this:self.}

proc setValue(self: ValueMachine, value: float) =
  self.value = value

  if bindings[0].isBound():
    var (voice,param) = bindings[0].getParameter()
    param.value = value
    param.onchange(value, voice)

  self.name = ($self.value)[0..6]
  self.globalParams[0].value = value

method init(self: ValueMachine) =
  procCall init(Machine(self))
  nBindings = 1
  bindings.setLen(1)
  name = "value"

  self.globalParams.add([
    Parameter(name: "value", kind: Float, min: -10000.0, max: 10000.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.setValue(newValue)
    ),
  ])
  setDefaults()

method createBinding(self: ValueMachine, slot: int, target: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, target, paramId)
  # send value
  var (voice,param) = bindings[slot].getParameter()
  param.value = value
  param.onchange(value, voice)

proc inputMenu(self: ValueMachine, mv: Point2d): Menu =
  var menu = newMenu(mv, nil)
  var te = newMenuItemText("value", $value) do(newValue: string):
    try:
      self.setValue(parseFloat(newValue))
    except ValueError:
      discard
  menu.items.add(te)
  return menu

method handleClick*(self: ValueMachine, mouse: Point2d): bool =
  if pointInAABB(mouse, getAABB()):
    return true
  return false

method event*(self: ValueMachine, event: Event, camera: Point2d): (bool, bool) =
  case event.kind:
  of MouseButtonDown:
    if event.button.button == 1:
      if event.button.clicks == 2:
        pushMenu(self.inputMenu(mouse() + point2d(-4.0, -4.0)))
        return (true,false)
      return (false,true)
  else:
    return (false,false)

method getMenu*(self: ValueMachine, mv: Point2d): Menu =
  result = procCall getMenu(Machine(self), mv)
  result.items.add(newMenuItem("set value") do():
    popMenu()
    pushMenu(self.inputMenu(mv))
  )

proc newValue(): Machine =
  var m = new(ValueMachine)
  m.init()
  return m

registerMachine("value", newValue, "ui")

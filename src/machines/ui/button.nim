import math
import strutils

import nico
import nico/vec

import common
import util

import ui/layoutview


type Button = ref object of Machine
  state: bool
  onValue: float32
  offValue: float32
  toggle: bool
  gamepad: int
  gamepadButton: int
  eventListener: EventListener

{.this:self.}

proc setOn(self: Button) =
  state = true
  if bindings[0].isBound():
    var (voice, param) = bindings[0].getParameter()
    param.value = onValue
    param.onchange(param.value, voice)

proc setOff(self: Button) =
  state = false
  if bindings[0].isBound():
    var (voice, param) = bindings[0].getParameter()
    param.value = offValue
    param.onchange(param.value, voice)

method init(self: Button) =
  procCall init(Machine(self))
  nBindings = 1
  bindings.setLen(1)
  name = "button"

  self.globalParams.add([
    Parameter(name: "state", kind: Trigger, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.state = newValue.bool
    ),
    Parameter(name: "on", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.onValue = newValue
    ),
    Parameter(name: "off", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.offValue = newValue
    ),
    Parameter(name: "toggle", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.toggle = newValue.bool
    ),
    Parameter(name: "gamepad", kind: Int, min: 0'f, max: 3'f, default: 0'f, onchange: proc(newValue: float32, voice: int) =
      self.gamepad = newValue.int
    ),
    Parameter(name: "button", kind: Int, min: -1'f, max: NicoButton.high.float32, default: -1, onchange: proc(newValue: float32, voice: int) =
      self.gamepadButton = newValue.int
    ),
  ])

  self.eventListener = addEventListener(proc(e: Event): bool =
    if e.kind == ekButtonDown and e.button.int == self.gamepadButton and e.which.int == self.gamepad:
      self.setOn()
      return false
    elif e.kind == ekButtonUp and e.button.int == self.gamepadButton and e.which.int == self.gamepad:
      self.setOff()
      return false
    return false
  )

  setDefaults()

method cleanup(self: Button) =
  removeEventListener(self.eventListener)

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

const gamepadButtonNames = [
  "A", "B", "X", "Y", "back", "guide", "start", "L3", "R3", "L1", "R1", "UP", "DOWN", "LEFT", "RIGHT",
]

const gamepadButtonColors = [
  11, 3, 8, 2, 12, 1, 10, 9,
]

method drawBox(self: Button) =
  let x = self.pos.x.int
  let y = self.pos.y.int

  if self.gamepadButton >= 0 and self.gamepadButton < gamepadButtonColors.len div 2:
    setColor(0)
    circfill(self.pos.x, self.pos.y, 7)
    setColor(gamepadButtonColors[self.gamepadButton*2])
    circfill(self.pos.x, self.pos.y, 5)
    setColor(gamepadButtonColors[self.gamepadButton*2+1])
    circ(self.pos.x, self.pos.y, 5)
    if state:
      setColor(7)
      circ(self.pos.x, self.pos.y, 7)

  else:
    setColor(if state: 5 else: 4)
    rrectfill(getButtonAABB())
    setColor(1)
    rrect(getButtonAABB())

  if self.gamepadButton >= 0 and self.gamepadButton < gamepadButtonNames.len:
    setColor(0)
    printc(gamepadButtonNames[self.gamepadButton], pos.x, pos.y)


method handleClick(self: Button, mouse: Vec2f): bool =
  if pointInAABB(mouse, getButtonAABB()):
    return true
  return false

method event(self: Button, event: Event, camera: Vec2f): (bool, bool) =
  if toggle and event.kind == ekMouseButtonDown:
    state = not state
    if state:
      self.setOn()
    else:
      self.setOff()
    return (true, false)

  if not state and event.kind == ekMouseButtonDown:
    setOn()
    return (true, true)

  elif state and event.kind == ekMouseButtonUp:
    setOff()
    return (false, false)

  return (false, true)

proc newButton(): Machine =
  var button = new(Button)
  button.init()
  return button

registerMachine("button", newButton, "ui")

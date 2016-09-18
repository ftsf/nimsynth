import common
import pico
import util
import math
import strutils
import basic2d
import layoutview

type Knob = ref object of Machine
  lastmv: Point2d

{.this:self.}

method init(self: Knob) =
  procCall init(Machine(self))
  nBindings = 1
  bindings.setLen(1)
  name = "knob"

method drawBox(self: Knob) =
  let x = self.pos.x.int
  let y = self.pos.y.int

  setColor(4)
  circfill(x, y, 4)
  setColor(1)
  circ(x, y, 5)
  setColor(6)
  if bindings[0].machine != nil:
    var (voice,param) = bindings[0].machine.getParameter(bindings[0].param)
    let range = param.max - param.min
    let angle = lerp(degToRad(-180.0 - 45.0), degToRad(45.0), ((param.value - param.min) / range))
    line(x,y, x + cos(angle) * 4, y + sin(angle) * 4)
    printShadowC(param.name, x, y + 8)
    printShadowC(
      if param.getValueString != nil:
        param.getValueString(param.value, voice)
      elif param.kind == Int:
        $param.value.int
      else:
        param.value.formatFloat(ffDecimal, 2)
      , x, y + 16)
  else:
    printShadowC(name, x, y + 8)

method getAABB(self: Knob): AABB =
  result.min.x = self.pos.x - 12.0
  result.min.y = self.pos.y - 6.0
  result.max.x = self.pos.x + 12.0
  result.max.y = self.pos.y + 12.0

proc getKnobAABB(self: Knob): AABB =
  result.min.x = self.pos.x - 6.0
  result.min.y = self.pos.y - 6.0
  result.max.x = self.pos.x + 6.0
  result.max.y = self.pos.y + 6.0

method handleClick(self: Knob, mouse: Point2d): bool =
  if pointInAABB(mouse, getKnobAABB()):
    lastmv = mouse()
    relmouse(true)
    return true
  return false

method layoutUpdate(self: Knob, layout: View, dt: float) =
  if not mousebtn(0):
    LayoutView(layout).stolenInput = nil
    relmouse(false)

  elif bindings[0].machine != nil:
    let mv = mouse()

    var (voice,param) = bindings[0].machine.getParameter(bindings[0].param)
    let shift = (getModState() and KMOD_SHIFT) != 0
    let ctrl = (getModState() and KMOD_CTRL) != 0
    let move = if ctrl: 0.1 elif shift: 0.001 else: 0.01

    param.value -= (mv.y - lastmv.y) * move * (param.max - param.min)
    param.value = clamp(param.value, param.min, param.max)
    param.onchange(param.value)

    lastmv = mv

proc newKnob(): Machine =
  var knob = new(Knob)
  knob.init()
  return knob

registerMachine("knob", newKnob)

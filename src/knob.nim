import common
import pico
import util
import math
import strutils
import basic2d
import layoutview
import menu
import basemachine

type Knob = ref object of Machine
  lastmv: Point2d
  held: bool
  min,max: float
  center: float
  spring: float
  midicc: int
  learning: bool

{.this:self.}

method init(self: Knob) =
  procCall init(Machine(self))
  nBindings = 1
  bindings.setLen(1)
  name = "knob"
  useMidi = true
  midiChannel = 0

  self.globalParams.add([
    Parameter(name: "min", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.min = newValue
    ),
    Parameter(name: "max", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.max = newValue
    ),
    Parameter(name: "center", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.center = newValue
    ),
    Parameter(name: "spring", kind: Float, min: 0.0, max: 10.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.spring = newValue
    ),
    Parameter(name: "cc", kind: Int, min: 0.0, max: 120.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.midicc = newValue.int
    ),
  ])

  setDefaults()


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
    let min = lerp(param.min,param.max,self.min)
    let max = lerp(param.min,param.max,self.max)
    let range = max - min
    if range != 0.0:
      let angle = lerp(degToRad(-180.0 - 45.0), degToRad(45.0), ((param.value - min) / range))
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

method midiEvent(self: Knob, event: MidiEvent) =
  if event.command == 3:
    if learning:
      self.midicc = event.data1.int
      self.globalParams[4].value = self.midicc.float
      self.learning = false
      echo "assigned cc: ", self.midicc
    elif event.data1 == midicc.uint8:
      if bindings[0].isBound:
        var (voice,param) = bindings[0].getParameter()
        let min = lerp(param.min,param.max,min)
        let max = lerp(param.min,param.max,max)
        param.value = lerp(min, max, event.data2.float / 127.0)
        param.onchange(param.value, voice)


method handleClick(self: Knob, mouse: Point2d): bool =
  if pointInAABB(mouse, getKnobAABB()):
    lastmv = mouse()
    relmouse(true)
    return true
  return false

method event(self: Knob, event: Event, camera: Point2d): (bool, bool) =
  case event.kind:
  of MouseButtonUp:
    if event.button.button == 1:
      relmouse(false)
      held = false
      return (true,false)

  of MouseButtonDown:
    held = true
    return (true,true)

  of MouseMotion:
    if bindings[0].machine != nil:
      var (voice,param) = bindings[0].machine.getParameter(bindings[0].param)
      let shift = (getModState() and KMOD_SHIFT) != 0
      let ctrl = ctrl()
      let move = if ctrl: 0.1 elif shift: 0.001 else: 0.01

      let min = lerp(param.min,param.max,min)
      let max = lerp(param.min,param.max,max)
      param.value -= event.motion.yrel.float * move * (max - min)
      param.value = clamp(param.value, min, max)
      param.onchange(param.value, voice)
      return (true,true)
  else:
    discard

  return (false,true)

method process(self: Knob) =
  if bindings[0].machine != nil and not held:
    if self.spring > 0.0:
      var (voice,param) = bindings[0].machine.getParameter(bindings[0].param)
      let d = param.value - center
      let f = d * spring * invSampleRate
      param.value -= f
      param.value = clamp(param.value, min, max)
      param.onchange(param.value, voice)

method getMenu*(self: Knob, mv: Point2d): Menu =
  result = procCall getMenu(Machine(self), mv)
  result.items.add(newMenuItem("midi learn") do():
    self.learning = true
    echo "learning enabled"
    popMenu()
  )

proc newKnob(): Machine =
  var knob = new(Knob)
  knob.init()
  return knob

registerMachine("knob", newKnob, "util")

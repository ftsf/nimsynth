import common
import pico
import strutils
import util
import basic2d
import math
import synth
import sdl2.audio

import basemachine
import machineview
import menu

### Layout View
# Draw a graph of the machine connections

{.this:self.}

proc draw(self: Knob) =
  let x = self.pos.x.int
  let y = self.pos.y.int

  setColor(4)
  circfill(x, y, 4)
  setColor(1)
  circ(x, y, 5)
  setColor(6)
  if self.paramId > -1:
    var (voice,param) = self.machine.getParameter(self.paramId)
    let range = param.max - param.min
    let angle = lerp(degToRad(-180 - 45), degToRad(45), ((param.value - param.min) / range))
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
    printShadowC("?", x, y + 8)

proc getAABB(self: Knob): AABB =
  result.min.x = self.pos.x - 6.0
  result.min.y = self.pos.y - 6.0
  result.max.x = self.pos.x + 6.0
  result.max.y = self.pos.y + 6.0

proc getHandleAABB(self: Knob): AABB =
  result.min.x = self.pos.x - 12.0
  result.max.x = self.pos.x + 12.0
  result.min.y = self.pos.y + 6.0
  result.max.y = self.pos.y + 12.0

type LayoutView* = ref object of View
  currentMachine*: Machine
  currentKnob*: Knob
  dragging*: bool
  tweaking*: bool
  adjustingInput*: ptr Input
  connecting*: bool
  lastmv*: Point2d
  menu*: Menu

const arrowVerts = [
  point2d(-5,-3),
  point2d( 5, 0),
  point2d(-5, 3)
]

proc newLayoutView*(): LayoutView =
  result = new(LayoutView)
  result.currentMachine = nil

method draw*(self: LayoutView) =
  cls()

  setColor(1)
  line(0, screenHeight div 2, screenWidth, screenHeight div 2)
  setColor(1)
  for x in 1..<sampleBuffer.len:
    if x > screenWidth:
      break
    let y0 = (sampleBuffer[x-1] * (screenHeight.float / 2.0)).int + screenHeight div 2
    let y1 = (sampleBuffer[x] * (screenHeight.float / 2.0)).int + screenHeight div 2
    line(x-1,y0,x,y1)

  setCamera(-screenWidth div 2, -screenHeight div 2)

  var mv = mouse() + vector2d(-screenWidth div 2, -screenHeight div 2)

  if connecting and currentMachine != nil:
    setColor(1)
    line(currentMachine.pos, mv)
  elif connecting and currentKnob != nil:
    setColor(4)
    line(currentKnob.pos, mv)

  # draw connections
  for machine in mitems(machines):
    for input in mitems(machine.inputs):
      # TODO: find nearest points on AABBs
      # TODO: use nice bezier splines for connections
      setColor(1)
      line(input.machine.pos, machine.pos)
      let mid = (input.machine.pos + machine.pos) / 2.0
      setColor(6)
      trifill(rotatedPoly(mid, arrowVerts, (machine.pos - input.machine.pos).angle))
      setColor(1)
      poly(rotatedPoly(mid, arrowVerts, (machine.pos - input.machine.pos).angle))
      if adjustingInput == addr(input):
        setColor(7)
        printShadowC(adjustingInput[].gain.formatFloat(ffDecimal, 2), mid.x.int, mid.y.int + 4)

  for knob in mitems(knobs):
    if knob.paramId > -1 and knob.machine != nil:
      setColor(4)
      line(knob.pos, knob.machine.pos)

  # draw boxes
  for machine in mitems(machines):
    machine.drawBox()

  for knob in knobs:
    knob.draw()

  if menu != nil:
    menu.draw()

  spr(20, mv.x, mv.y)

  setCamera()
  setColor(1)
  printr("layout", screenWidth - 1, 1)

method key*(self: LayoutView, key: KeyboardEventPtr, down: bool): bool =
  if menu != nil:
    if menu.key(key, down):
      return true
  let scancode = key.keysym.scancode
  if down:
    case scancode:
    of SDL_SCANCODE_F2:
      if currentMachine != nil:
        currentView = currentMachine.getMachineView()
        return true
    of SDL_SCANCODE_INSERT:
      if currentMachine != nil:
        recordMachine = currentMachine
    of SDL_SCANCODE_DELETE:
      if currentKnob != nil:
        knobs.del(knobs.find(currentKnob))
        currentKnob = nil
        return true
      if currentMachine != nil and currentMachine != masterMachine:
        currentMachine.delete()
        currentMachine = nil
        return true
    else:
      discard

  return false

method update*(self: LayoutView, dt: float) =
  var mv = mouse()
  mv.x += (-screenWidth div 2).float
  mv.y += (-screenHeight div 2).float

  if menu != nil:
    if mousebtnp(0):
      if pointInAABB(mv,menu.getAABB()):
        # check which item they clicked on
        let item = (mv.y - menu.pos.y).int div 9
        if item >= 0 and item < menu.items.len:
          menu.items[item].action()
      else:
        # clicked outside of menu, close it
        menu = nil

  # left click to select and move machines
  if mousebtnp(0):
    for knob in mitems(knobs):
      if pointInAABB(mv, knob.getAABB()):
        currentKnob = knob
        currentMachine = nil
        tweaking = true
        relmouse(true)
        break
      elif pointInAABB(mv, knob.getHandleAABB()):
        currentKnob = knob
        currentMachine = nil
        dragging = true
    for machine in mitems(machines):
      if pointInAABB(mv, machine.getAABB()):
        currentMachine = machine
        currentKnob = nil
        dragging = true
        break
    # check for adjusting input gain
    for machine in mitems(machines):
      for input in mitems(machine.inputs):
        let mid = (input.machine.pos + machine.pos) / 2.0
        if pointInAABB(mv, mid.getAABB(4.0)):
          adjustingInput = addr(input)
          relmouse(true)
          break

  if not mousebtn(0):
    dragging = false
    tweaking = false
    adjustingInput = nil
    relmouse(false)

  # right click drag to create connections, or delete them
  if mousebtnp(1):
    currentMachine = nil
    for machine in mitems(machines):
      if pointInAABB(mv, machine.getAABB()):
        currentMachine = machine
        if currentMachine.nOutputs > 0:
          connecting = true
        break
    if currentMachine == nil:
      # check if it was a connection midpoint
      for machine in mitems(machines):
        for i,input in machine.inputs:
          let mid = (input.machine.pos + machine.pos) / 2.0
          if pointInAABB(mv, mid.getAABB(4.0)):
            disconnectMachines(input.machine, machine)
            return
      for knob in mitems(knobs):
        if pointInAABB(mv, knob.getAABB()):
          currentKnob = knob
          currentMachine = nil
          connecting = true
          return
      # open new machine menu
      self.menu = newMenu()
      self.menu.pos = mv
      for i in 0..machineTypes.high:
        (proc =
          let mtype = machineTypes[i]
          var item = newMenuItem(mtype.name, proc() =
            var m = mtype.factory()
            m.pos = mv
            pauseAudio(1)
            machines.add(m)
            pauseAudio(0)
            self.menu = nil
          )
          self.menu.items.add(item)
        )()

      self.menu.items.add(newMenuItem("knob", proc() =
        var knob = new(Knob)
        knob = Knob(pos: mv, paramId: -1)
        knobs.add(knob)
      ))

  if not mousebtn(1) and not connecting and currentMachine == nil:
    # release right click when not over machine and not dragging from machine
    # TODO: open menu to select machine to insert
    # TODO: need a list of possible machines
    discard
  elif not mousebtn(1) and connecting and currentKnob != nil:
    # connect knob to machine
    for machine in mitems(machines):
      if pointInAABB(mv, machine.getAABB()):
        # open menu of params to connect knob to
        self.menu = newMenu()
        self.menu.pos = mv
        var knob = currentKnob
        var targetMachine = machine
        for i in 0..targetMachine.getParameterCount()-1:
          (proc =
            var paramId = i
            var (voice,param) = targetMachine.getParameter(i)
            var item = newMenuItem(param.name, proc() =
              knob.machine = targetMachine
              knob.paramId = paramId
            )
            self.menu.items.add(item)
          )()
        break
    connecting = false
    currentKnob = nil

  elif not mousebtn(1) and connecting and currentMachine != nil:
    # release right click drag, attempt to create connection
    # check if a connection was made
    for machine in mitems(machines):
      if machine == currentMachine:
        # TODO: same machine, open context menu
        # delete
        # replace
        discard
      else:
        if pointInAABB(mv, machine.getAABB()):
          discard connectMachines(currentMachine, machine)
    connecting = false

  if tweaking and currentKnob != nil:
    if currentKnob.paramId > -1:
      var (voice,param) = currentKnob.machine.getParameter(currentKnob.paramId)
      let shift = (getModState() and KMOD_SHIFT) != 0
      let ctrl = (getModState() and KMOD_CTRL) != 0
      let move = if ctrl: 0.1 elif shift: 0.001 else: 0.01
      param.value -= (mv.y - lastmv.y) * move * (param.max - param.min)
      param.value = clamp(param.value, param.min, param.max)
      param.onchange(param.value)
  elif dragging and currentKnob != nil:
    currentKnob.pos += (mv - lastmv)
  elif adjustingInput != nil:
    let shift = (getModState() and KMOD_SHIFT) != 0
    let ctrl = (getModState() and KMOD_CTRL) != 0
    let move = if ctrl: 0.1 elif shift: 0.001 else: 0.01
    adjustingInput[].gain = clamp(adjustingInput[].gain + (lastmv.y - mv.y) * move, 0.0, 10.0)
  elif dragging and currentMachine != nil:
    currentMachine.pos += (mv - lastmv)
  elif dragging and currentMachine != nil:
    currentMachine.pos += (mv - lastmv)

  lastmv = mv

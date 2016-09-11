import common
import pico
import strutils
import util
import basic2d
import synth

import machineview

### Layout View
# Draw a graph of the machine connections

{.this:self.}

type LayoutView* = ref object of View
  currentMachine*: Machine
  dragging*: bool
  connecting*: bool
  lastmv*: Point2d

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
  setColor(6)
  for x in 1..<sampleBuffer.len:
    if x > screenWidth:
      break
    let y0 = (sampleBuffer[x-1] * (screenHeight.float / 2.0)).int + screenHeight div 2
    let y1 = (sampleBuffer[x] * (screenHeight.float / 2.0)).int + screenHeight div 2
    line(x-1,y0,x,y1)

  setCamera(-screenWidth div 2, -screenHeight div 2)

  var mv = mouse() + vector2d(-screenWidth div 2, -screenHeight div 2)

  if connecting:
    setColor(1)
    line(currentMachine.pos, mv)

  # draw connections
  for machine in mitems(machines):
    for input in machine.inputs:
      setColor(1)
      line(input.machine.pos, machine.pos)
      let mid = (input.machine.pos + machine.pos) / 2.0
      setColor(6)
      trifill(rotatedPoly(mid, arrowVerts, (machine.pos - input.machine.pos).angle))
      setColor(1)
      poly(rotatedPoly(mid, arrowVerts, (machine.pos - input.machine.pos).angle))

  # draw boxes
  for machine in mitems(machines):
    setColor(if currentMachine == machine: 4 else: 1)
    rectfill(machine.pos.x - 16, machine.pos.y - 4, machine.pos.x + 16, machine.pos.y + 4)
    setColor(6)
    rect(machine.pos.x.int - 16, machine.pos.y.int - 4, machine.pos.x.int + 16, machine.pos.y.int + 4)
    printc(machine.name, machine.pos.x, machine.pos.y - 2)

  spr(20, mv.x, mv.y)

  setCamera()
  setColor(1)
  printr("layout", screenWidth - 1, 1)

proc getAABB(self: Machine): AABB =
  result.min.x = pos.x - 16
  result.min.y = pos.y - 4
  result.max.x = pos.x + 16
  result.max.y = pos.y + 4

proc getAdjacent(self: Machine): seq[Machine] =
  result = newSeq[Machine]()
  for input in mitems(inputs):
    result.add(input.machine)

proc DFS[T](current: T, white: var seq[T], grey: var seq[T], black: var seq[T]): bool =
  grey.add(current)
  for adj in current.getAdjacent():
    if adj in black:
      continue
    if adj in grey:
      # contains cycle
      return true
    if DFS(adj, white, grey, black):
      return true
  # fully explored: move from grey to black
  grey.del(grey.find(current))
  black.add(current)
  return false

proc hasCycle[T](G: seq[T]): bool =
  var white = newSeq[T]()
  white.add(G)
  var grey = newSeq[T]()
  var black = newSeq[T]()

  while white.len > 0:
    var current = white.pop()
    if(DFS(current, white, grey, black)):
      return true
  return false

method key*(self: LayoutView, key: KeyboardEventPtr, down: bool): bool =
  let scancode = key.keysym.scancode
  if down:
    case scancode:
    of SDL_SCANCODE_RETURN:
      if currentMachine != nil:
        MachineView(vMachineView).machine = currentMachine
        currentView = vMachineView
        echo "machine view"
        return true
    else:
      discard

  if currentMachine != nil:
    let note = keyToNote(key)
    if note > -1:
      if down and not key.repeat:
        currentMachine.trigger(note)
      elif not down:
        currentMachine.release(note)
  return false

method update*(self: LayoutView, dt: float) =
  var mv = mouse()
  mv.x += (-screenWidth div 2).float
  mv.y += (-screenHeight div 2).float

  # left click to select and move machines
  if mousebtnp(0):
    for machine in mitems(machines):
      if pointInAABB(mv, machine.getAABB()):
        currentMachine = machine
        dragging = true

  if not mousebtn(0):
    dragging = false

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
            machine.inputs.del(i)
            return
      # open new machine menu
      var m = newSynth()
      m.pos = mv
      machines.add(m)
      currentMachine = m

  # release right click drag, attempt to create connection
  if not mousebtn(1) and connecting and currentMachine != nil:
    # check if a connection was made
    for machine in mitems(machines):
      if machine != currentMachine:
        if pointInAABB(mv, machine.getAABB()):
          if machine.nInputs > 0:
            # check it doesn't connect back to us
            for rinput in currentMachine.inputs:
              if rinput.machine == machine:
                connecting = false
                echo "can't connect back"
                return
            machine.inputs.add(Input(machine: currentMachine, output: 0, gain: 1.0))
            if hasCycle(machines):
              echo "loop detected"
              discard machine.inputs.pop()
          else:
            echo "no inputs"
    connecting = false

  if dragging:
    currentMachine.pos += (mv - lastmv)

  lastmv = mv

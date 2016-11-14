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

import locks

### Layout View
# Draw a graph of the machine connections

{.this:self.}

type LayoutView* = ref object of View
  name*: string
  currentMachine*: Machine
  dragging*: bool
  adjustingInput*: ptr Input
  connecting*: bool
  binding*: bool
  lastmv*: Point2d
  stolenInput*: Machine
  camera*: Point2d
  panning: bool

const arrowVerts = [
  point2d(-3,-3),
  point2d( 3, 0),
  point2d(-3, 3)
]

proc newLayoutView*(): LayoutView =
  result = new(LayoutView)
  result.camera = point2d(-screenWidth.float / 2.0, -screenHeight.float / 2.0)
  result.currentMachine = nil

import tables

proc addMachineMenu(self: LayoutView, mv: Point2d, title: string, action: proc(mt: MachineType)): Menu =
  var menu = newMenu(mv, title)
  for cat, contents in pairs(machineTypesByCategory):
    (proc =
      let cat = cat
      let contents = contents
      var item = newMenuItem(cat) do():
        var menu = newMenu(mv, cat)
        for mtype in contents:
          (proc =
            let mtype = mtype
            var item = newMenuItem(mtype.name, proc() =
              action(mtype)
              popMenu()
            )
            menu.items.add(item)
          )()
        popMenu()
        pushMenu(menu)
      menu.items.add(item)
    )()
  return menu

method draw*(self: LayoutView) =
  cls()

  when true:
    setColor(1)
    line(0, screenHeight div 2, screenWidth, screenHeight div 2)
    for x in 1..<sampleBuffer.len:
      if x > screenWidth:
        break
      let y0 = (sampleBuffer[x-1] * 64).int + screenHeight div 2
      let y1 = (sampleBuffer[x] * 64).int + screenHeight div 2
      setColor(if abs(sampleBuffer[x-1]) > 1.0: 2 else: 1)
      line(x-1,y0,x,y1)

  setCamera(camera)

  var mv = mouse() + camera

  if connecting and currentMachine != nil:
    setColor(1)
    line(currentMachine.pos, mv)
  elif binding and currentMachine != nil:
    setColor(4)
    line(currentMachine.pos, mv)

  # draw connections
  for machine in mitems(machines):
    for input in mitems(machine.inputs):
      # TODO: find nearest points on AABBs
      # TODO: use nice bezier splines for connections

      let power = if input.machine.mute: 0.0 else: abs(input.machine.outputSamples[input.output]) * input.gain
      setColor(if power <= 0.0001: 1 elif power <= 0.01: 3 elif power < 1.0: 11 else: 8)
      line(input.machine.pos, machine.pos)
      let mid = (input.machine.pos + machine.pos) / 2.0
      setColor(6)
      trifill(rotatedPoly(mid, arrowVerts, (machine.pos - input.machine.pos).angle))
      setColor(if input.machine.mute: 1 else: 13)
      poly(rotatedPoly(mid, arrowVerts, (machine.pos - input.machine.pos).angle))

      # if the user is adjusting the gain, draw the gain amount
      if adjustingInput == addr(input):
        setColor(7)
        printShadowC(adjustingInput[].gain.linearToDb.formatFloat(ffDecimal, 2) & " Db", mid.x.int, mid.y.int + 4)

    for i,binding in mpairs(machine.bindings):
      if not machine.hideBindings:
        if binding.machine != nil:
          setColor(if machine == currentMachine: 4 else: 2)
          line(binding.machine.pos, machine.pos)

          let mid = (machine.pos + binding.machine.pos) / 2.0
          if machine == currentMachine:
            circfill(mid.x, mid.y, 4)
            setColor(0)
            printc($i,mid.x + 1,mid.y - 2)
          else:
            setColor(14)
            trifill(rotatedPoly(mid, arrowVerts, (binding.machine.pos - machine.pos).angle))
            setColor(2)
            poly(rotatedPoly(mid, arrowVerts, (binding.machine.pos - machine.pos).angle))

  # draw boxes
  for machine in mitems(machines):
    machine.drawBox()
    if machine == currentMachine:
      setColor(6)
      rect(machine.getAABB().expandAABB(2.0))

  setCamera()
  setColor(1)
  if self.name != nil:
    print(self.name, 1, 1)
  printr("layout", screenWidth - 1, 1)


method event*(self: LayoutView, event: Event): bool =
  let ctrl = ctrl()
  if stolenInput != nil:
    var (handled,keep) = stolenInput.event(event)
    if not keep:
      stolenInput = nil
    if handled:
      return true

  case event.kind:
  of MouseButtonDown:
    let mv = intPoint2d(event.button.x, event.button.y) + camera
    case event.button.button:
    of 1:
      # left click, check for machines under cursor
      for machine in mitems(machines):
        if pointInAABB(mv, machine.getAABB().expandAABB(2.0)):
          if ctrl and currentMachine != nil:
            swapMachines(currentMachine, machine)
          else:
            # handle machines that steal input
            if machine.handleClick(mv):
              stolenInput = machine
              return true
            currentMachine = machine
            if event.button.clicks == 2:
              # switch to machineview
              currentView = currentMachine.getMachineView()
            else:
              dragging = true
          return true
      # didn't click on a machine, maybe a gain control?
      for machine in mitems(machines):
        for input in mitems(machine.inputs):
          let mid = (input.machine.pos + machine.pos) / 2.0
          if pointInAABB(mv, mid.getAABB(4.0)):
            adjustingInput = addr(input)
            relmouse(true)
            return true
      # clicked on nothing
      currentMachine = nil
    of 2:
      panning = true
      discard captureMouse(true)
      return true
    of 3:
      # right click
      for machine in mitems(machines):
        if pointInAABB(mv, machine.getAABB().expandAABB(2.0)):
          currentMachine = machine
          if currentMachine.nOutputs > 0:
            connecting = true
            binding = false
          elif currentMachine.nBindings > 0:
            binding = true
            connecting = false
          return true

      # they didn't right click on a machine, check other stuff
      # check if it was a connection midpoint

      for machine in mitems(machines):
        for i,input in machine.inputs:
          let mid = (input.machine.pos + machine.pos) / 2.0
          var machine = machine
          if pointInAABB(mv, mid.getAABB(4.0)):
            var menu = newMenu(mv + -camera, "connection")
            menu.items.add(newMenuItem("disconnect", proc() =
              disconnectMachines(input.machine, machine)
              popMenu()
            ))
            menu.items.add(newMenuItem("insert", proc() =
              pushMenu(self.addMachineMenu(menu.pos, "insert machine") do(mtype: MachineType):
                # TODO: make sure it can be inserted here
                var m = mtype.factory()
                echo "inserting ", mtype.name
                m.pos = mv
                pauseAudio(1)
                withLock machineLock:
                  machines.add(m)
                self.currentMachine = m
                # connect it
                if connectMachines(m, machine):
                  if connectMachines(input.machine, m, input.gain):
                    disconnectMachines(input.machine, machine)
                  else:
                    echo "failed to connect: ", machine.name, " and ", m.name
                    discard machines.pop()
                else:
                  echo "failed to connect: ", m.name, " and ", input.machine.name
                  discard machines.pop()
                pauseAudio(0)
                popMenu()
                popMenu()
              )
            ))
            pushMenu(menu)
            return

        if not machine.hideBindings:
          for i,binding in machine.bindings:
            if binding.machine != nil:
              let mid = (machine.pos + binding.machine.pos) / 2.0
              if pointInAABB(mv, mid.getAABB(4.0)):
                # show all bindings between the two machines
                var sourceMachine = machine
                var targetMachine = binding.machine
                var menu = newMenu(mv + -camera, "remove bindings")
                for slot,binding in sourceMachine.bindings:
                  (proc() =
                    let slot = slot
                    if binding.machine == targetMachine:
                      var (voice, param) = binding.getParameter()
                      menu.items.add(newMenuItem($slot & " -> " & param.name, proc() =
                        removeBinding(sourceMachine, slot)
                        popMenu()
                      ))
                  )()
                pushMenu(menu)
                return

      pushMenu(self.addMachineMenu(mv + -camera, "add machine") do(mtype: MachineType):
        var m = mtype.factory()
        m.pos = mv
        pauseAudio(1)
        machines.add(m)
        self.currentMachine = m
        pauseAudio(0)
        popMenu()
      )
      return true
    else:
      discard

  of MouseMotion:
    let mv = intPoint2d(event.motion.x, event.motion.y) + camera
    if adjustingInput != nil:
      let shift = (getModState() and KMOD_SHIFT) != 0
      let move = if ctrl: 0.1 elif shift: 0.001 else: 0.01
      #adjustingInput[].gain = clamp(adjustingInput[].gain + (lastmv.y - mv.y) * move, 0.0, 10.0)
      let gain = adjustingInput[].gain
      adjustingInput[].gain = clamp(adjustingInput[].gain + (lastmv.y - mv.y) * move, 0.0, 10.0)
      lastmv = mv
      return true
    if dragging:
      currentMachine.pos += mv - lastmv
      lastmv = mv
      return true
    if panning:
      camera -= (mv - lastmv)
      return true
    lastmv = mv
    return true

  of MouseButtonUp:
    let mv = intPoint2d(event.button.x, event.button.y) + camera
    case event.button.button:
    of 1:
      dragging = false
      adjustingInput = nil
      relmouse(false)
      return true
    of 2:
      panning = false
      relmouse(false)
      discard captureMouse(false)
      return true
    of 3:
      relmouse(false)
      if currentMachine != nil and pointInAABB(mv, currentMachine.getAABB.expandAABB(2)):
        # open machine context menu
        pushMenu(currentMachine.getMenu(mv + -camera))
        connecting = false
        binding = false
        return true
      elif currentMachine != nil and connecting:
        # if there's a machine under cursor, connect them
        for machine in mitems(machines):
          if pointInAABB(mv, machine.getAABB):
            if machine != currentMachine:
              var targetMachine = machine
              var sourceMachine = currentMachine
              var selectedOutput = 0
              var selectedInput = 0

              if sourceMachine.nOutputs > 1:
                pushMenu(sourceMachine.getOutputMenu(mv + -camera) do(outputId: int):
                  selectedOutput = outputId
                  popMenu()
                  pushMenu(targetMachine.getInputMenu(mv + -self.camera) do(inputId: int):
                    selectedInput = inputId
                    discard connectMachines(sourceMachine, targetMachine, 1.0, selectedInput, selectedOutput)
                    popMenu()
                  )
                )
              elif targetMachine.nInputs > 1:
                pushMenu(targetMachine.getInputMenu(mv + -camera) do(inputId: int):
                  selectedInput = inputId
                  discard connectMachines(sourceMachine, targetMachine, 1.0, selectedInput, selectedOutput)
                  popMenu()
                )
              else:
                discard connectMachines(sourceMachine, targetMachine, 1.0, selectedInput, selectedOutput)
        connecting = false
      elif currentMachine != nil and binding:
        for machine in mitems(machines):
          if pointInAABB(mv, machine.getAABB):
            if machine != currentMachine:
              var target = machine
              var source = currentMachine
              if source.nBindings > 1:
                pushMenu(currentMachine.getSlotMenu(mv + -camera) do(slotId: int):
                  popMenu()
                  pushMenu(target.getParameterMenu(mv + -self.camera, "select param") do(paramId: int):
                    createBinding(source, slotId, target, paramId)
                    popMenu()
                  )
                )
              else:
                pushMenu(machine.getParameterMenu(mv + -camera, "select param") do(paramId: int):
                  createBinding(source, 0, target, paramId)
                  popMenu()
                )
        binding = false

      return true
    else:
      discard

  of KeyDown, KeyUp:
    let scancode = event.key.keysym.scancode
    let down = event.kind == KeyDown

    if down:
      case scancode:
      of SDL_SCANCODE_S:
        if down and ctrl:
          # TODO: ask for filename
          var menu = newMenu(mouse(), "save song")
          var te = newMenuItemText("name", if self.name == nil: "" else: self.name)
          menu.items.add(te)
          menu.items.add(newMenuItem("save") do():
            self.name = te.value
            if self.name in getLayouts():
              var menu = newMenu(point2d(0,0), "overwrite '" & self.name & "'?")
              menu.items.add(newMenuItem("no") do():
                popMenu()
                popMenu()
              )
              menu.items.add(newMenuItem("yes") do():
                saveLayout(self.name)
                popMenu()
                popMenu()
              )
              pushMenu(menu)
            else:
              saveLayout(self.name)
              popMenu()
          )
          pushMenu(menu)
      of SDL_SCANCODE_O:
        if down and ctrl:
          # TODO: show list of layout files
          var menu = newMenu(mouse(), "select file to load")

          for i,layout in getLayouts():
            (proc() =
              let layout = layout
              menu.items.add(newMenuItem(layout) do():
                loadLayout(layout)
                if self.name == nil:
                  self.name = layout
                popMenu()
              )
            )()
          pushMenu(menu)
      of SDL_SCANCODE_F2:
        if currentMachine != nil:
          currentView = currentMachine.getMachineView()
          return true
      of SDL_SCANCODE_2:
        if ctrl:
          if currentMachine != nil:
            currentView = currentMachine.getMachineView()
            return true
      of SDL_SCANCODE_HOME:
          camera = point2d(-screenWidth.float / 2.0, -screenHeight.float / 2.0)
          return true
      of SDL_SCANCODE_DELETE, SDL_SCANCODE_BACKSPACE:
        if currentMachine != nil and currentMachine != masterMachine:
          currentMachine.delete()
          currentMachine = nil
          return true
      else:
        discard
  else:
    discard

  return false

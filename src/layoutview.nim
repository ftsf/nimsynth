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

type LayoutView* = ref object of View
  name*: string
  currentMachine*: Machine
  dragging*: bool
  adjustingInput*: ptr Input
  connecting*: bool
  binding*: bool
  lastmv*: Point2d
  menu*: Menu
  stolenInput*: Machine
  camera*: Point2d

const arrowVerts = [
  point2d(-5,-3),
  point2d( 5, 0),
  point2d(-5, 3)
]

proc newLayoutView*(): LayoutView =
  result = new(LayoutView)
  result.camera = point2d(-screenWidth.float / 2.0, -screenHeight.float / 2.0)
  result.currentMachine = nil

proc addMachineMenu(self: LayoutView, mv: Point2d, title: string, action: proc(mt: MachineType)): Menu =
  var menu = newMenu(mv, title)
  menu.back = proc() =
    self.menu = nil
  for i in 0..machineTypes.high:
    (proc =
      let mtype = machineTypes[i]
      var item = newMenuItem(mtype.name, proc() =
        action(mtype)
      )
      menu.items.add(item)
    )()
  return menu

method draw*(self: LayoutView) =
  cls()

  when true:
    setColor(1)
    line(0, screenHeight div 2, screenWidth, screenHeight div 2)
    setColor(1)
    for x in 1..<sampleBuffer.len:
      if x > screenWidth:
        break
      let y0 = (sampleBuffer[x-1] * 64).int + screenHeight div 2
      let y1 = (sampleBuffer[x] * 64).int + screenHeight div 2
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

      setColor(1)
      line(input.machine.pos, machine.pos)
      let mid = (input.machine.pos + machine.pos) / 2.0
      setColor(6)
      trifill(rotatedPoly(mid, arrowVerts, (machine.pos - input.machine.pos).angle))
      setColor(1)
      poly(rotatedPoly(mid, arrowVerts, (machine.pos - input.machine.pos).angle))

      # if the user is adjusting the gain, draw the gain amount
      if adjustingInput == addr(input):
        setColor(7)
        printShadowC(adjustingInput[].gain.formatFloat(ffDecimal, 2), mid.x.int, mid.y.int + 4)

    for i,binding in mpairs(machine.bindings):
      if not machine.hideBindings:
        if binding.machine != nil:
          setColor(if machine == currentMachine: 4 else: 5)
          line(binding.machine.pos, machine.pos)
          if machine == currentMachine:
            let mid = (machine.pos + binding.machine.pos) / 2.0
            circfill(mid.x, mid.y, 4)
            setColor(0)
            printc($i,mid.x + 1,mid.y - 2)

  # draw boxes
  for machine in mitems(machines):
    machine.drawBox()
    if machine == currentMachine:
      setColor(6)
      rect(machine.getAABB().expandAABB(2.0))

  if menu != nil:
    menu.draw()

  spr(20, mv.x, mv.y)

  setCamera()
  setColor(1)
  if self.name != nil:
    print(self.name, 1, 1)
  printr("layout", screenWidth - 1, 1)

method key*(self: LayoutView, key: KeyboardEventPtr, down: bool): bool =
  if menu != nil:
    if menu.key(key, down):
      return true

  let scancode = key.keysym.scancode
  let shift = (getModState() and KMOD_SHIFT) != 0
  let ctrl = (getModState() and KMOD_CTRL) != 0

  if down:
    case scancode:
    of SDL_SCANCODE_S:
      if down and ctrl:
        # TODO: ask for filename
        self.menu = newMenu(point2d(0,0), "save layout")
        self.menu.back = proc() =
          self.menu = nil
        var te = newMenuItemText("name", if self.name == nil: "" else: self.name)
        self.menu.items.add(te)
        self.menu.items.add(newMenuItem("save") do():
          self.name = te.value
          if self.name in getLayouts():
            self.menu = newMenu(point2d(0,0), "overwrite '" & self.name & "'?")
            self.menu.back = proc() =
              self.menu = nil
            self.menu.items.add(newMenuItem("no") do():
              self.menu = nil
            )
            self.menu.items.add(newMenuItem("yes") do():
              saveLayout(self.name)
              self.menu = nil
            )
          else:
            saveLayout(self.name)
            self.menu = nil
        )
    of SDL_SCANCODE_O:
      if down and ctrl:
        # TODO: show list of layout files
        self.menu = newMenu(point2d(0,0), "select file to load")
        self.menu.back = proc() =
          self.menu = nil

        for i,layout in getLayouts():
          (proc() =
            let layout = layout
            self.menu.items.add(newMenuItem(layout) do():
              loadLayout(layout)
              if self.name == nil:
                self.name = layout
              self.menu = nil
            )
          )()
    of SDL_SCANCODE_F2:
      if currentMachine != nil:
        currentView = currentMachine.getMachineView()
        return true
    of SDL_SCANCODE_HOME:
        camera = point2d(-screenWidth.float / 2.0, -screenHeight.float / 2.0)
        return true
    of SDL_SCANCODE_INSERT:
      if currentMachine != nil:
        recordMachine = currentMachine
      else:
        recordMachine = nil
    of SDL_SCANCODE_DELETE:
      if currentMachine != nil and currentMachine != masterMachine:
        currentMachine.delete()
        currentMachine = nil
        return true
    else:
      discard

  return false

method update*(self: LayoutView, dt: float) =
  var mv = mouse() + camera

  let ctrl = (getModState() and KMOD_CTRL) != 0

  if menu != nil:
    menu.handleMouse(mv)

  if stolenInput != nil:
    stolenInput.layoutUpdate(self, dt)

  if mousebtn(2):
    camera -= mv - lastmv
    return

  # left click to select and move machines
  if mousebtnp(0):
    for machine in mitems(machines):
      if pointInAABB(mv, machine.getAABB()):
        if machine.handleClick(mv):
          stolenInput = machine
          return
        else:
          if ctrl and currentMachine != nil:
            swapMachines(currentMachine, machine)
            return
          else:
            currentMachine = machine
            dragging = true
            return
        return
    # check for adjusting input gain
    for machine in mitems(machines):
      for input in mitems(machine.inputs):
        let mid = (input.machine.pos + machine.pos) / 2.0
        if pointInAABB(mv, mid.getAABB(4.0)):
          adjustingInput = addr(input)
          relmouse(true)
          return
    # clicked on nothing
    currentMachine = nil


  if not mousebtn(0):
    dragging = false
    adjustingInput = nil
    relmouse(false)

  # right click drag to create connections, or delete them
  if mousebtnp(1):
    var targetMachine: Machine = nil
    for machine in mitems(machines):
      if pointInAABB(mv, machine.getAABB()):
        currentMachine = machine
        targetMachine = machine
        if currentMachine.nOutputs > 0:
          connecting = true
          binding = false
          return
        if currentMachine.nBindings > 0:
          binding = true
          connecting = false
          return
        break
    if targetMachine == nil:
      # they didn't right click on a machine, check other stuff
      # check if it was a connection midpoint
      for machine in mitems(machines):
        for i,input in machine.inputs:
          let mid = (input.machine.pos + machine.pos) / 2.0
          var machine = machine
          if pointInAABB(mv, mid.getAABB(4.0)):
            self.menu = newMenu(mv, "connection")
            self.menu.back = proc() =
              self.menu = nil
            self.menu.items.add(newMenuItem("disconnect", proc() =
              disconnectMachines(input.machine, machine)
              self.menu = nil
            ))
            self.menu.items.add(newMenuItem("insert", proc() =
              self.menu = self.addMachineMenu(self.menu.pos, "insert machine") do(mtype: MachineType):
                # TODO: make sure it can be inserted here
                var m = mtype.factory()
                echo "inserting ", mtype.name
                m.pos = mv
                pauseAudio(1)
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
                self.menu = nil
            ))
            return
        for i,binding in machine.bindings:
          if binding.machine != nil:
            let mid = (machine.pos + binding.machine.pos) / 2.0
            if pointInAABB(mv, mid.getAABB(4.0)):
              # show all bindings between the two machines
              var sourceMachine = machine
              var targetMachine = binding.machine
              self.menu = newMenu(mv, "bindings")
              self.menu.back = proc() =
                self.menu = nil
              for slot,binding in sourceMachine.bindings:
                (proc() =
                  let slot = slot
                  if binding.machine == targetMachine:
                    var (voice, param) = binding.getParameter()
                    self.menu.items.add(newMenuItem($slot & ": " & param.name, proc() =
                      removeBinding(sourceMachine, slot)
                      self.menu = nil
                    ))
                )()
              return
      # open new machine menu
      self.menu = addMachineMenu(mv, "add machine") do(mtype: MachineType):
        var m = mtype.factory()
        m.pos = mv
        pauseAudio(1)
        machines.add(m)
        self.currentMachine = m
        pauseAudio(0)
        self.menu = nil
      return

  if not mousebtn(1) and (connecting or binding) and currentMachine != nil:
    # release right click drag, attempt to create connection
    # check if a connection was made
    var sourceMachine = currentMachine

    for machine in mitems(machines):
      if pointInAABB(mv, machine.getAABB()):
        if machine == sourceMachine:
          self.menu = newMenu(mv, "machine")
          self.menu.back = proc() =
            self.menu = nil
          var machine = machine
          self.menu.items.add(newMenuItem("rename", proc() =
            self.menu = newMenu(mv, "rename")
            self.menu.back = proc() =
              self.menu = nil
            var te = newMenuItemText("name", machine.name)
            self.menu.items.add(te)
            self.menu.items.add(newMenuItem("rename") do():
              machine.name = te.value
              self.menu = nil
            )
          ))
          self.menu.items.add(newMenuItem("show bindings", proc() =
            sourceMachine.hideBindings = not sourceMachine.hideBindings
            self.menu = nil
          ))
          self.menu.items.add(newMenuItem("delete", proc() =
            sourceMachine.delete()
            self.menu = nil
          ))
          discard
        else:
          var targetMachine = machine
          if binding:
            # open binding menu
            # if source machine has multiple bindings, select which one
            if sourceMachine.nBindings > 1:
              self.menu = newMenu(mv, "select slot")
              self.menu.back = proc() =
                self.menu = nil
              for i in 0..sourceMachine.nBindings-1:
                (proc() =
                  let slotId = i
                  var binding = addr(sourceMachine.bindings[slotId])
                  var str: string
                  if binding.machine != nil:
                    var (voice, param) = binding.machine.getParameter(binding.param)
                    str = binding.machine.name & ": " & (if voice >= 0: ($voice & ": ") else: "") & param.name
                  else:
                    str = " - "

                  self.menu.items.add(
                    newMenuItem($(slotId+1) & ": " & str) do():
                      self.menu = targetMachine.getParameterMenu(mv, "select param") do(paramId: int):
                        sourceMachine.createBinding(slotId, targetMachine, paramId)
                        self.menu = nil
                  )
                )()
            else:
              var binding = addr(sourceMachine.bindings[0])
              self.menu = targetMachine.getParameterMenu(mv, "select param") do(paramId: int):
                sourceMachine.createBinding(0, targetMachine, paramId)
                self.menu = nil
          elif connecting:
            # connecting machines
            if sourceMachine.nOutputs == 1 and targetMachine.nInputs == 1:
              discard connectMachines(sourceMachine, targetMachine)
            else:
              if sourceMachine.nOutputs > 1:
                # open output select menu
                self.menu = newMenu(mv, "select output")
                self.menu.back = proc() =
                  self.menu = nil
                self.menu.back = proc() =
                  self.menu = nil
                for i in 0..sourceMachine.nOutputs-1:
                  (proc() =
                    let outputId = i
                    self.menu.items.add(newMenuItem($(outputId + 1) & ": " & sourceMachine.getOutputName(outputId) ) do():
                      if targetMachine.nInputs > 1:
                        # open input select menu
                        self.menu = newMenu(mv, "select input")
                        self.menu.back = proc() =
                          self.menu = nil
                        for j in 0..targetMachine.nInputs-1:
                          (proc() =
                            let inputId = j
                            self.menu.items.add(newMenuItem($(inputId + 1) & ": " & targetMachine.getInputName(inputId)) do():
                              discard connectMachines(sourceMachine, targetMachine, 1.0, inputId, outputId)
                              self.menu = nil
                            )
                          )()
                      else:
                        discard connectMachines(sourceMachine, targetMachine, 1.0, 0, outputId)
                        self.menu = nil
                    )
                  )()
              else:
                # open input select menu
                self.menu = newMenu(mv, "select input")
                self.menu.back = proc() =
                  self.menu = nil
                for j in 0..targetMachine.nInputs-1:
                  (proc() =
                    let inputId = j
                    self.menu.items.add(newMenuItem($(inputId + 1) & ": " & targetMachine.getInputName(inputId)) do():
                      discard connectMachines(sourceMachine, targetMachine, 1.0, inputId, 0)
                      self.menu = nil
                    )
                  )()
    connecting = false
    binding = false

  if adjustingInput != nil:
    let shift = (getModState() and KMOD_SHIFT) != 0
    let move = if ctrl: 0.1 elif shift: 0.001 else: 0.01
    adjustingInput[].gain = clamp(adjustingInput[].gain + (lastmv.y - mv.y) * move, 0.0, 10.0)
  elif dragging and currentMachine != nil:
    currentMachine.pos += (mv - lastmv)
  elif dragging and currentMachine != nil:
    currentMachine.pos += (mv - lastmv)

  lastmv = mv

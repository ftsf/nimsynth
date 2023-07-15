import sugar
import math
import strutils
import sequtils

import common
import nico
import nico/vec
import util

import core/basemachine
import ui/machineview
import ui/menu
import ui/paramwindow

import core/ringbuffer

### Layout View
# Draw a graph of the machine connections

{.this:self.}

type LayoutView* = ref object of View
  currentMachine*: Machine
  keyboardMachine*: Machine
  dragging*: bool
  adjustingInput*: ptr Input
  connecting*: bool
  binding*: bool
  lastmv*: Vec2f
  stolenInput*: Machine
  panning: bool
  showParams: bool
  shift: bool
  ctrl: bool

const arrowVerts = [
  vec2f(-3,-3),
  vec2f( 3, 0),
  vec2f(-3, 3)
]

proc newLayoutView*(): LayoutView =
  result = new(LayoutView)
  result.camera = vec2f(screenWidth.float32 / 2.0, screenHeight.float32 / 2.0)
  result.currentMachine = nil
  result.keyboardMachine = nil
  result.windows = @[]

import tables

proc addMachineMenu(self: LayoutView, mv: Vec2f, title: string, action: proc(mt: MachineType)): Menu =
  var menu = newMenu(mv, title)
  machineTypesByCategory.sort((x,y) => cmp(x[0], y[0]))
  for cat, contents in pairs(machineTypesByCategory):
    closureScope:
      var cat = cat
      var contents = contents
      var catitem = newMenuItem(cat) do():
        var menu = newMenu(mv, cat)
        for mtype in contents:
          closureScope:
            var mtype = mtype
            var mtypeName = mtype.name
            var item = newMenuItem(mtypeName, proc() =
              action(mtype)
              if not self.shift:
                popMenu()
            )
            menu.items.add(item)
        popMenu()
        pushMenu(menu)
      menu.items.add(catitem)
  return menu

method draw*(self: LayoutView) =
  cls()

  if sampleMachine != nil:
    # draw oscilliscope
    setColor(1)
    line(0, screenHeight div 2, screenWidth, screenHeight div 2)

    for x in 1..<screenWidth:
      let s0 = (oscilliscopeBuffer.length div screenWidth) * (x - 1)
      let s1 = (oscilliscopeBuffer.length div screenWidth) * x
      let y0 = (oscilliscopeBuffer[s0] * 64.0).int + screenHeight div 2
      let y1 = (oscilliscopeBuffer[s1] * 64.0).int + screenHeight div 2

      setColor(if abs(oscilliscopeBuffer[s1]) > 1.0: 2 else: 3)
      line(x-1,y0,x,y1)

  setCamera(-camera.x, -camera.y)

  let mv = mouseVec() - camera

  if connecting and currentMachine != nil:
    setColor(1)
    line(currentMachine.pos, mv)
  elif binding and currentMachine != nil:
    setColor(4)
    line(currentMachine.pos, mv)

  # draw connections
  for machine in machines:
    for input in machine.inputs.mitems():
      # TODO: find nearest points on AABBs
      # TODO: use nice bezier splines for connections

      let power = if input.machine.disabled: 0.0 else: abs(input.machine.outputSamples[input.output]) * input.gain
      setColor(if power <= 0.0001: 1 elif power <= 0.01: 3 elif power < 1.0: 11 else: 8)
      line(input.machine.pos, machine.pos)
      let mid = (input.machine.pos + machine.pos) / 2.0
      setColor(6)
      let rp = rotatedPoly(mid, arrowVerts, (machine.pos - input.machine.pos).angle)
      trifill(rp)

      if machine.nInputs > 1:
        setColor(5)
        let dir = (machine.pos - input.machine.pos).normalized
        let mp = mid + dir * 8
        printShadowC($(input.inputId+1), mp.x.int, mp.y.int - 4, 1)

      # if the user is adjusting the gain, draw the gain amount
      if adjustingInput == addr(input):
        setColor(7)
        printShadowC(adjustingInput[].gain.linearToDb.formatFloat(ffDecimal, 2) & " Db", mid.x.int, mid.y.int + 4)

    for i,binding in mpairs(machine.bindings):
      if not machine.hideBindings:
        if binding.machine != nil:
          setColor(if machine.disabled: 1 elif machine == currentMachine: 4 else: 2)
          line(binding.machine.pos, machine.pos)

          let mid = (machine.pos + binding.machine.pos) / 2.0
          if machine == currentMachine:
            circfill(mid.x, mid.y, 4)
            setColor(0)
            printc($(i+1),mid.x + 1,mid.y - 2)
          else:
            setColor(14)
            trifill(rotatedPoly(mid, arrowVerts, (binding.machine.pos - machine.pos).angle))

  # draw boxes
  for machine in machines:
    machine.drawBox()
    if machine == currentMachine:
      setColor(7)
      rrect(machine.getAABB().expandAABB(2.0))

  for w in windows:
    w.draw()

  setCamera()
  setColor(1)
  if layoutName != "":
    print(layoutName, 1, 1)
  printr("layout", screenWidth - 1, 1)

proc handleStolenEvent(self: LayoutView, event: Event): bool =
  var (handled,keep) = stolenInput.event(event, camera)
  if not keep:
    stolenInput = nil
  return handled

proc getMachineAtPos(self: LayoutView, pos: Vec2f): Machine =
  for machine in machines:
    if pointInAABB(pos, machine.getAABB):
      return machine
  return nil

proc tryConnect*(self: LayoutView, sourceMachine: Machine, targetMachine: Machine) =
  var selectedOutput = 0
  var selectedInput = 0

  if sourceMachine.nOutputs > 1:
    pushMenu(sourceMachine.getOutputMenu(mouseVec()) do(outputId: int):
      selectedOutput = outputId
      popMenu()
      pushMenu(targetMachine.getInputMenu(mouseVec()) do(inputId: int):
        selectedInput = inputId
        discard connectMachines(sourceMachine, targetMachine, 1.0, selectedInput, selectedOutput)
        popMenu()
      )
    )
  elif targetMachine.nInputs > 1:
    pushMenu(targetMachine.getInputMenu(mouseVec()) do(inputId: int):
      selectedInput = inputId
      discard connectMachines(sourceMachine, targetMachine, 1.0, selectedInput, selectedOutput)
      popMenu()
    )
  else:
    discard connectMachines(sourceMachine, targetMachine, 1.0, selectedInput, selectedOutput)

proc tryBind*(self: LayoutView, sourceMachine: Machine, targetMachine: Machine) =
  if sourceMachine.nBindings > 1:
    # binding menu
    pushMenu(currentMachine.getSlotMenu(mouseVec()) do(slotId: int):
      let mv = mouseVec()
      proc bindParamMenu(slotId: int) =
        pushMenu(targetMachine.getBindParameterMenu(mv, "slot " & $(slotId+1) & " -> ", sourceMachine, sourceMachine.bindings[slotId]) do(paramId: int):
          createBinding(sourceMachine, slotId, targetMachine, paramId)
          popMenu()
          if self.shift:
            popMenu()
            if slotId + 1 < sourceMachine.nBindings:
              bindParamMenu(slotId + 1)
          else:
            popMenu()
        )
      bindParamMenu(slotId)
    )
  else:
    # only one binding slot, no menu needed
    pushMenu(targetMachine.getParameterMenu(mouseVec(), "select input param") do(paramId: int):
      createBinding(sourceMachine, 0, targetMachine, paramId)
      popMenu()
    )

method event*(self: LayoutView, event: Event): bool =
  for i in countdown(windows.high,windows.low):
    var window = windows[i]
    if window.event(event):
      return true

  windows.keepItIf(it.close == false)

  if stolenInput != nil:
    if handleStolenEvent(event):
      return true

  case event.kind:
  of ekMouseButtonDown:
    let mv = vec2f(event.x, event.y) - camera
    case event.button:
    of 1:
      # left click, check for machines under cursor
      for machine in mitems(machines):
        if pointInAABB(mv, machine.getAABB().expandAABB(2.0)):
          if self.ctrl and currentMachine != nil:
            swapMachines(currentMachine, machine)
          elif self.shift:
            currentMachine = machine
            if currentMachine.nOutputs > 0:
              connecting = true
              binding = false
            elif currentMachine.nBindings > 0:
              binding = true
              connecting = false
          else:
            # handle machines that steal input
            if machine.handleClick(mv):
              stolenInput = machine
              if handleStolenEvent(event):
                return true

            currentMachine = machine
            if currentMachine.useKeyboard:
              keyboardMachine = currentMachine
            if event.clicks == 2:
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
            return true
      # clicked on nothing
      currentMachine = nil

    of 2:
      # middle click = pan layout
      panning = true
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
            var menu = newMenu(mouseVec(), "connection")
            menu.items.add(newMenuItem("disconnect", proc() =
              disconnectMachines(input.machine, machine)
              popMenu()
            ))
            menu.items.add(newMenuItem("insert", proc() =
              pushMenu(self.addMachineMenu(menu.pos, "insert machine") do(mtype: MachineType):
                # TODO: make sure it can be inserted here
                let nextMachine = machine
                let prevMachine = input.machine
                let newMachine = mtype.factory()
                echo "inserting ", mtype.name, " between ", prevMachine.name, " and ", nextMachine.name
                newMachine.pos = mv
                self.currentMachine = newMachine
                # connect it
                if connectMachines(newMachine, nextMachine, input.gain, input.inputId):
                  if connectMachines(prevMachine, newMachine):
                    disconnectMachines(prevMachine, nextMachine)
                  else:
                    echo "failed to connect: ", prevMachine.name, " and ", newMachine.name
                    discard machines.pop()
                else:
                  echo "failed to connect: ", newMachine.name, " and ", nextMachine.name
                  discard machines.pop()
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
                var menu = newMenu(mouseVec(), "remove bindings")
                for slot,binding in sourceMachine.bindings:
                  (proc() =
                    let slot = slot
                    if binding.machine == targetMachine:
                      var (voice, param) = binding.getParameter()
                      menu.items.add(newMenuItem($(slot+1) & " -> " & (if voice != -1: $(voice+1) & ": " else: "") & param.name, proc() =
                        removeBinding(sourceMachine, slot)
                        popMenu()
                      ))
                  )()
                menu.items.add(newMenuItem(""))
                menu.items.add(newMenuItem("remove all") do():
                  for slot,binding in sourceMachine.bindings:
                    if binding.machine == targetMachine:
                      removeBinding(sourceMachine, slot)
                  popMenu()
                )
                pushMenu(menu)
                return

      pushMenu(self.addMachineMenu(mouseVec(), "add machine") do(mtype: MachineType):
        var m = mtype.factory()
        if m != nil:
          m.pos = mv
          machines.add(m)
          self.currentMachine = m
          if m.useKeyboard:
            keyboardMachine = m
      )
      return true
    else:
      discard

  of ekMouseMotion:
    let mv = vec2f(event.x, event.y) - camera
    if adjustingInput != nil:
      let move = if ctrl: 0.1 elif shift: 0.001 else: 0.01
      #adjustingInput[].gain = clamp(adjustingInput[].gain + (lastmv.y - mv.y) * move, 0.0, 10.0)
      let gain = adjustingInput[].gain
      adjustingInput[].gain = clamp(adjustingInput[].gain + (lastmv.y - mv.y) * move, 0.0, 10.0)
      lastmv = mv
      return false
    if dragging:
      currentMachine.pos += mv - lastmv
      lastmv = mv
      return false
    if panning:
      camera += mouserelVec()
      return false
    lastmv = mv
    return false

  of ekMouseButtonUp:
    let mv = vec2f(event.x, event.y) - camera
    case event.button:
    of 1:
      dragging = false
      adjustingInput = nil
      if currentMachine != nil and connecting:
        # if there's a machine under cursor, connect them
        let machine = getMachineAtPos(mv)
        if machine != nil:
          self.tryConnect(currentMachine, machine)
        connecting = false
      elif currentMachine != nil and binding:
        let machine = getMachineAtPos(mv)
        if machine != nil:
          self.tryBind(currentMachine, machine)
        binding = false
      return true
    of 2:
      panning = false
      return true
    of 3:
      if currentMachine != nil and pointInAABB(mv, currentMachine.getAABB.expandAABB(2)):
        # open machine context menu
        pushMenu(currentMachine.getMenu(mouseVec()))
        connecting = false
        binding = false
        return true
      elif currentMachine != nil and connecting:
        # if there's a machine under cursor, connect them
        let machine = getMachineAtPos(mv)
        if machine != nil:
          self.tryConnect(currentMachine, machine)
        connecting = false
      elif currentMachine != nil and binding:
        let machine = getMachineAtPos(mv)
        if machine != nil:
          self.tryBind(currentMachine, machine)
        binding = false
      return true
    else:
      discard

  of ekKeyDown, ekKeyUp:
    let scancode = event.scancode
    let down = event.kind == ekKeyDown

    if event.repeat == 0 and event.keycode == K_LSHIFT or event.keycode == K_RSHIFT:
      self.shift = down

    if event.repeat == 0 and event.keycode == K_LCTRL or event.keycode == K_RCTRL:
      self.ctrl = down

    if down:
      case scancode:
      of SCANCODE_S:
        if down and ctrl:
          # TODO: ask for filename
          var menu = newMenu(mouseVec(), "save song")
          var te = newMenuItemText("name", layoutName)
          menu.items.add(te)
          menu.items.add(newMenuItem("save") do():
            if te.value in getLayouts():
              var menu = newMenu(vec2f(0,0), "overwrite '" & te.value & "'?")
              menu.items.add(newMenuItem("no") do():
                popMenu()
                popMenu()
              )
              menu.items.add(newMenuItem("yes") do():
                layoutName = te.value
                saveLayout(layoutName)
                popMenu()
                popMenu()
              )
              pushMenu(menu)
            else:
              layoutName = te.value
              saveLayout(layoutName)
              popMenu()
          )
          pushMenu(menu)
      of SCANCODE_O:
        if down and ctrl:
          # TODO: show list of layout files
          var menu = newMenu(mouseVec(), "select file to load")

          for i,layout in getLayouts():
            (proc() =
              let layout = layout
              menu.items.add(newMenuItem(layout) do():
                loadLayout(layout)
                popMenu()
              )
            )()
          pushMenu(menu)
      of SCANCODE_F2:
        if currentMachine != nil:
          currentView = currentMachine.getMachineView()
          return true
      of SCANCODE_2:
        if ctrl:
          if currentMachine != nil:
            currentView = currentMachine.getMachineView()
            return true
      of SCANCODE_HOME:
          camera = vec2f(-screenWidth.float32 / 2.0, -screenHeight.float32 / 2.0)
          return true
      of SCANCODE_DELETE, SCANCODE_BACKSPACE:
        if currentMachine != nil and currentMachine != masterMachine:
          currentMachine.delete()
          if keyboardMachine == currentMachine:
            keyboardMachine = nil
          currentMachine = nil
          return true
      of SCANCODE_PAGEUP:
        oscilliscopeBufferSize += 100
        oscilliscopeBuffer = newRingBuffer[float32](oscilliscopeBufferSize)
        return true
      of SCANCODE_PAGEDOWN:
        oscilliscopeBufferSize -= 100
        if oscilliscopeBufferSize < screenWidth:
          oscilliscopeBufferSize = screenWidth
        oscilliscopeBuffer = newRingBuffer[float32](oscilliscopeBufferSize)
        return true
      of SCANCODE_SPACE:
        oscilliscopeFreeze = not oscilliscopeFreeze
        return true
      of SCANCODE_PERIOD:
        if currentMachine != nil:
          let mv = mouseVec()
          var win = newParamWindow(currentMachine, (mv.x - camera.x).int, (mv.y - camera.y).int, 128, 64)
          win.view = self
          windows.add(win)
        return true
      else:
        discard

    if event.repeat == 0 and menuStack.len == 0:
      if keyboardMachine != nil:
        let note = keyToNote(event.keycode)
        if note != -3:
          if down:
            keyboardMachine.trigger(note)
          else:
            keyboardMachine.release(note)

  else:
    discard

  return false

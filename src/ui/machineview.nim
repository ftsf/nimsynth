import common
import nico
import nico/vec
import strutils
import util
import menu

### Machine View
# Draw a single machine's settings

{.this:self.}

type MachineView* = ref object of View
  machine*: Machine
  currentParam*: int
  dragging: bool
  clickPos: Vec2f
  scroll*: int

const maxPatchSlots = 64

const paramNameWidth* = 64

proc newMachineView*(machine: Machine): MachineView =
  result = new(MachineView)
  result.machine = machine

proc drawParams*(self: MachineView, x,y,w,h: int) =
  var nParams = machine.getParameterCount()
  var yv = y
  scroll = clamp(scroll,0,nParams-1)
  let startParam = clamp(scroll, 0, nParams-1)
  let sliderWidth = w - 64 - 6
  if nParams > 0:
    var i = startParam
    while yv < h and i < nParams:
      var (voice, param) = machine.getParameter(i)

      if param.separator:
        setColor(5)
        line(x,yv,x+paramNameWidth + sliderWidth,yv)
        yv += 4

      setColor(if i == currentParam: 8 elif param.fav: 10 else: 7)
      print((if voice > -1: $(voice+1) & ": " else: "") & param.name, x, yv)
      printr(param[].valueString(param.value), x + 63, yv)
      var range = (param.max - param.min)
      if range == 0.0:
        range = 1.0
      setColor(1)
      # draw slider background
      rectfill(x + paramNameWidth, yv, x + paramNameWidth + sliderWidth, yv+4)

      # draw slider fill
      setColor(if i == currentParam: 8 else: 6)

      let zeroX = x + paramNameWidth + (sliderWidth.float32 * clamp(invLerp(param.min, param.max, 0.0), 0.0, 1.0)).int

      rectfill(zeroX, yv, x + paramNameWidth + (sliderWidth.float32 * invLerp(param.min, param.max, param.value)).int, yv+4)

      # draw default bar
      if param.kind != Note:
        setColor(7)
        let defaultX = x + paramNameWidth + (sliderWidth.float32 * invLerp(param.min, param.max, param.default)).int
        line(defaultX, yv, defaultX, yv+4)

      yv += 8
      i += 1

    # draw scrollbar
    block:
      setColor(1)
      rectfill(x + w - 4, y, x + w, y + h - 1)

      # handle
      setColor(13)
      let yStart = scroll.float32 / nParams.float32
      let yEnd = (scroll + nParams).float32 / nParams.float32
      rectfill(x + w - 4, y + (h.float32 * yStart).int, x + w, y + (h.float32 * yEnd).int)

      # current
      block:
        setColor(7)
        let yStart = currentParam.float32 / nParams.float32
        let yEnd = (currentParam+1).float32 / nParams.float32
        rectfill(x + w - 4, y + (h.float32 * yStart).int, x + w, y + (h.float32 * yEnd).int)

method draw*(self: MachineView) =
  let paramsOnScreen = (screenHeight div 8)
  cls()
  setColor(6)
  printr(machine.name, screenWidth - 1, 1)

  let paramWidth = screenWidth div 3 + paramNameWidth
  drawParams(1,1, paramWidth, screenHeight - 1)

  machine.drawExtraData(paramWidth + 4, 16, screenWidth - paramWidth - 4, screenHeight - 16 - 16)

proc updateParams*(self: MachineView, x,y,w,h: int) =
#  if mousebtn(0):
#  # drag to adjust value
#  if dragging:
#    var (voice, param) = machine.getParameter(currentParam)
#    param.value = lerp(param.min, param.max, clamp(invLerp(paramNameWidth.float32, paramNameWidth.float32 + sliderWidth.float32, mv.x), 0.0, 1.0))
#    if param.kind == Int or param.kind == Trigger:
#      param.value = param.value.int.float32
#    param.onchange(param.value, voice)
#else:
#  dragging = false
  discard


method update*(self: MachineView, dt: float32) =
  machine.updateExtraData(screenWidth div 3 + paramNameWidth, 16, screenWidth - 1, screenHeight - 1)
  updateParams(1,1, screenWidth div 3 + paramNameWidth, screenHeight - 1)

proc key*(self: MachineView, event: Event): bool =
  let scancode = event.scancode
  let keycode = event.keycode
  let ctrl = (event.mods and KMOD_CTRL) != 0
  let shift = (event.mods and KMOD_SHIFT) != 0

  let paramsOnScreen = (screenHeight div 8)

  let down = event.kind == ekKeyDown

  var globalParams = addr(machine.globalParams)
  var voiceParams =  addr(machine.voiceParams)
  var nParams = globalParams[].len + voiceParams[].len * machine.voices.len
  if down:
    case scancode:
    of SCANCODE_S:
      if ctrl and down:
        var patchName: string = ""
        var menu = newMenu(vec2f(0,0), "save patch")
        var te = newMenuItemText("name", patchName)
        menu.items.add(te)
        menu.items.add(newMenuItem("save") do():
          savePatch(self.machine, te.value)
          popMenu()
        )
        pushMenu(menu)
        return true
    of SCANCODE_O:
      if ctrl and down:
        var menu = newMenu(vec2f(0,0), "load patch")
        for patch in machine.getPatches():
          var patchName = patch
          (proc() =
            menu.items.add(newMenuItem(patchName) do():
              self.machine.loadPatch(patchName)
              popMenu()
            )
          )()
        pushMenu(menu)
        return true
    of SCANCODE_UP:
      currentParam -= 1
      if currentParam < 0:
        currentParam = nParams - 1
      return true
    of SCANCODE_DOWN:
      currentParam += 1
      if currentParam > nParams - 1:
        currentParam = 0
      return true
    of SCANCODE_LEFT, SCANCODE_RIGHT:
      var (voice, param) = machine.getParameter(currentParam)
      let range = param.max - param.min
      let dir = if scancode == SCANCODE_LEFT: -1.0 else: 1.0
      case param.kind:
      of Int, Trigger, Note, Bool:
        let move = if ctrl: (if param.kind == Note: 12.0 else: 10.0) else: 1.0
        param.value = clamp(param.value.int.float32 + move * dir, param.min, param.max)
      of Float:
        let move = if shift: 0.001 elif ctrl: 0.1 else: 0.01
        param.value = clamp(param.value + range * move * dir, param.min, param.max)

      if param.onchange != nil:
        param.onchange(param.value, voice)
      param[].trigger(voice)

      return true
    of SCANCODE_KP_PLUS, SCANCODE_EQUALS:
      machine.addVoice()
      return true
    of SCANCODE_KP_MINUS, SCANCODE_MINUS:
      machine.popVoice()
      return true
    of SCANCODE_SPACE:
      var (voice, param) = machine.getParameter(currentParam)
      param.fav = not param.fav
      return true

    else:
      discard

  # TODO: handle extra keys for the machine

  if event.repeat == 0:
    let note = keyToNote(event.keycode)
    if note != -3:
      if down:
        machine.trigger(note)
      else:
        machine.release(note)
  return false

method event*(self: MachineView, event: Event): bool =
  case event.kind:
  of ekMouseWheel:
    scroll -= event.ywheel
    return true
  of ekMouseButtonUp:
    case event.button:
    of 1:
      dragging = false
      return true
    else:
      discard
  of ekMouseButtonDown:
    case event.button:
    of 1:
      # check if they clicked on a param bar
      let mv = vec2f(event.x, event.y)
      if mv.x < screenWidth div 3 + paramNameWidth:
        if mv.x > screenWidth div 3 + paramNameWidth - 5:
          # scrollbar
          # TODO: adjust scroll based on click
          discard
        else:
          var y = 0
          let nParams = machine.getParameterCount()
          for i in scroll..nParams-1:
            var (voice, param) = machine.getParameter(i)
            if param.separator:
              y += 4
            if mv.y >= y and mv.y <= y + 7:
              currentParam = i
              dragging = true
              clickPos = mv
              return true
            y += 8
    of 3:
      # check if they clicked on a param bar
      # reset to default value
      let mv = vec2f(event.x, event.y)
      if mv.x < screenWidth div 3 + paramNameWidth:
        if mv.x > screenWidth div 3 + paramNameWidth - 5:
          discard
        else:
          var y = 0
          let nParams = machine.getParameterCount()
          for i in scroll..nParams-1:
            var (voice, param) = machine.getParameter(i)
            if param.separator:
              y += 4
            if mv.y >= y and mv.y <= y + 7:
              currentParam = i
              let (voice,param) = machine.getParameter(currentParam)
              param.value = param.default
              param.onchange(param.value, voice)
              return true
            y += 8
    else:
      discard
  of ekMouseMotion:
    if dragging:
      var (voice, param) = machine.getParameter(currentParam)
      let paramWidth = screenWidth div 3 + paramNameWidth
      let sliderWidth = paramWidth - 64 - 6
      if shift():
        # jump directly to value
        param.value = lerp(param.min, param.max, clamp(invLerp(paramNameWidth.float32, paramNameWidth.float32 + sliderWidth.float32, event.x.float32), 0.0, 1.0))
      else:
        # relative shift
        let range = param.max - param.min
        let ydist = event.y.float32 - clickPos.y
        let sensitivity = clamp(10.0 / abs(event.y.float32 - clickPos.y))
        let speed = (range / sliderWidth.float32) * sensitivity
        if ydist < 3:
          param.value = lerp(param.min, param.max, clamp(invLerp(paramNameWidth.float32, paramNameWidth.float32 + sliderWidth.float32, event.x.float32), 0.0, 1.0))
        else:
          param.value = clamp(param.value + event.xrel * speed, param.min, param.max)
      #if param.kind == Int or param.kind == Trigger:
      #  if param.value > 0:
      #    param.value = (param.value + 0.5).int.float32
      #  elif param.value < 0:
      #    param.value = (param.value - 0.5).int.float32
      #  else:
      #    param.value = param.value.int.float32
      param.onchange(param.value, voice)
      return false
  of ekKeyUp, ekKeyDown:
    return key(event)
  else:
    discard
  return false

proc getCurrentParam*(self: MachineView): (int, ptr Parameter) =
  return self.machine.getParameter(self.currentParam)

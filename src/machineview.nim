import common
import pico
import strutils
import util
import menu
import basic2d
import sdl2

### Machine View
# Draw a single machine's settings

{.this:self.}

type MachineView* = ref object of View
  machine*: Machine
  currentParam*: int
  dragging: bool
  scroll*: int

const maxPatchSlots = 64

const paramNameWidth = 64

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

      setColor(if i == currentParam: 8 else: 7)
      print((if voice > -1: $voice & ": " else: "") & param.name, x, yv)
      printr(param[].valueString(param.value), x + 63, yv)
      var range = (param.max - param.min)
      if range == 0.0:
        range = 1.0
      setColor(1)
      # draw slider background
      rectfill(x + paramNameWidth, yv, x + paramNameWidth + sliderWidth, yv+4)

      # draw slider fill
      setColor(if i == currentParam: 8 else: 6)

      let zeroX = x + paramNameWidth + sliderWidth.float * clamp(invLerp(param.min, param.max, 0.0), 0.0, 1.0)

      rectfill(zeroX, yv, x + paramNameWidth + sliderWidth.float * invLerp(param.min, param.max, param.value), yv+4)

      # draw default bar
      setColor(7)
      let defaultX = x + paramNameWidth + sliderWidth.float * invLerp(param.min, param.max, param.default)
      line(defaultX, yv, defaultX, yv+4)

      yv += 8
      i += 1

    # draw scrollbar
    block:
      setColor(1)
      rectfill(x + w - 4, y, x + w, y + h - 1)

      # handle
      setColor(13)
      let yStart = scroll.float / nParams.float
      let yEnd = (scroll + nParams).float / nParams.float
      rectfill(x + w - 4, y + h.float * yStart, x + w, y + h.float * yEnd)

      # current
      block:
        setColor(7)
        let yStart = currentParam.float / nParams.float
        let yEnd = (currentParam+1).float / nParams.float
        rectfill(x + w - 4, y + h.float * yStart, x + w, y + h.float * yEnd)



method draw*(self: MachineView) =
  let paramsOnScreen = (screenHeight div 8)
  cls()
  setColor(6)
  printr(machine.name, screenWidth - 1, 1)

  let paramWidth = screenWidth div 3 + paramNameWidth
  drawParams(1,1, paramWidth, screenHeight - 1)

  machine.drawExtraData(paramWidth + 4, 16, screenWidth - paramWidth - 4, screenHeight - 16)

proc updateParams*(self: MachineView, x,y,w,h: int) =
  discard
#if mousebtn(0):
#  # drag to adjust value
#  if dragging:
#    var (voice, param) = machine.getParameter(currentParam)
#    param.value = lerp(param.min, param.max, clamp(invLerp(paramNameWidth.float, paramNameWidth.float + sliderWidth.float, mv.x), 0.0, 1.0))
#    if param.kind == Int or param.kind == Trigger:
#      param.value = param.value.int.float
#    param.onchange(param.value, voice)
#else:
#  dragging = false


method update*(self: MachineView, dt: float) =

  let mv = mouse()

  if mv.x > screenWidth div 3 + paramNameWidth:
    machine.updateExtraData(screenWidth div 3 + paramNameWidth, 16, screenWidth - 1, screenHeight - 1)
  else:
    updateParams(1,1, screenWidth div 3 + paramNameWidth, screenHeight - 1)

proc key*(self: MachineView, key: KeyboardEventPtr, down: bool): bool =
  let scancode = key.keysym.scancode
  let ctrl = ctrl()
  let shift = (int16(key.keysym.modstate) and int16(KMOD_SHIFT)) != 0

  let paramsOnScreen = (screenHeight div 8)

  var globalParams = addr(machine.globalParams)
  var voiceParams =  addr(machine.voiceParams)
  var nParams = globalParams[].len + voiceParams[].len * machine.voices.len
  if down:
    case scancode:
    of SDL_SCANCODE_S:
      if ctrl and down:
        var patchName: string = ""
        var menu = newMenu(point2d(0,0), "save patch")
        var te = newMenuItemText("name", if patchName == nil: "" else: patchName)
        menu.items.add(te)
        menu.items.add(newMenuItem("save") do():
          savePatch(self.machine, te.value)
          popMenu()
        )
        pushMenu(menu)
        return true
    of SDL_SCANCODE_O:
      if ctrl and down:
        var menu = newMenu(point2d(0,0), "load patch")
        for patch in machine.getPatches():
          (proc() =
            let patchName = patch
            menu.items.add(newMenuItem(patch) do():
              self.machine.loadPatch(patchName)
              popMenu()
            )
          )()
        pushMenu(menu)
        return true
    of SDL_SCANCODE_UP:
      currentParam -= 1
      if currentParam < 0:
        currentParam = nParams - 1
      return true
    of SDL_SCANCODE_DOWN:
      currentParam += 1
      if currentParam > nParams - 1:
        currentParam = 0
      return true
    of SDL_SCANCODE_LEFT, SDL_SCANCODE_RIGHT:
      var (voice, param) = machine.getParameter(currentParam)
      let range = param.max - param.min
      let dir = if scancode == SDL_SCANCODE_LEFT: -1.0 else: 1.0
      case param.kind:
      of Int, Trigger, Note, Bool:
        let move = if ctrl: (if param.kind == Note: 12.0 else: 10.0) else: 1.0
        param.value = clamp(param.value.int.float + move * dir, param.min, param.max)
      of Float:
        let move = if shift: 0.001 elif ctrl: 0.1 else: 0.01
        param.value = clamp(param.value + range * move * dir, param.min, param.max)
      if param.onchange != nil:
        param.onchange(param.value, voice)
      return true
    of SDL_SCANCODE_KP_PLUS, SDL_SCANCODE_EQUALS:
      machine.addVoice()
      return true
    of SDL_SCANCODE_KP_MINUS, SDL_SCANCODE_MINUS:
      machine.popVoice()
      return true

    else:
      discard

  # TODO: handle extra keys for the machine

  return false

method event(self: MachineView, event: Event): bool =
  case event.kind:
  of MouseWheel:
    scroll -= event.wheel.y
    return true
  of MouseButtonUp:
    case event.button.button:
    of 1:
      dragging = false
      return true
    else:
      discard
  of MouseButtonDown:
    case event.button.button:
    of 1:
      # check if they clicked on a param bar
      let mv = intPoint2d(event.button.x, event.button.y)
      var y = 0
      let nParams = machine.getParameterCount()
      for i in scroll..nParams-1:
        var (voice, param) = machine.getParameter(i)
        if param.separator:
          y += 4
        if mv.y >= y and mv.y <= y + 7:
          currentParam = i
          dragging = true
          return true
        y += 8
    else:
      discard
  of MouseMotion:
    if dragging:
      var (voice, param) = machine.getParameter(currentParam)
      let paramWidth = screenWidth div 3 + paramNameWidth
      let sliderWidth = paramWidth - 64 - 6
      param.value = lerp(param.min, param.max, clamp(invLerp(paramNameWidth.float, paramNameWidth.float + sliderWidth.float, event.motion.x.float), 0.0, 1.0))
      if param.kind == Int or param.kind == Trigger:
        param.value = param.value.int.float
      param.onchange(param.value, voice)
      return true
  of KeyUp, KeyDown:
    return key(event.key, event.kind == KeyDown)
  else:
    discard
  return false

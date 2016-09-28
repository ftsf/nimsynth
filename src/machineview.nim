import common
import pico
import strutils
import util
import menu
import basic2d

### Machine View
# Draw a single machine's settings

{.this:self.}

type MachineView* = ref object of View
  machine*: Machine
  currentParam*: int
  dragging: bool
  scroll: int
  menu*: Menu

const maxPatchSlots = 64

const paramNameWidth = 64

proc newMachineView*(machine: Machine): MachineView =
  result = new(MachineView)
  result.machine = machine

proc drawParams*(self: MachineView, x,y,w,h: int) =
  let paramsOnScreen = (h div 8)

  var nParams = machine.getParameterCount()
  var y = y
  let startParam = scroll
  let sliderWidth = w - 64
  if nParams > 0:
    # TODO: fix scrolling
    for i in startParam..(min(nParams-1, startParam+paramsOnScreen)):
      setColor(if i == currentParam: 8 else: 7)
      var (voice, param) = machine.getParameter(i)
      print((if voice > -1: $(voice+1) & ": " else: "") & param.name, x, y)
      printr(if param.getValueString != nil: param.getValueString(param.value, voice) else: param.value.formatFloat(ffDecimal, 2), x + 63, y)
      var range = (param.max - param.min)
      if range == 0.0:
        range = 1.0
      setColor(1)
      # draw slider background
      rectfill(x + paramNameWidth, y, x + paramNameWidth + sliderWidth, y+4)

      # draw slider fill
      setColor(if i == currentParam: 8 else: 6)
      let zero = if 0.0 >= param.min and 0.0 <= param.max: invLerp(param.min, param.max, 0.0) else: param.min
      rectfill(x + paramNameWidth + sliderWidth * ((zero - param.min) / range).float, y, x + paramNameWidth + sliderWidth.float * ((param.value - param.min) / range).float, y+4)

      # draw default bar
      setColor(7)
      line(x + paramNameWidth + sliderWidth * ((param.default - param.min) / range), y, x + paramNameWidth + sliderWidth * ((param.default - param.min) / range), y+4)
      y += 8

method draw*(self: MachineView) =
  let paramsOnScreen = (screenHeight div 8)
  cls()
  setColor(6)
  printr(machine.name, screenWidth - 1, 1)

  let paramWidth = screenWidth div 3 + paramNameWidth
  drawParams(1,1, paramWidth, screenHeight - 1)

  machine.drawExtraInfo(paramWidth + 4, 16, screenWidth - paramWidth - 4, screenHeight - 16)

  if menu != nil:
    menu.draw()

  # mouse cursor
  let mv = mouse()
  spr(20, mv.x, mv.y)

proc updateParams*(self: MachineView, x,y,w,h: int) =
  let mv = mouse()

  let paramsOnScreen = h div 8
  let nParams = machine.getParameterCount()
  currentParam = clamp(currentParam, 0, nParams-1)

  if currentParam >= paramsOnScreen - scroll:
    scroll = currentParam
  elif currentParam < scroll:
    scroll = currentParam

  # mouse cursor
  let sliderWidth = w - paramNameWidth
  if mousebtnp(0):
    # click to select param
    let paramUnderCursor = mv.y.int div 8 - scroll
    if mv.x >= x + paramNameWidth and mv.x < x + paramNameWidth + sliderWidth:
      if paramUnderCursor > -1 and paramUnderCursor < nParams:
        currentParam = paramUnderCursor
        dragging = true
  if mousebtn(0):
    # drag to adjust value
    if dragging:
      var (voice, param) = machine.getParameter(currentParam)
      param.value = lerp(param.min, param.max, clamp(invLerp(paramNameWidth.float, paramNameWidth.float + sliderWidth.float, mv.x), 0.0, 1.0))
      if param.kind == Int or param.kind == Trigger:
        param.value = param.value.int.float
      param.onchange(param.value, voice)
  else:
    dragging = false


method update*(self: MachineView, dt: float) =

  let mv = mouse()

  if menu != nil:
    menu.handleMouse(mv)
    return

  updateParams(1,1, screenWidth div 3 + paramNameWidth, screenHeight - 1)

  # TODO: handle mouse cursor in extradata section


method key*(self: MachineView, key: KeyboardEventPtr, down: bool): bool =
  if menu != nil:
    if menu.key(key, down):
      return true

  let scancode = key.keysym.scancode
  let ctrl = (int16(key.keysym.modstate) and int16(KMOD_CTRL)) != 0
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
        self.menu = newMenu(point2d(0,0), "save patch")
        self.menu.back = proc() =
          self.menu = nil
        var te = newMenuItemText("name", if patchName == nil: "" else: patchName)
        self.menu.items.add(te)
        self.menu.items.add(newMenuItem("save") do():
          savePatch(self.machine, te.value)
          self.menu = nil
        )
        return true
    of SDL_SCANCODE_O:
      if ctrl and down:
        self.menu = newMenu(point2d(0,0), "load patch")
        self.menu.back = proc() =
          self.menu = nil
        for patch in machine.getPatches():
          (proc() =
            let patchName = patch
            self.menu.items.add(newMenuItem(patch) do():
              self.machine.loadPatch(patchName)
              self.menu = nil
            )
          )()

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
    of SDL_SCANCODE_KP_PLUS:
      machine.addVoice()
      return true
    of SDL_SCANCODE_KP_MINUS:
      machine.popVoice()
      return true

    else:
      discard

  # TODO: handle extra keys for the machine

  return false

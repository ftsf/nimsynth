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
  scroll: int
  patchSlot: int
  menu*: Menu

const maxPatchSlots = 64

proc newMachineView*(machine: Machine): MachineView =
  result = new(MachineView)
  result.machine = machine

method draw*(self: MachineView) =
  let paramsOnScreen = (screenHeight div 8)
  cls()
  setColor(1)
  printr(machine.name, screenWidth - 1, 1)
  printr("patch: " & $patchSlot, screenWidth - 1, 9)
  var nParams = machine.getParameterCount()
  var y = 1
  let startParam = scroll
  let sliderWidth = (screenWidth - 64) div 3
  for i in startParam..(min(nParams-1, startParam+paramsOnScreen)):
    setColor(if i == currentParam: 8 else: 7)
    var (voice, param) = machine.getParameter(i)
    print((if voice > -1: $(voice+1) & ": " else: "") & param.name, 1, y)
    printr(if param.getValueString != nil: param.getValueString(param.value, voice) else: param.value.formatFloat(ffDecimal, 2), 64, y)
    var range = (param.max - param.min)
    if range == 0.0:
      range = 1.0
    setColor(1)
    # draw slider background
    rectfill(64, y, 64 + sliderWidth, y+4)

    # draw slider fill
    setColor(if i == currentParam: 8 else: 6)
    let zero = invLerp(param.min, param.max, 0.0)
    rectfill(64 + sliderWidth * ((zero - param.min) / range).float, y, 64 + sliderWidth.float * ((param.value - param.min) / range).float, y+4)
    # draw default bar
    setColor(7)
    line(64 + sliderWidth * ((param.default - param.min) / range), y, 64 + sliderWidth * ((param.default - param.min) / range),y+4)
    y += 8

method update*(self: MachineView, dt: float) =
  let paramsOnScreen = (screenHeight div 8)
  let nParams = machine.getParameterCount()
  currentParam = clamp(currentParam, 0, nParams-1)

  if currentParam >= paramsOnScreen - scroll:
    scroll = currentParam
  elif currentParam < scroll:
    scroll = currentParam

method key*(self: MachineView, key: KeyboardEventPtr, down: bool): bool =
  let scancode = key.keysym.scancode
  let ctrl = (int16(key.keysym.modstate) and int16(KMOD_CTRL)) != 0
  let shift = (int16(key.keysym.modstate) and int16(KMOD_SHIFT)) != 0
  let move = if shift: 0.001 elif ctrl: 0.1 else: 0.01

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
          savePatch(self.machine, patchName)
          self.menu = nil
        )
        return true
    of SDL_SCANCODE_O:
      if ctrl and down:
        loadPatch(machine, $patchSlot)
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
    of SDL_SCANCODE_LEFT:
      var (voice, param) = machine.getParameter(currentParam)
      let range = param.max - param.min
      if param.kind == Int:
        param.value = clamp(param.value - 1, param.min, param.max)
      else:
        param.value = clamp(param.value - range * move, param.min, param.max)
      if param.onchange != nil:
        param.onchange(param.value, voice)
      return true
    of SDL_SCANCODE_RIGHT:
      var (voice, param) = machine.getParameter(currentParam)
      let range = param.max - param.min
      if param.kind == Int:
        param.value = clamp(param.value + 1, param.min, param.max)
      else:
        param.value = clamp(param.value + range * move, param.min, param.max)
      if param.onchange != nil:
        param.onchange(param.value, voice)
      return true
    of SDL_SCANCODE_KP_PLUS:
      machine.addVoice()
      return true
    of SDL_SCANCODE_KP_MINUS:
      machine.popVoice()
      return true
    of SDL_SCANCODE_PAGEUP:
      patchSlot -= 1
      if patchSlot < 0:
        patchSlot = maxPatchSlots - 1
      return true
    of SDL_SCANCODE_PAGEDOWN:
      patchSlot += 1
      if patchSlot > maxPatchSlots - 1:
        patchSlot = 0
      return true

    else:
      discard

  return false

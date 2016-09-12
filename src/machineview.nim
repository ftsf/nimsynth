import common
import pico
import strutils
import util

### Machine View
# Draw a single machine's settings

{.this:self.}

type MachineView* = ref object of View
  machine*: Machine
  currentParam*: int

proc newMachineView*(machine: Machine): MachineView =
  result = new(MachineView)
  result.machine = machine

method draw*(self: MachineView) =
  cls()
  setColor(1)
  printr(machine.name, screenWidth - 1, 1)
  var nParams = machine.getParameterCount()
  var y = 1
  for i in 0..nParams-1:
    setColor(if i == currentParam: 8 else: 7)
    var (voice, param) = machine.getParameter(i)
    print((if voice > -1: $(voice+1) & ": " else: "") & param.name, 1, y)
    printr(if param.getValueString != nil: param.getValueString(param.value, voice) else: param.value.formatFloat(ffDecimal, 2), 64, y)
    let range = param.max - param.min
    setColor(1)
    rectfill(64, y, 64 + (screenWidth - 64 - 64), y+4)
    setColor(if i == currentParam: 8 else: 7)
    let zero = if param.max > 0.0 and param.min < 0.0: invLerp(param.min, param.max, 0.0) else: param.min
    rectfill(64 + (screenWidth - 64 - 64) * zero, y, 64 + (screenWidth - 64 - 64) * ((param.value - param.min) / range), y+4)
    setColor(7)
    line(64 + (screenWidth - 64 - 64) * ((param.default - param.min) / range), y, 64 + (screenWidth - 64 - 64) * ((param.default - param.min) / range),y+4)
    y += 8

method update*(self: MachineView, dt: float) =
  let nParams = machine.getParameterCount()
  currentParam = clamp(currentParam, 0, nParams-1)

method key*(self: MachineView, key: KeyboardEventPtr, down: bool): bool =
  let scancode = key.keysym.scancode
  let ctrl = (int16(key.keysym.modstate) and int16(KMOD_CTRL)) != 0
  let shift = (int16(key.keysym.modstate) and int16(KMOD_SHIFT)) != 0
  let move = if shift: 0.001 else: 0.01

  var globalParams = addr(machine.globalParams)
  var voiceParams =  addr(machine.voiceParams)
  var nParams = globalParams[].len + voiceParams[].len * machine.voices.len
  if down:
    case scancode:
    of SDL_SCANCODE_UP:
      currentParam -= 1
      currentParam = clamp(currentParam, 0, nParams-1)
      return true
    of SDL_SCANCODE_DOWN:
      currentParam += 1
      currentParam = clamp(currentParam, 0, nParams-1)
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
    else:
      discard

  return false

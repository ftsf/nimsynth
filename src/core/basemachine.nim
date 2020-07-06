import common

import nico
import nico/vec

import ui/machineview
import util

import ui/menu


{.this: self.}

method getMachineView*(self: Machine): View {.base.} =
  return newMachineView(self)

method getAABB*(self: Machine): AABB {.base.} =
  result.min.x = (pos.x.int - 16).float32
  result.min.y = (pos.y.int - 4).float32
  result.max.x = (pos.x.int + 16).float32
  result.max.y = (pos.y.int + 4).float32

method drawBox*(self: Machine) {.base.} =
  if nInputs == 0 and nOutputs > 0:
    # generator
    setColor(3)
  elif nInputs == 0 and nOutputs == 0:
    # util
    setColor(2)
  else:
    # fx
    setColor(1)
  rrectfill(getAABB())
  setColor(if bypass: 5 elif disabled: 1 else: 6)
  rrect(getAABB())
  printc(name, pos.x, pos.y - 2)

#method layoutUpdate*(self: Machine, layout: View, df: float) {.base.} =
#  discard

method getParameterMenu*(self: Machine, mv: Vec2f, title: string, onselect: proc(paramId: int)): Menu {.base.} =
  var menu = newMenu(mv, title)
  for i in 0..<getParameterCount():
    (proc =
      var paramId = i
      var (voice,param) = self.getParameter(i)
      var item = newMenuItem((if voice > -1: $(voice+1) & ": " else: "") & param.name, proc() =
        onselect(paramId)
      )
      if param.separator:
        menu.items.add(newMenuItem(""))
      menu.items.add(item)
    )()
  return menu

method getBindParameterMenu*(self: Machine, mv: Vec2f, title: string, sourceMachine: Machine, binding: Binding, onselect: proc(paramId: int)): Menu {.base.} =
  var menu = newMenu(mv, title)
  var hadItemBeforeSep = false
  for i in 0..<getParameterCount():
    var (voice,param) = self.getParameter(i)
    if binding.kind != bkAny:
      if binding.kind == bkNote and param.kind != Note: continue
      if binding.kind == bkInt and param.kind != Int: continue
      if binding.kind == bkTrigger and param.kind != Trigger: continue
      if binding.kind == bkFloat and param.kind != Float: continue
    hadItemBeforeSep = true
    var alreadyBound = false
    for b in sourceMachine.bindings:
      if b.machine == self and b.param == i:
        alreadyBound = true
        break
    (proc =
      var paramId = i
      var item = newMenuItem((if voice > -1: $(voice+1) & ": " else: "") & param.name, proc() =
        onselect(paramId)
      )
      if alreadyBound:
        item.status = Warning
      if param.separator and hadItemBeforeSep:
        menu.items.add(newMenuItem(""))
        hadItemBeforeSep = false
      menu.items.add(item)
    )()
  return menu

method getSlotMenu*(self: Machine, mv: Vec2f, onselect: proc(slotId: int)): Menu {.base.} =
  var menu = newMenu(mv, "select binding slot")
  for i in 0..<nBindings:
    (proc() =
      let slotId = i
      var binding = addr(self.bindings[slotId])
      var str: string
      if binding.machine != nil:
        var (voice, param) = binding.machine.getParameter(binding.param)
        str = binding.machine.name & ": " & (if voice > -1: ($(voice+1) & ": ") else: "") & param.name
      else:
        str = " - "

      menu.items.add(
        newMenuItem($(slotId+1) & " -> " & str) do():
          onselect(slotId)
      )
    )()
  return menu

method getBindingMenu*(self: Machine, mv: Vec2f, targetMachine: Machine, slotId: int = -1, onselect: proc(slotId, paramId: int)): Menu {.base.} =
  if nBindings > 1 and slotId == -1:
    # let them select the slot first
    return self.getSlotMenu(mv) do(slotId: int):
      popMenu()
      pushMenu(self.getBindingMenu(mv, targetMachine, slotId, onselect))

  let slotId = (if slotId == -1: 0 else: slotId)

  var menu = self.getParameterMenu(mv, "select param") do(paramId: int):
    onselect(slotId, paramId)

  return menu

method getOutputMenu*(self: Machine, mv: Vec2f, onselect: proc(outputId: int)): Menu {.base.} =
  var menu = newMenu(mv, "select output")
  for i in 0..nOutputs-1:
    (proc() =
      let outputId = i
      menu.items.add(newMenuItem($outputId & ": " & self.getOutputName(outputId) ) do():
        onselect(outputId)
      )
    )()
  return menu

method getInputMenu*(self: Machine, mv: Vec2f, onselect: proc(inputId: int)): Menu {.base.} =
  var menu = newMenu(mv, "select input")
  for i in 0..<nInputs:
    (proc() =
      let inputId = i
      menu.items.add(newMenuItem($(inputId+1) & ": " & self.getInputName(inputId) ) do():
        onselect(inputId)
      )
    )()
  return menu

method getMenu*(self: Machine, mv: Vec2f): Menu {.base.} =
  var menu = newMenu(mv, name)
  menu.items.add(newMenuItem("rename", proc() =
    var menu = newMenu(menu.pos, "rename")
    var te = newMenuItemText("name", self.name)
    menu.items.add(te)
    menu.items.add(newMenuItem("rename") do():
      self.name = te.value
      popMenu()
      popMenu()
    )
    pushMenu(menu)
  ))
  if nBindings > 0:
    menu.items.add(newMenuItem("show bindings", proc() =
      self.hideBindings = not self.hideBindings
      popMenu()
    ))
  if nOutputs > 0:
    menu.items.add(newMenuItem("monitor", proc() =
      sampleMachine = self
      popMenu()
    ))
  if self.disabled:
    menu.items.add(newMenuItem("enable", proc() =
      self.disabled = not self.disabled
      popMenu()
    ))
  else:
    menu.items.add(newMenuItem("disable", proc() =
      self.disabled = not self.disabled
      popMenu()
    ))
  if nInputs > 0 and nOutputs > 0:
    menu.items.add(newMenuItem("bypass", proc() =
      self.bypass = not self.bypass
      popMenu()
    ))
  menu.items.add(newMenuItem("reset", proc() =
    self.reset()
    popMenu()
  ))
  menu.items.add(newMenuItem("remove", proc() =
    self.remove()
    popMenu()
  ))
  menu.items.add(newMenuItem("delete", proc() =
    self.delete()
    popMenu()
  ))
  return menu

method drawParams*(self: Machine, x,y,w,h: int, favOnly: bool = false) {.base.} =
  let paramNameWidth = 64
  let sliderWidth = w - paramNameWidth - 6

  var i = 0
  var yv = y
  for voice,param in self.parameters(favOnly):
    if i < self.scroll:
      i += 1
      continue
    i += 1
    if param.separator:
      setColor(5)
      line(x,yv,x+paramNameWidth + sliderWidth,yv)
      yv += 4

    setColor(if i == self.currentParam: 8 elif param.fav: 10 else: 7)
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

    let zeroX = x + paramNameWidth + sliderWidth.float * clamp(invLerp(param.min, param.max, 0.0), 0.0, 1.0)

    rectfill(zeroX, yv, x + paramNameWidth + sliderWidth.float * invLerp(param.min, param.max, param.value), yv+4)

    # draw default bar
    if param.kind != Note:
      setColor(7)
      let defaultX = x + paramNameWidth + sliderWidth.float * invLerp(param.min, param.max, param.default)
      line(defaultX, yv, defaultX, yv+4)

    yv += 8
    i += 1

    if yv >= y + h:
      break

method updateParams*(self: Machine, x,y,w,h: int, favOnly: bool = false) {.base.} =
  let paramNameWidth = 64
  let sliderWidth = w - paramNameWidth - 6

  var i = 0
  var yv = y
  for voice,param in self.parameters(favOnly):
    if i < self.scroll:
      i += 1
      continue
    i += 1
    if param.separator:
      yv += 4

    var range = (param.max - param.min)
    if range == 0.0:
      range = 1.0

    yv += 8
    i += 1

    if yv >= y + h:
      break

import basic2d

import common
import util
import ui.machineview
import ui.menu
import ui.layoutview

import pico


{.this: self.}

method getMachineView*(self: Machine): View {.base.} =
  return newMachineView(self)

method getAABB*(self: Machine): AABB {.base.} =
  result.min.x = pos.x - 16
  result.min.y = pos.y - 4
  result.max.x = pos.x + 16
  result.max.y = pos.y + 4

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
  rectfill(getAABB())
  setColor(if bypass: 5 elif mute: 1 else: 6)
  rect(getAABB())
  printc(name, pos.x, pos.y - 2)

method layoutUpdate*(self: Machine, layout: View, df: float) {.base.} =
  discard

method getParameterMenu*(self: Machine, mv: Point2d, title: string, onselect: proc(paramId: int)): Menu =
  var menu = newMenu(mv, title)
  for i in 0..getParameterCount()-1:
    (proc =
      var paramId = i
      var (voice,param) = self.getParameter(i)
      var item = newMenuItem((if voice > -1: $voice & ": " else: "") & param.name, proc() =
        onselect(paramId)
      )
      if param.separator:
        menu.items.add(newMenuItem(""))
      menu.items.add(item)
    )()
  return menu

method getSlotMenu*(self: Machine, mv: Point2d, onselect: proc(slotId: int)): Menu =
  var menu = newMenu(mv, "select slot")
  for i in 0..nBindings-1:
    (proc() =
      let slotId = i
      var binding = addr(self.bindings[slotId])
      var str: string
      if binding.machine != nil:
        var (voice, param) = binding.machine.getParameter(binding.param)
        str = binding.machine.name & ": " & (if voice >= 0: ($voice & ": ") else: "") & param.name
      else:
        str = " - "

      menu.items.add(
        newMenuItem($slotId & " -> " & str) do():
          onselect(slotId)
      )
    )()
  return menu

method getBindingMenu*(self: Machine, mv: Point2d, targetMachine: Machine, slotId: int = -1, onselect: proc(slotId, paramId: int)): Menu =
  if nBindings > 1 and slotId == -1:
    # let them select the slot first
    return self.getSlotMenu(mv) do(slotId: int):
      popMenu()
      pushMenu(self.getBindingMenu(mv, targetMachine, slotId, onselect))

  let slotId = (if slotId == -1: 0 else: slotId)

  var menu = self.getParameterMenu(mv, "select param") do(paramId: int):
    onselect(slotId, paramId)

  return menu

method getOutputMenu*(self: Machine, mv: Point2d, onselect: proc(outputId: int)): Menu =
  var menu = newMenu(mv, "select output")
  for i in 0..nOutputs-1:
    (proc() =
      let outputId = i
      menu.items.add(newMenuItem($outputId & ": " & self.getOutputName(outputId) ) do():
        onselect(outputId)
      )
    )()
  return menu

method getInputMenu*(self: Machine, mv: Point2d, onselect: proc(inputId: int)): Menu =
  var menu = newMenu(mv, "select input")
  for i in 0..nInputs-1:
    (proc() =
      let inputId = i
      menu.items.add(newMenuItem($inputId & ": " & self.getInputName(inputId) ) do():
        onselect(inputId)
      )
    )()
  return menu

method getMenu*(self: Machine, mv: Point2d): Menu =
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
    menu.items.add(newMenuItem("mute", proc() =
      self.mute = not self.mute
      popMenu()
    ))
    menu.items.add(newMenuItem("monitor", proc() =
      sampleMachine = self
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
  menu.items.add(newMenuItem("delete", proc() =
    self.delete()
    popMenu()
  ))
  return menu


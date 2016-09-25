import common
import machineview
import pico
import util
import basic2d
import menu
import layoutview

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
  setColor(if recordMachine == self: 8 else: 6)
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
      var item = newMenuItem(param.name, proc() =
        onselect(paramId)
      )
      menu.items.add(item)
    )()
  return menu

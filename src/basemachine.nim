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

method drawBox*(self: Machine) {.base.} =
  setColor(1)
  rectfill(pos.x - 16, pos.y - 4, pos.x + 16, pos.y + 4)
  setColor(if recordMachine == self: 8 else: 6)
  rect(pos.x.int - 16, pos.y.int - 4, pos.x.int + 16, pos.y.int + 4)
  printc(name, pos.x, pos.y - 2)

method layoutUpdate*(self: Machine, layout: View, df: float) {.base.} =
  discard

method getAABB*(self: Machine): AABB {.base.} =
  result.min.x = pos.x - 16
  result.min.y = pos.y - 4
  result.max.x = pos.x + 16
  result.max.y = pos.y + 4

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

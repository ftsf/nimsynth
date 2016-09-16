import common
import machineview
import pico
import util

{.this: self.}

method getMachineView*(self: Machine): View {.base.} =
  return newMachineView(self)

method drawBox*(self: Machine) {.base.} =
  setColor(1)
  rectfill(pos.x - 16, pos.y - 4, pos.x + 16, pos.y + 4)
  setColor(6)
  rect(pos.x.int - 16, pos.y.int - 4, pos.x.int + 16, pos.y.int + 4)
  printc(name, pos.x, pos.y - 2)

method getAABB*(self: Machine): AABB {.base.} =
  result.min.x = pos.x - 16
  result.min.y = pos.y - 4
  result.max.x = pos.x + 16
  result.max.y = pos.y + 4

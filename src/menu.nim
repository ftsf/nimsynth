import basic2d
import util
import pico
import common

{.this:self.}

type
  MenuItem* = ref object of RootObj
    label*: string
    action*: proc()
  Menu* = ref object of RootObj
    pos*: Point2d
    items*: seq[MenuItem]
    selected*: int
    back*: proc()

proc newMenu*(): Menu =
  result = new(Menu)
  result.items = newSeq[MenuItem]()
  result.selected = -1

proc newMenuItem*(label: string, action: proc() = nil): MenuItem =
  result = new(MenuItem)
  result.label = label
  result.action = action

proc getAABB*(self: Menu): AABB =
  result.min.x = pos.x - 2
  result.min.y = pos.y - 2
  result.max.x = pos.x + 64 + 1
  result.max.y = pos.y + items.len.float * 9.0 + 1.0

proc draw*(self: Menu) =
  setColor(1)
  let aabb = self.getAABB()
  rectfill(aabb.min.x, aabb.min.y, aabb.max.x, aabb.max.y)
  var y = pos.y.int
  for i,item in items:
    setColor(if selected == i: 7 else: 6)
    print(item.label, pos.x.int + 1, y)
    y += 9

  setColor(6)
  rect(aabb.min.x.int, aabb.min.y.int, aabb.max.x.int, aabb.max.y.int)

proc key*(self: Menu, key: KeyboardEventPtr, down: bool): bool =
  if down:
    case key.keysym.scancode:
    of SDL_SCANCODE_UP:
      selected -= 1
      if selected < 0:
        selected = items.high
      return true
    of SDL_SCANCODE_DOWN:
      selected += 1
      if selected > items.high:
        selected = 0
      return true
    of SDL_SCANCODE_RETURN:
      if selected < 0:
        return true
      if items[selected].action != nil:
        items[selected].action()
      return true
    of SDL_SCANCODE_ESCAPE:
      if back != nil:
        back()
      return true
    else:
      return false
  return false

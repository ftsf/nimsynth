import basic2d
import util
import pico
import common

{.this:self.}

type
  MenuItemStatus* = enum
    Default
    Primary
    Warning
    Danger
    Disabled
  MenuItem* = ref object of RootObj
    label*: string
    action*: proc()
    status*: MenuItemStatus
  MenuItemText* = ref object of MenuItem
    default*: string
    value*: string
  Menu* = ref object of RootObj
    label*: string
    pos*: Point2d
    items*: seq[MenuItem]
    selected*: int
    back*: proc()
    hasSetTextFunc: int

var menuStack*: seq[Menu]

proc pushMenu*(menu: Menu) =
  menuStack.add(menu)

proc popMenu*() =
  if menuStack.len > 0:
    discard menuStack.pop()

proc hasMenu*(): bool =
  return menuStack.len > 0

proc getMenu*(): Menu =
  return menuStack[menuStack.high]

proc newMenu*(pos: Point2d, label: string = nil): Menu =
  result = new(Menu)
  result.pos = pos
  result.label = label
  result.items = newSeq[MenuItem]()
  result.selected = -1
  result.hasSetTextFunc = -1

proc newMenuItem*(label: string, action: proc() = nil, status: MenuItemStatus = Default): MenuItem =
  result = new(MenuItem)
  result.label = label
  result.action = action
  result.status = status

proc newMenuItemText*(label: string, default: string = ""): MenuItemText =
  var mi = new(MenuItemText)
  mi.label = label
  mi.default = default
  mi.value = default
  return mi

proc inputText(self: MenuItemText, text: string): bool =
  value &= text
  return true

proc getAABB*(self: Menu): AABB =
  result.min.x = pos.x - 2
  result.min.y = pos.y - 2

  result.max.y = min(pos.y + items.len.float * 9.0 + 10.0, screenHeight.float - 8.0)

  let rows = (result.max.y - result.min.y).int div 9
  result.max.y = result.min.y + rows.float * 9.0 + 2.0
  let cols = 1 + items.len div rows
  result.max.x = result.min.x + cols.float * 64.0 + 4

method draw*(self: MenuItem, x,y,w: int, selected: bool): int =
  setColor(
    case self.status:
    of Default: 1
    of Primary: 3
    of Warning: 4
    of Danger: 2
    of Disabled: 0
  )
  rectfill(x, y-1, x+w, y + 5)
  if selected:
    setColor(
      case self.status:
      of Default: 13
      of Primary: 11
      of Warning: 9
      of Danger: 8
      of Disabled: 0
    )

    rectfill(x, y-1, x+w, y + 5)
  setColor(if selected: 7 else: 6)
  print(label, x + 2, y)
  return 9

method draw*(self: MenuItemText, x,y,w: int, selected: bool): int =
  if selected:
    setColor(13)
    rectfill(x, y, x+w, y + 5)
  setColor(if selected: 7 else: 6)
  print(label & ": " & value, x + 2, y)
  return 9

proc draw*(self: Menu) =
  let camera = getCamera()
  let aabb = self.getAABB()

  let w = (aabb.max.x - aabb.min.x).int
  let h = (aabb.max.y - aabb.min.y).int

  if aabb.max.x > screenWidth + camera.x:
    pos.x = (screenWidth + camera.x - w).float
  if aabb.max.y > screenHeight + camera.y:
    pos.y = clamp((screenHeight + camera.y - h).float, 0.0, screenHeight.float - 8.0)

  let x = pos.x.int
  let y = pos.y.int

  setColor(1)
  rectfill(aabb)
  var yv = y + 2
  var xv = x
  if label != nil:
    setColor(13)
    print(label, x + 2, yv)
    yv += 9
  let starty = yv
  for i,item in items:
    yv += item.draw(xv, yv, 64, selected == i)
    if yv >= aabb.max.y:
      yv = starty
      xv += 64

  setColor(6)
  rect(aabb)

proc event*(self: Menu, event: Event): bool =
  case event.kind:
  of MouseMotion:
    let mv = mouse()
    let aabb = self.getAABB()
    if pointInAABB(mv, self.getAABB()):
      let rows = (aabb.max.y - aabb.min.y) div 9 - (if label != nil: 1 else: 0)
      let column = (mv.x - pos.x).int div 64
      let row = (mv.y - pos.y).int div 9 - (if label != nil: 1 else: 0)
      if row < 0:
        return true
      if row >= rows:
        return true
      let item = row + (column * rows)
      if item >= 0 and item < items.len:
        selected = item
      return true

  of MouseButtonDown:
    let mv = mouse()
    if pointInAABB(mv, self.getAABB()):
      if event.button.button == 1 and selected >= 0:
        if items[selected].action != nil:
          items[selected].action()
      return true

    elif event.button.button == 1:
      if back != nil:
        back()
      else:
        popMenu()
      return true

  of KeyDown, KeyUp:
    let down = event.kind == KeyDown
    let scancode = event.key.keysym.scancode

    if down:
      if selected >= 0 and selected < items.len and items[selected] of MenuItemText:
        var te = MenuItemText(items[selected])
        if hasSetTextFunc != selected:
          setTextFunc(proc(text: string): bool =
            return te.inputText(text)
          )
        if scancode == SDL_SCANCODE_BACKSPACE and down and te.value.len > 0:
          te.value = te.value[0..te.value.high-1]
          return true
      else:
        setTextFunc(nil)
        hasSetTextFunc = -1

      case scancode:
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
        else:
          popMenu()
        return true
      else:
        discard
  else:
    discard

  return false

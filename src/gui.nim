{.this:self.}

import sdl2

type
  GuiObject* = object of RootObj
  GuiWindow* ref object of GuiObject
    title: string
    x,y: int
    w,h: int
    bg: int

method init*(self: GuiWindow, title: string, x,y,w,h: int) =
  title = title
  x = x
  y = y
  w = w
  h = h

proc newGuiWindow*(title: string, x,y,w,h: int): GuiWindow =
  result = new(GuiWindow)
  result.init()

method event(self: GuiWindow, evt: sdl.Event): bool {.base.} =
  return false

method draw(self: GuiWindow) {.base.} =
  setColor(bg)
  rectfill(x,y,w,h)
  setColor(6)
  rect(x,y,w,h)

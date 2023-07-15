import common
import nico
import nico/vec
import math
import util

type ParamWindow = ref object of Window
  machine*: Machine
  favOnly*: bool
  scroll*: int
  currentParam*: int
  dragging*: bool
  clickPos*: Vec2f

const paramNameWidth = 64



method drawContents(self: ParamWindow, x,y,w,h: int) =
  # draw parameters for the machine
  let sliderWidth = self.w - paramNameWidth - 6

  var yv = y
  var x = x
  var i = 0
  for voice, param in self.machine.parameters(self.favOnly):
    if i < self.scroll:
      i += 1
      continue

    if param.separator:
      setColor(5)
      line(x,yv,x+paramNameWidth + sliderWidth,yv)
      yv += 4

    setColor(if i == self.currentParam: 8 elif param.fav: 10 else: 7)
    print((if voice > -1: $voice & ": " else: "") & param.name, x, yv)
    printr(param[].valueString(param.value), x + 63, yv)
    var range = (param.max - param.min)
    if range == 0.0:
      range = 1.0

    let minX = x + paramNameWidth
    let maxX = minX + sliderWidth

    # draw slider background
    setColor(0)
    rectfill(minX, yv, maxX, yv+4)

    # draw slider fill
    setColor(if i == self.currentParam: 8 else: 6)

    let zeroX = x + paramNameWidth + sliderWidth.float32 * clamp(invLerp(param.min, param.max, 0.0), 0.0, 1.0)
    rectfill(clamp(zeroX, minX, maxX), yv, clamp(minX + sliderWidth.float32 * invLerp(param.min, param.max, param.value), minX, maxX), yv+4)

    # draw default bar
    if param.kind != Note:
      setColor(7)
      let defaultX = minX + sliderWidth.float32 * invLerp(param.min, param.max, param.default)
      line(defaultX, yv, defaultX, yv+4)

    yv += 8

    i += 1
    if yv + 7 >= y + h:
      setColor(7)
      print("...", x, yv)
      break

proc getParamByPos(self: ParamWindow, x,y,w,h: int, px,py: int): int =
  var yv = y
  let nParams = self.machine.getParameterCount(self.favOnly)
  for i in self.scroll..<nParams:
    var (voice, param) = self.machine.getParameter(i, self.favOnly)
    if param.separator:
      yv += 4
    if py >= yv and py <= yv + 7:
      return i
    yv += 8
  return -1

method eventContents(self: ParamWindow, x,y,w,h: int, e: Event): bool =
  let sliderWidth = self.w - paramNameWidth - 6

  case e.kind:
  of ekMouseWheel:
    let mv = mouseVec()
    if mv.x >= x and mv.x <= x + w and mv.y >= y and mv.y <= y + h:
      self.scroll -= e.ywheel
      if self.scroll < 0:
        self.scroll = 0
      let nParams = self.machine.getParameterCount(self.favOnly)
      if self.scroll >= nParams:
        self.scroll = nParams
      return true
  of ekMouseButtonUp:
    case e.button:
    of 1:
      if self.dragging:
        self.dragging = false
        return true
    else:
      discard
  of ekMouseButtonDown:
    case e.button:
    of 1:
      # check if they clicked on a param bar
      let mv = mouseVec()
      if mv.x >= x and mv.x <= x + w and mv.y >= y and mv.y <= y + h:
        # TODO handle scrollbar
        let i = self.getParamByPos(x,y,w,h, mv.x.int, mv.y.int)
        if i >= 0:
          if mv.x > x + paramNameWidth:
            self.currentParam = i
            self.dragging = true
            self.clickPos = mv
            return true
          elif mv.x < x + paramNameWidth and e.clicks == 2:
            let (voice, param) = self.machine.getParameter(i, self.favOnly)
            param.fav = not param.fav
    of 3:
      # check if they clicked on a param bar
      # reset to default value
      let mv = mouseVec()
      if mv.x >= x and mv.x <= x + w and mv.y >= y and mv.y <= y + h:
        if mv.x > x + paramNameWidth:
          var yv = y
          let nParams = self.machine.getParameterCount()
          for i in self.scroll..<nParams:
            var (voice, param) = self.machine.getParameter(i)
            if param.separator:
              yv += 4
            if mv.y >= y and mv.y <= yv + 7:
              self.currentParam = i
              let (voice,param) = self.machine.getParameter(self.currentParam, self.favOnly)
              param.value = param.default
              param.onchange(param.value, voice)
              return true
            yv += 8
    else:
      discard
  of ekMouseMotion:
    if self.dragging:
      var (voice, param) = self.machine.getParameter(self.currentParam, self.favOnly)
      if shift():
        # jump directly to value
        param.value = lerp(param.min, param.max, clamp(invLerp(paramNameWidth.float32, paramNameWidth.float + sliderWidth.float, e.x.float), 0.0, 1.0))
      else:
        # relative shift
        let range = param.max - param.min
        let ydist = e.y.float32 - self.clickPos.y
        let sensitivity = clamp(10.0 / abs(e.y.float32 - self.clickPos.y))
        let speed = (range / sliderWidth.float32) * sensitivity
        if ydist < 3:
          param.value = lerp(param.min, param.max, clamp(invLerp(paramNameWidth.float32, paramNameWidth.float + sliderWidth.float, (e.x - x).float), 0.0, 1.0))
        else:
          param.value = clamp(param.value + e.xrel * speed, param.min, param.max)
      param.onchange(param.value, voice)
      return false
  of ekKeyDown:
    let mv = mouseVec()
    if mv.x >= x and mv.x <= x + w and mv.y >= y and mv.y <= y + h:
      if e.keycode == K_F:
        self.favOnly = not self.favOnly
        self.currentParam = 0
        self.scroll = 0
        return true
  else:
    discard
  return false

proc newParamWindow*(machine: Machine, x,y,w,h: int): Window =
  var win = new(ParamWindow)
  win.machine = machine
  win.pos = vec2f(x,y)
  win.w = w
  win.h = h
  win.title = machine.name
  return win

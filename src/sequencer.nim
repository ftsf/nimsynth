{.this:self.}

import strutils
import pico
import common
import sdl2
import util
import master
import basemachine
import machineview
import menu
import math
import basic2d

const colsPerPattern = 8

type
  PatternColor = enum
    Green
    Blue
    Red
    Yellow
    White
  Pattern* = ref object of RootObj
    name*: string
    color*: PatternColor
    rows*: seq[array[colsPerPattern, int]]
  ColumnMode = enum
    cmCoarse
    cmFine
    cmFloat
  ColumnInterpolation = enum
    ciStep
    ciLinear
    ciCubic
  Sequencer* = ref object of Machine
    patterns*: seq[Pattern]
    columnDetails*: array[colsPerPattern, tuple[mode: ColumnMode, interpolation: ColumnInterpolation]]
    currentPattern*: int
    currentStep*: int
    currentColumn*: int
    subColumn*: int
    playingPattern*: int
    step*: int
    ticksPerBeat*: int
    playing: bool
    subTick: float
    looping: bool
  SequencerView* = ref object of MachineView
    clipboard: Pattern

proc mapSeqValueToParamValue(value: int, param: ptr Parameter): float =
  case param.kind:
  of Bool:
    return (if value == 1.0: 1.0 else: 0.0)
  of Note, Int:
    return clamp(value.float, param.min, param.max)
  of Trigger:
    return (if value == 1: 1.0 else: 0.0)
  of Float:
    return lerp(param.min, param.max, invLerp(0.0, 999.0, clamp(value, 0, 999).float))

proc newPattern*(length: int = 16): Pattern =
  result = new(Pattern)
  result.rows = newSeq[array[colsPerPattern, int]](length)
  result.name = ""
  for row in mitems(result.rows):
    for col in mitems(row):
      col = Blank

method init*(self: Sequencer) =
  procCall init(Machine(self))

  patterns = newSeq[Pattern](64)
  patterns[0] = newPattern(16)
  ticksPerBeat = 4
  subTick = 0.0
  name = "seq"
  nOutputs = 0
  nInputs = 0
  nBindings = 8
  bindings.setLen(8)

  globalParams.add([
    Parameter(kind: Int, name: "pattern", min: 0.0, max: 63.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      if newValue == OffNote:
        self.subTick = 0.0
        self.step = 0
        self.playing = false
      else:
        self.playingPattern = clamp(newValue.int, 0, self.patterns.high)
        self.subTick = 0.0
        self.step = 0
        self.playing = true
    , getValueString: proc(value: float, voice: int): string =
      if self.patterns[value.int] != nil:
        return $value.int & ": " & self.patterns[value.int].name
      else:
        return $value.int
    ),
    Parameter(kind: Int, name: "tpb", min: -32.0, max: 32.0, default: 4.0, onchange: proc(newValue: float, voice: int) =
      self.ticksPerBeat = newValue.int
    , getValueString: proc(value: float, voice: int): string =
      return (if value < 0: "1/" & $(-value.int) else: $value.int)
    ),
    Parameter(kind: Int, name: "loop", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.looping = newValue.bool
    , getValueString: proc(value: float, voice: int): string =
      return (if value == 1.0: "on" else: "off")
    ),
    Parameter(kind: Int, name: "play", min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.playing = newValue.bool
    , getValueString: proc(value: float, voice: int): string =
      return (if value == 1.0: "on" else: "off")
    ),
    Parameter(kind: Float, name: "tick", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      if self.patterns[self.playingPattern] != nil:
        if self.patterns[self.playingPattern].rows != nil:
          self.step = (newValue * self.patterns[self.playingPattern].rows.high.float).int
          self.subTick = 0.0
    , getValueString: proc(value: float, voice: int): string =
      return $(value * self.patterns[self.playingPattern].rows.high.float).int
    ),
  ])

  setDefaults()

proc newSequencerView(machine: Machine): View =
  var v = new(SequencerView)
  v.machine = machine
  return v

method getMachineView*(self: Sequencer): View =
  return newSequencerView(self)

proc newSequencer*(): Machine =
  var sequencer = new(Sequencer)
  sequencer.init()
  return sequencer

registerMachine("sequencer", newSequencer, "util")

method getAABB*(self: Sequencer): AABB =
  result.min.x = pos.x - 17
  result.min.y = pos.y - 17
  result.max.x = pos.x + 17
  result.max.y = pos.y + 17 + 8

method drawBox*(self: Sequencer) =
  # draw container
  let x = pos.x - 15
  let y = pos.y - 15

  setColor(2)
  rectfill(getAABB())
  setColor(1)
  rectfill(x-1,y-1, x+31,y+31)
  setColor(6)
  rect(getAABB())

  var pattern = patterns[playingPattern]

  for j in 0..7:
    for i in 0..7:
      let patId = j * 8 + i
      let pattern = patterns[patId]
      setColor(
        if pattern == nil: 0 else:
          case pattern.color:
          of Green:
            if patId == playingPattern and playing: 11 else: 3
          of Blue:
            if patId == playingPattern and playing: 12 else: 1
          of Red:
            if patId == playingPattern and playing: 8 else: 2
          of Yellow:
            if patId == playingPattern and playing: 9 else: 4
          of White:
            if patId == playingPattern and playing: 7 else: 5
      )

      rectfill(x + i * 4, y + j * 4, x + i * 4 + 2, y + j * 4 + 2)

  setColor(6)
  printc(name, pos.x.int , pos.y.int + 18)

proc drawPattern(self: Sequencer, x,y,w,h: int) =
  clip(x,y,w,h)
  let pattern = patterns[currentPattern]
  # TODO fix scrolling
  let startStep = clamp(currentStep - (h div 8) + 7, 0, pattern.rows.high)
  let endStep = clamp(startStep + (h div 8), 0, pattern.rows.high)

  for i in startStep..endStep:
    let y = y + (i - startStep) * 8
    let row = pattern.rows[i]

    # draw background
    setColor(if ticksPerBeat > 1 and i %% ticksPerBeat == 0: 5 else: 1)
    rectfill(x, y, x + colsPerPattern * 17, y+7)

    # draw line
    if playingPattern == currentPattern and step == i:
      setColor(2)
      let y = y + (subTick * 8.0).int
      line(x, y, x + colsPerPattern * 17, y)

    # draw step number
    setColor(if i == currentStep: 12 elif ticksPerBeat > 1 and i %% ticksPerBeat == 0: 6 else: 13)
    printr($i, x + 9, y + 1)

    # draw values in columns
    for col,val in row:
      if i == currentStep and col == currentColumn:
        setColor(0)
        rectfill(x + col * 16 + 11, y - 1, x + col * 16 + 11 + 13, y + 8)

      if bindings[col].machine != nil:
        var targetMachine = bindings[col].machine
        var (voice, targetParam) = targetMachine.getParameter(bindings[col].param)
        # color the background of the current cell a different color
        case targetParam.kind:
        of Note:
          var str = if val == Blank: "..." else: noteToNoteName(val.int)
          setColor(if i == currentStep and col == currentColumn and subColumn == 0: 12 elif ticksPerBeat > 1 and i %% ticksPerBeat == 0: 6 else: 13)
          print(str[0..1], x + col * 16 + 12, y + 1)
          setColor(if i == currentStep and col == currentColumn and subColumn == 1: 12 elif ticksPerBeat > 1 and i %% ticksPerBeat == 0: 6 else: 13)
          print(str[2..2], x + col * 16 + 12 + 8, y + 1)
        of Bool:
          var str = if val == Blank: "  ." else: align($val, 3, ' ')
        of Int,Float:
          # we want to split this into 3 columns, one for each char
          var str = if val == Blank: "..." else: align($val, 3, '.')
          for c in 0..2:
            setColor(if i == currentStep and col == currentColumn and c == subColumn: 12 elif ticksPerBeat > 1 and i %% ticksPerBeat == 0: 6 else: 13)
            print(str[c..c], x + col * 16 + 12 + c * 4, y + 1)
        of Trigger:
          setColor(if i == currentStep and col == currentColumn: 12 elif ticksPerBeat > 1 and i %% ticksPerBeat == 0: 6 else: 13)
          print(if val == 1: " x " elif val == 0: " - " else: " . ", x + col * 16 + 12, y + 1)
      else:
          setColor(if i == currentStep and col == currentColumn: 12 elif ticksPerBeat > 1 and i %% ticksPerBeat == 0: 6 else: 13)
          print(" - ", x + col * 16 + 12, y + 1)

  # draw scrollbar
  if startStep != 0 or endStep != pattern.rows.high:
    setColor(1)
    rectfill(x + colsPerPattern * 17 + 2, y, x + colsPerPattern * 17 + 7, y + h)
    setColor(13)
    rectfill(x + colsPerPattern * 17 + 2, y + (startStep.float/pattern.rows.high.float) * h.float, x + colsPerPattern * 17 + 7, y + (endStep.float/pattern.rows.high.float) * h.float)
    if playingPattern == currentPattern:
      setColor(2)
      rectfill(x + colsPerPattern * 17 + 2, y + (step.float/pattern.rows.len.float) * h.float, x + colsPerPattern * 17 + 7, y + ((step+1).float/pattern.rows.len.float) * h.float)
    setColor(7)
    rectfill(x + colsPerPattern * 17 + 2, y + (currentStep.float/pattern.rows.len.float) * h.float, x + colsPerPattern * 17 + 7, y + ((currentStep+1).float/pattern.rows.len.float) * h.float)

  clip()

proc drawPatternSelector(self: Sequencer, x,y,w,h: int) =
  const squareSize = 12
  const padding = 2

  setColor(1)
  rectfill(x-1, y-1, x + (squareSize+padding) * 8 + padding - 1, y + (squareSize + padding) * 8 + padding - 1)

  for row in 0..7:
    for col in 0..7:
      let patId = (row * 8) + col
      let pattern = patterns[patId]
      setColor(
        if pattern == nil: 0 else:
          case pattern.color:
          of Green:
            if patId == playingPattern and playing: 11 else: 3
          of Blue:
            if patId == playingPattern and playing: 12 else: 1
          of Red:
            if patId == playingPattern and playing: 8 else: 2
          of Yellow:
            if patId == playingPattern and playing: 9 else: 4
          of White:
            if patId == playingPattern and playing: 7 else: 5
      )
      rectfill(x + col * (squareSize + padding), y + row * (squareSize + padding), x + col * (squareSize + padding) + (squareSize - 1), y + row * (squareSize + padding) + (squareSize - 1))

      setColor(if patId == currentPattern: 7 else: 0)
      rect(x + col * (squareSize + padding), y + row * (squareSize + padding), x + col * (squareSize + padding) + (squareSize - 1), y + row * (squareSize + padding) + (squareSize - 1))

  var y = y + 9 * (squareSize + padding)
  let pattern = patterns[currentPattern]
  setColor(6)
  print("pattern: " & (if pattern.name != nil: pattern.name else: $currentPattern), x, y)
  y += 8
  print("ticks: " & $pattern.rows.len, x, y)
  y += 8
  print("tick:  " & $currentStep, x, y)
  y += 8
  if ticksPerBeat > 0:
    print("length: " & floatToTimeStr(pattern.rows.len.float * (beatsPerSecond() / ticksPerBeat.float)), x, y)
  elif ticksPerBeat < 0:
    print("length: " & floatToTimeStr((pattern.rows.len.float / (1.0 / -ticksPerBeat.float)).float * beatsPerSecond()), x, y)
  else:
    print("length: inf", x, y)
  y += 8
  if ticksPerBeat > 0:
    print("time: " & floatToTimeStr(currentStep.float * (beatsPerSecond() / ticksPerBeat.float)), x, y)
  elif ticksPerBeat < 0:
    print("time: " & floatToTimeStr((currentStep.float / (1.0 / -ticksPerBeat.float)).float * beatsPerSecond()), x, y)
  else:
    print("time: n/a", x, y)


method update(self: SequencerView, dt: float) =
  var s = Sequencer(machine)

  s.currentPattern = clamp(s.currentPattern, 0, 63)

  updateParams(screenWidth - 128, 8, 126, screenHeight - 9)

method draw*(self: SequencerView) =
  cls()
  var sequencer = Sequencer(machine)
  if sequencer.patterns[sequencer.currentPattern] == nil:
    sequencer.patterns[sequencer.currentPattern] = newPattern(16)
  let pattern = sequencer.patterns[sequencer.currentPattern]
  let startStep = clamp(sequencer.currentStep-7,0,pattern.rows.high)

  setColor(6)
  printr(sequencer.name, screenWidth - 1, 1)

  # draw bindings
  block:
    setColor(4)
    if sequencer.bindings[sequencer.currentColumn].machine != nil:
      var binding = sequencer.bindings[sequencer.currentColumn]
      var (voice, param) = binding.machine.getParameter(binding.param)
      print(binding.machine.name & ": " & (if voice != -1: $voice & ": " else: "") & param.name, 1, 9+8)
    else:
      print($sequencer.currentColumn & ": unbound", 1, 9+8)

    for i in 0..colsPerPattern-1:
      if sequencer.bindings[i].machine == nil:
        rect(i * 16 + 13, 8, i * 16 + 13 + 12, 15)
      else:
        rectfill(i * 16 + 13, 8, i * 16 + 13 + 12, 15)

  sequencer.drawPattern(1,24,screenWidth - 1,screenHeight - 49)

  sequencer.drawPatternSelector(colsPerPattern * 17 + 24, 24, 8 * 9, 8 * 9)

  setColor(4)

  sequencer.currentStep = clamp(sequencer.currentStep, 0, sequencer.patterns[sequencer.currentPattern].rows.high)

  if sequencer.currentStep < pattern.rows.high:
    if sequencer.bindings[sequencer.currentColumn].machine != nil:
      var (voice, param) = sequencer.bindings[sequencer.currentColumn].getParameter()
      let value = pattern.rows[sequencer.currentStep][sequencer.currentColumn]
      if value != Blank and sequencer.bindings[sequencer.currentColumn].machine != nil:
        let value = mapSeqValueToParamValue(value, param)
        print("value: " & param[].valueString(value), 1, screenHeight - 8)
      if param.kind == Note:
        printr("oct: " & $baseOctave, colsPerPattern * 17, screenHeight - 8)

  drawParams(screenWidth - 128, 8, 126, screenHeight - 9)

method process*(self: Sequencer) =
  let pattern = patterns[playingPattern]
  if pattern == nil:
    return
  if playing:
    if subTick == 0.0:
      # update all params first then call onchange on all
      # this is so multiple changes can be made at once
      for i,binding in bindings:
        if binding.machine != nil:
          var targetMachine = binding.machine
          var (voice,param) = targetMachine.getParameter(binding.param)
          if pattern.rows[step][i] == Blank:
            continue
          elif not param.deferred:
            let value = pattern.rows[step][i]
            param.value = mapSeqValueToParamValue(value, param)
            param.onchange(param.value, voice)

      for i,binding in bindings:
        if binding.machine != nil:
          var targetMachine = binding.machine
          var (voice,param) = targetMachine.getParameter(binding.param)
          if pattern.rows[step][i] == Blank:
            continue
          elif param.deferred:
            let value = pattern.rows[step][i]
            param.value = mapSeqValueToParamValue(value, param)
            param.onchange(param.value, voice)

    let ticksPerBeat = if ticksPerBeat < 0: 1.0 / -ticksPerBeat.float else: ticksPerBeat.float
    subTick += invSampleRate * beatsPerSecond() * ticksPerBeat.float
    if subTick >= 1.0:
      step += 1
      subTick = 0.0
      if step > pattern.rows.high:
        step = 0
        if not looping:
          playing = false

    globalParams[4].value = step.float / pattern.rows.high.float

proc setValue(self: Sequencer, newValue: int) =
  var pattern = patterns[currentPattern]

  var machine = bindings[currentColumn].machine
  if machine == nil:
    return
  var (voice, param) = machine.getParameter(bindings[currentColumn].param)

  var value = pattern.rows[currentStep][currentColumn]

  if newValue == Blank:
    value = Blank
  else:
    if param.kind == Int or param.kind == Float:
      if value == Blank:
        value = 0
      let k = if subColumn == 0: 2 elif subColumn == 1: 1 else: 0
      let d = (value/(10^k)) mod 10
      value = value + (newValue - d) * (10^k)

    elif param.kind == Note:
      if subColumn == 0:
        value = newValue
      elif subColumn == 1:
        if value != Blank:
          # just change octave
          let note = value mod 12
          value = ((newValue + 1) * 12) + note
    elif param.kind == Trigger:
      value = if newValue == 1: 1 else: 0

  pattern.rows[currentStep][currentColumn] = value

  currentStep += 1
  if currentStep > pattern.rows.high:
    currentStep = pattern.rows.high

method key*(self: SequencerView, key: KeyboardEventPtr, down: bool): bool =
  var s = Sequencer(machine)

  let scancode = key.keysym.scancode
  let ctrl = ctrl()

  let pattern = s.patterns[s.currentPattern]

  if scancode == SDL_SCANCODE_L and ctrl and down:
    # toggle loop
    if s.looping:
      s.globalParams[2].value = 0.0
      s.globalParams[2].onchange(0.0)
    else:
      s.globalParams[2].value = 1.0
      s.globalParams[2].onchange(1.0)
    return true
  elif scancode == SDL_SCANCODE_C and ctrl and down:
    clipboard = newPattern()
    clipboard.rows = pattern.rows
    return true
  elif scancode == SDL_SCANCODE_V and ctrl and down:
    if clipboard != nil:
      pattern.rows = clipboard.rows
    return true
  elif scancode == SDL_SCANCODE_LEFT and down:
    if ctrl:
      # prev pattern
      s.currentPattern -= 1
      if s.currentPattern < 0:
        s.currentPattern = s.patterns.high
      if s.patterns[s.currentPattern] == nil:
        s.patterns[s.currentPattern] = newPattern()
      return true
    else:
      s.subColumn -= 1
      if s.subColumn < 0:
        s.currentColumn -= 1

        if s.currentColumn < 0:
          s.currentColumn = colsPerPattern-1

        var maxSubCol = 0
        var targetMachine = s.bindings[s.currentColumn].machine
        if targetMachine == nil:
          maxSubCol = 0
        else:
          var (voice, targetParam) = targetMachine.getParameter(s.bindings[s.currentColumn].param)
          maxSubCol = if targetParam.kind == Note: 1 elif targetParam.kind == Trigger: 0 else: 2
        s.subColumn = maxSubCol
      if s.currentColumn < 0:
        s.currentColumn = colsPerPattern - 1
      return true
  elif scancode == SDL_SCANCODE_RIGHT and down:
    if ctrl:
      # next pattern
      s.currentPattern += 1
      if s.currentPattern > s.patterns.high:
        s.patterns.add(newPattern())
      if s.patterns[s.currentPattern] == nil:
        s.patterns[s.currentPattern] = newPattern()
      return true
    else:
      var maxSubCol = 0
      var targetMachine = s.bindings[s.currentColumn].machine
      if targetMachine == nil:
        maxSubCol = 0
      else:
        var (voice, targetParam) = targetMachine.getParameter(s.bindings[s.currentColumn].param)
        maxSubCol = if targetParam.kind == Note: 1 elif targetParam.kind == Trigger: 0 else: 2

      s.subColumn += 1
      if s.subColumn > maxSubCol:
        s.subColumn = 0
        s.currentColumn += 1
        if s.currentColumn > colsPerPattern - 1:
          s.currentColumn = 0
      return true
  elif scancode == SDL_SCANCODE_UP and down:
    s.currentStep -= (if ctrl: s.ticksPerBeat else: 1)
    if s.currentStep < 0:
      s.currentStep = pattern.rows.high
    return true
  elif scancode == SDL_SCANCODE_DOWN and down:
    s.currentStep += (if ctrl: s.ticksPerBeat else: 1)
    if s.currentStep > pattern.rows.high:
      s.currentStep = 0
    return true
  elif key.keysym.scancode == SDL_SCANCODE_PAGEUP and down:
    if ctrl:
      let length = s.patterns[s.currentPattern].rows.len
      s.patterns[s.currentPattern].rows.setLen(max(length div 2, 1))
      return true
  elif key.keysym.scancode == SDL_SCANCODE_PAGEDOWN and down:
    if ctrl:
      let length = s.patterns[s.currentPattern].rows.len
      s.patterns[s.currentPattern].rows.setLen(length * 2)
      # fill the new spaces with Blank
      for i in length..(length*2)-1:
        for c in 0..colsPerPattern-1:
          s.patterns[s.currentPattern].rows[i][c] = Blank
      return true
  elif key.keysym.scancode == SDL_SCANCODE_SPACE and down:
    if s.currentPattern == s.playingPattern:
      s.playing = not s.playing
      if s.playing:
        s.step = s.currentStep
        s.subTick = 0.0
    else:
      s.globalParams[0].value = s.currentPattern.float
      s.globalParams[0].onchange(s.currentPattern.float)
      s.playing = true
    return true
  elif key.keysym.scancode == SDL_SCANCODE_HOME and down:
    if ctrl:
      s.step = 0
      s.subTick = 0.0
    else:
      s.currentStep = 0
    return true
  elif key.keysym.scancode == SDL_SCANCODE_END and down:
    s.currentStep = pattern.rows.high
    return true
  elif key.keysym.scancode == SDL_SCANCODE_MINUS and down:
    var (voice, param) = s.getParameter(1)
    s.ticksPerBeat -= 1
    param.value = s.ticksPerBeat.float
    param.onchange(param.value, voice)
    return true
  elif key.keysym.scancode == SDL_SCANCODE_EQUALS and down:
    var (voice, param) = s.getParameter(1)
    s.ticksPerBeat += 1
    param.value = s.ticksPerBeat.float
    param.onchange(param.value, voice)
    return true
  elif key.keysym.scancode == SDL_SCANCODE_BACKSPACE and down:
    var menu = newMenu(point2d(
      (s.currentColumn * 16 + 12).float,
      8.float
    ), "bind machine")

    for i in 0..machines.high:
      if machines[i] == self.machine:
        continue
      (proc() =
        let targetMachine = machines[i]
        menu.items.add(newMenuItem(targetMachine.name) do():
          echo "selected ", s.currentColumn, " to ", targetMachine.name
          pushMenu(targetMachine.getParameterMenu(menu.pos, "bind param") do(paramId: int):
            s.bindings[s.currentColumn].machine = targetMachine
            s.bindings[s.currentColumn].param = paramId
            popMenu()
            popMenu()
          )
        )
      )()
    pushMenu(menu)
    return true

  # if current column is a note type:
  if not ctrl and s.bindings[s.currentColumn].machine != nil:
    var targetMachine = s.bindings[s.currentColumn].machine
    var (voice, targetParam) = targetMachine.getParameter(s.bindings[s.currentColumn].param)
    case targetParam.kind:
    of Note:
      if s.subColumn == 0:
        let note = keyToNote(key)
        if note >= 0 and down:
          s.setValue(note)
          return true
        if note == OffNote and down:
          s.setValue(OffNote)
          return true
        if note == Blank and down:
          s.setValue(Blank)
          return true
      elif s.subColumn == 1:
        if down:
          case scancode:
          of SDL_SCANCODE_0:
            s.setValue(0)
            return true
          of SDL_SCANCODE_1:
            s.setValue(1)
            return true
          of SDL_SCANCODE_2:
            s.setValue(2)
            return true
          of SDL_SCANCODE_3:
            s.setValue(3)
            return true
          of SDL_SCANCODE_4:
            s.setValue(4)
            return true
          of SDL_SCANCODE_5:
            s.setValue(5)
            return true
          of SDL_SCANCODE_6:
            s.setValue(6)
            return true
          of SDL_SCANCODE_7:
            s.setValue(7)
            return true
          of SDL_SCANCODE_8:
            s.setValue(8)
            return true
          of SDL_SCANCODE_9:
            s.setValue(9)
            return true
          of SDL_SCANCODE_PERIOD:
            s.setValue(Blank)
            return true
          else:
            discard
    of Int, Float, Trigger, Bool:
      if down:
        case scancode:
        of SDL_SCANCODE_0:
          s.setValue(0)
          return true
        of SDL_SCANCODE_1:
          s.setValue(1)
          return true
        of SDL_SCANCODE_2:
          s.setValue(2)
          return true
        of SDL_SCANCODE_3:
          s.setValue(3)
          return true
        of SDL_SCANCODE_4:
          s.setValue(4)
          return true
        of SDL_SCANCODE_5:
          s.setValue(5)
          return true
        of SDL_SCANCODE_6:
          s.setValue(6)
          return true
        of SDL_SCANCODE_7:
          s.setValue(7)
          return true
        of SDL_SCANCODE_8:
          s.setValue(8)
          return true
        of SDL_SCANCODE_9:
          s.setValue(9)
          return true
        of SDL_SCANCODE_PERIOD:
          s.setValue(Blank)
          return true
        else:
          discard

  return false

method event(self: SequencerView, event: Event): bool =
  var s = Sequencer(self.machine)
  case event.kind:
  of KeyUp, KeyDown:
    let down = event.kind == KeyDown
    if self.key(event.key, down):
      return true

  of MouseButtonDown, MouseButtonUp:
    let mv = mouse()
    let down = event.kind == MouseButtonDown

    # select pattern cell
    if mv.y > 24 and mv.x <= (colsPerPattern * 17) + 9:
      if event.button.button == 1 and down:
        let row = (mv.y - 24) div 8 - scroll
        s.currentStep = clamp(row, 0, s.patterns[s.currentPattern].rows.high)
        let col = (mv.x - 9) div 17
        s.currentColumn = clamp(col, 0, colsPerPattern-1)
        return true

    # if mouse is in pattern selector, select pattern
    elif mv.y > 24 and mv.x > colsPerPattern * 17 + 9 and mv.x < screenWidth - 128:
      const squareSize = 12
      const padding = 2
      let y = clamp((mv.y - 24) div (squareSize + padding), 0, 7)
      let x = clamp((mv.x - (colsPerPattern * 17 + 9 + 12)) div (squareSize + padding), 0, 7)
      let patId = clamp(y * 8 + x, 0, 63)

      if event.button.button == 1:
        s.currentPattern = patId
        if s.currentPattern > s.patterns.high:
          s.patterns.setLen(s.currentPattern+1)
          if s.patterns[s.currentPattern] == nil:
            s.patterns[s.currentPattern] = newPattern()
        return
      elif event.button.button == 3 and down:
        if s.patterns[patId] == nil:
          s.patterns[patId] = newPattern()
        else:
          if s.patterns[patId].color == PatternColor.high:
            s.patterns[patId].color = Green
          else:
            s.patterns[patId].color.inc()

  of MouseMotion:
    discard

  else:
   discard
  return false

proc `$`(self: Pattern): string =
  result = ""
  if rows != nil:
    for row in rows:
      for i in 0..colsPerPattern-1:
        result &= $row[i]
        if i < colsPerPattern-1:
          result &= ","
      result &= "\n"

method saveExtraData(self: Sequencer): string =
  # export pattern data
  result = "PATTERNS\n"
  for pattern in patterns:
    if pattern == nil:
      result &= "END\n"
    else:
      result &= $pattern
      result &= "END\n"


import strutils

method loadExtraData(self: Sequencer, data: string) =
  echo "loading extra Sequencer data"
  patterns = newSeq[Pattern](64)
  var pattern: Pattern
  var patId = 0
  for line in data.splitLines:
    let sline = line.strip()
    if sline == "PATTERNS":
      pattern = newPattern(0)
      continue
    if pattern != nil:
      if sline == "END":
        if pattern.rows.len == 0:
          patterns[patId] = nil
        else:
          patterns[patId] = pattern
        pattern = newPattern(0)
        patId += 1
        if patId > 63:
          break
      else:
        pattern.rows.setLen(pattern.rows.len+1)
        for i,col in pairs(sline.split(",")):
          pattern.rows[pattern.rows.high][i] = parseInt(col)

{.this:self.}

import math
import strutils

import nico
import nico/vec

import ../../common
import ../../util

import ../../core/basemachine
import ../../ui/machineview
import ../../ui/menu
import ../../machines/master


const colsPerPattern = 8
const maxPatterns = 64

type
  PatternColor = enum
    Green
    Blue
    Red
    Yellow
    White
  Pattern* = ref object
    name*: string
    color*: PatternColor
    rows*: seq[array[colsPerPattern, int]]
    loopStart*: int
    loopEnd*: int
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
    groove*: int
    humanization: float32

    playingPattern*: int
    nextPattern*: int

    humanizationMap: seq[float32]

    step*: int
    ticksPerBeat*: int
    beatsPerBar*: int
    playing: bool
    subTick: float
    looping: bool
    recording: bool
    recordColumn: int

  SequencerView* = ref object of MachineView
    clipboard: Pattern

proc mapSeqValueToParamValue(value: int, param: ptr Parameter): float =
  case param.kind:
  of Bool:
    return (if value == 0: 0.0 else: 1.0)
  of Note:
    return value.float
  of Int:
    return clamp(value.float, param.min, param.max)
  of Trigger:
    return (if value == 1: 1.0 else: 0.0)
  of Float:
    return lerp(param.min, param.max, invLerp(0.0, 999.0, clamp(value, 0, 999).float))

proc mapParamValueToSeqValue(value: float, param: ptr Parameter): int =
  case param.kind:
  of Bool:
    return (if value == 0.0: 0 else: 1)
  of Note:
    return value.int
  of Int:
    return value.int
  of Trigger:
    return (if value == 0.0: 0 else: 1)
  of Float:
    return lerp(0'f, 999'f, invLerp(param.min, param.max, value)).int

proc newPattern*(length: int = 16): Pattern =
  result = new(Pattern)
  result.rows = newSeq[array[colsPerPattern, int]](length)
  result.name = ""
  for row in mitems(result.rows):
    for col in mitems(row):
      col = Blank

proc setPattern(self: Sequencer, patId: int) =
  self.currentPattern = clamp(patId, 0, self.patterns.high)
  if self.patterns[self.currentPattern] == nil:
    self.patterns[self.currentPattern] = newPattern()
  self.currentStep = clamp(self.currentStep, 0, self.patterns[self.currentPattern].rows.high)

proc playPattern(self: Sequencer, patId: int) =
  self.playingPattern = clamp(patId, 0, self.patterns.high)
  self.subTick = 0'f

  if self.patterns[self.playingPattern] == nil:
    self.playing = false
    self.step = 0
  else:
    self.playing = true
    self.step = self.patterns[self.playingPattern].loopStart

    if self.humanization > 0:
      self.humanizationMap = newSeq[float32](self.patterns[self.playingPattern].rows.len * colsPerPattern)
      var sum = 0'f
      for i in 0..<self.humanizationMap.len:
        self.humanizationMap[i] = 1.0'f + rnd(self.humanization)
        sum += self.humanizationMap[i]
      for i in 0..<self.humanizationMap.len:
        self.humanizationMap[i] /= sum
        self.humanizationMap[i] *= self.humanizationMap.len.float32 * colsPerPattern

method init*(self: Sequencer) =
  procCall init(Machine(self))

  patterns = newSeq[Pattern](maxPatterns)
  patterns[0] = newPattern(16)
  ticksPerBeat = 4
  nextPattern = -1
  beatsPerBar = 4
  subTick = 0.0
  name = "seq"
  nOutputs = 0
  nInputs = 0
  nBindings = 8
  bindings.setLen(8)
  useMidi = true
  stereo = false
  humanization = 0'f

  globalParams.add([
    Parameter(kind: Int, name: "pattern", min: 0.0, max: 63.0, default: 0.0, ignoreSave: true, onchange: proc(newValue: float, voice: int) =
      self.playPattern(newValue.int)
    , getValueString: proc(value: float, voice: int): string =
      if self.patterns[value.int] != nil:
        return $value.int & ": " & self.patterns[value.int].name
      else:
        return $value.int & ": empty"
    ),
    Parameter(kind: Int, name: "tpb", min: -32.0, max: 32.0, default: 4.0, onchange: proc(newValue: float, voice: int) =
      self.ticksPerBeat = newValue.int
    , getValueString: proc(value: float, voice: int): string =
      return (if value < 0: "1/" & $(-value.int) else: $value.int)
    ),
    Parameter(kind: Int, name: "groove", min: -4.0, max: 4.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.groove = newValue.int
    ),
    Parameter(kind: Float, name: "human", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.humanization = newValue.float32
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
    Parameter(kind: Int, name: "bpb", min: 1.0, max: 16.0, default: 4.0, onchange: proc(newValue: float, voice: int) =
      self.beatsPerBar = newValue.int
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
    if playingPattern == currentPattern:
      if pattern.loopStart != pattern.loopEnd:
        setColor(10)
        if pattern.loopStart == i:
          line(x, y, x + colsPerPattern * 17, y)
        if pattern.loopEnd == i:
          line(x, y + 7, x + colsPerPattern * 17, y + 7)
      if step == i:
        setColor(2)
        let y = y + (subTick * 8.0).int
        line(x, y, x + colsPerPattern * 17, y)

    if ticksPerBeat > 0:
      if i mod ticksPerBeat == 0 and (i div ticksPerBeat) mod beatsPerBar == 0:
        setColor(0)
        line(x, y, x + colsPerPattern * 17, y)

    # draw step number
    if ticksPerBeat < 1 or i mod ticksPerBeat == 0:
      setColor(if i == currentStep: 12 elif ticksPerBeat > 1 and i %% ticksPerBeat == 0: 6 else: 13)
      if ticksPerBeat < 1:
        printr($i, x + 9, y + 1)
      else:
        printr($(((i div ticksPerBeat) mod beatsPerBar) + 1), x + 9, y + 1)

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
        of Int,Float:
          # we want to split this into 3 columns, one for each char
          var str = if val == Blank: "..." else: align($val, 3, '.')
          for c in 0..2:
            setColor(if i == currentStep and col == currentColumn and c == subColumn: 12 elif ticksPerBeat > 1 and i %% ticksPerBeat == 0: 6 else: 13)
            print(str[c..c], x + col * 16 + 12 + c * 4, y + 1)
        of Bool:
          setColor(if i == currentStep and col == currentColumn: 12 elif ticksPerBeat > 1 and i %% ticksPerBeat == 0: 6 else: 13)
          print(if val == 1: " 1 " elif val == 0: " 0 " else: " . ", x + col * 16 + 12, y + 1)
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
    rectfill(x + colsPerPattern * 17 + 2, y + ((startStep.float/pattern.rows.high.float) * h.float).int, x + colsPerPattern * 17 + 7, y + ((endStep.float/pattern.rows.high.float) * h.float).int)
    if playingPattern == currentPattern:
      setColor(2)
      rectfill(x + colsPerPattern * 17 + 2, y + ((step.float/pattern.rows.len.float) * h.float).int, x + colsPerPattern * 17 + 7, y + (((step+1).float/pattern.rows.len.float) * h.float).int)
    setColor(7)
    rectfill(x + colsPerPattern * 17 + 2, y + ((currentStep.float/pattern.rows.len.float) * h.float).int, x + colsPerPattern * 17 + 7, y + (((currentStep+1).float/pattern.rows.len.float) * h.float).int)

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
            if (patId == playingPattern and playing) or (patId == nextPattern and frame mod 30 < 15): 11 else: 3
          of Blue:
            if (patId == playingPattern and playing) or (patId == nextPattern and frame mod 30 < 15): 12 else: 1
          of Red:
            if (patId == playingPattern and playing) or (patId == nextPattern and frame mod 30 < 15): 8 else: 2
          of Yellow:
            if (patId == playingPattern and playing) or (patId == nextPattern and frame mod 30 < 15): 9 else: 4
          of White:
            if (patId == playingPattern and playing) or (patId == nextPattern and frame mod 30 < 15): 7 else: 5
      )
      rectfill(x + col * (squareSize + padding), y + row * (squareSize + padding), x + col * (squareSize + padding) + (squareSize - 1), y + row * (squareSize + padding) + (squareSize - 1))

      setColor(if patId == currentPattern: 7 else: 0)
      rect(x + col * (squareSize + padding), y + row * (squareSize + padding), x + col * (squareSize + padding) + (squareSize - 1), y + row * (squareSize + padding) + (squareSize - 1))

  var y = y + 9 * (squareSize + padding)
  let pattern = patterns[currentPattern]
  setColor(6)
  print("pattern " & $currentPattern & ": " & pattern.name, x, y)
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
  y += 8
  if self.recording:
    setColor(8)
  print("recording: " & (if self.recording: "yes" else: "no"), x, y)


method update(self: SequencerView, dt: float) =
  var s = Sequencer(machine)

  updateParams(screenWidth - 128, 8, 126, screenHeight - 9)

method draw*(self: SequencerView) =
  cls()
  let sequencer = Sequencer(machine)

  let pattern = sequencer.patterns[sequencer.currentPattern]

  let startStep = clamp(sequencer.currentStep-7,0,pattern.rows.high)

  setColor(6)
  printr(sequencer.name, screenWidth - 1, 1)

  # draw bindings
  block:
    setColor(4)
    if sequencer.bindings[sequencer.currentColumn].machine != nil:
      # if column is bound
      var binding = sequencer.bindings[sequencer.currentColumn]
      var (voice, param) = binding.machine.getParameter(binding.param)
      print(binding.machine.name & ": " & (if voice != -1: $voice & ": " else: "") & param.name, 1, 9+8)
      # show current value
      let value = pattern.rows[sequencer.currentStep][sequencer.currentColumn]
      let valueFloat = mapSeqValueToParamValue(value, param)
      if param.getValueString != nil:
        print(param.getValueString(valueFloat, voice), 1, 9+8+8)
      else:
        print(valueFloat.formatFloat(ffDecimal, 4), 1, 9+8+8)
    else:
      print($(sequencer.currentColumn+1) & ": unbound", 1, 9+8)

    for i in 0..colsPerPattern-1:
      if sequencer.bindings[i].machine == nil:
        rect(i * 16 + 13, 8, i * 16 + 13 + 12, 15)
      else:
        rectfill(i * 16 + 13, 8, i * 16 + 13 + 12, 15)

  sequencer.drawPattern(1,32,screenWidth - 1,screenHeight - 49)

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
        # draw keyboard
        sspr(0,93,48,35, screenWidth - 48 * 2, screenHeight - 35 * 2 - 16, 48 * 2, 35 * 2)
        # draw octaves
        setColor(7)
        print($(baseOctave - 1), screenWidth - 110, screenHeight - 24, 2)
        print($baseOctave, screenWidth - 110, screenHeight - 56, 2)


  drawParams(screenWidth - 128, 8, 126, screenHeight - 100)


method process*(self: Sequencer) =
  let pattern = patterns[playingPattern]
  if pattern == nil:
    return
  if playing:
    if subTick == 0.0:
      if recording:
        # read binding param value into cell
        var pat = self.patterns[playingPattern]
        for i in 0..<colsPerPattern:
          if bindings[i].isBound():
            var (voice, param) = bindings[i].machine.getParameter(bindings[i].param)
            pat.rows[step][i] = mapParamValueToSeqValue(param.value, param)

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

    var realTicksPerBeat = if ticksPerBeat < 0: 1.0 / -ticksPerBeat.float else: ticksPerBeat.float
    if realTicksPerBeat >= 1:
      if groove > 0:
        if step mod 2 == 0:
          realTicksPerBeat += groove.float32
        else:
          realTicksPerBeat -= groove.float32
    if self.humanization > 0 and self.humanizationMap.len == pattern.rows.len:
      subTick += invSampleRate * beatsPerSecond() * realTicksPerBeat.float * self.humanizationMap[self.step]
    else:
      subTick += invSampleRate * beatsPerSecond() * realTicksPerBeat.float
    if subTick >= 1.0:
      step += 1
      subTick = 0.0
      if step > pattern.rows.high or (pattern.loopEnd != pattern.loopStart and step > pattern.loopEnd):
        # reached end of pattern
        if nextPattern != playingPattern and nextPattern >= 0:
          playPattern(nextPattern)
          nextPattern = -1
        else:
          playPattern(playingPattern)
          if not looping:
            playing = false

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
      let d = (value/(10^k)).int mod 10
      value = value + (newValue - d) * (10^k).int

    elif param.kind == Note:
      if subColumn == 0:
        value = newValue
      elif subColumn == 1:
        if value != Blank:
          # just change octave
          let note = value mod 12
          value = ((newValue + 1) * 12) + note
    elif param.kind == Trigger or param.kind == Bool:
      value = if newValue == 1: 1 else: 0

  pattern.rows[currentStep][currentColumn] = value

  currentStep += 1
  if currentStep > pattern.rows.high:
    currentStep = pattern.rows.high

proc key*(self: SequencerView, event: Event): bool =
  var s = Sequencer(machine)

  let scancode = event.scancode
  let ctrl = (event.mods and KMOD_CTRL) != 0
  let down = event.kind == ekKeyDown

  let pattern = s.patterns[s.currentPattern]

  if scancode == SCANCODE_R and ctrl and down:
    s.recording = not s.recording
  if scancode == SCANCODE_L and ctrl and down:
    # toggle loop
    if s.looping:
      s.globalParams[4].value = 0.0
      s.globalParams[4].onchange(0.0, -1)
    else:
      s.globalParams[4].value = 1.0
      s.globalParams[4].onchange(1.0, -1)
    return true
  elif scancode == SCANCODE_G and ctrl and down:
    if s.groove == 0:
      s.globalParams[2].value = 1.0
      s.globalParams[2].onchange(1.0, -1)
    else:
      s.globalParams[2].value = 0.0
      s.globalParams[2].onchange(0.0, -1)
    return true
  elif scancode == SCANCODE_B and ctrl and down:
    pattern.loopStart = s.currentStep
  elif scancode == SCANCODE_E and ctrl and down:
    pattern.loopEnd = s.currentStep
  elif scancode == SCANCODE_C and ctrl and down:
    clipboard = newPattern()
    clipboard.rows = pattern.rows
    return true
  elif scancode == SCANCODE_V and ctrl and down:
    if clipboard != nil:
      pattern.rows = clipboard.rows
    return true
  elif scancode == SCANCODE_LEFT and down:
    if ctrl:
      # prev pattern
      s.setPattern(s.currentPattern-1)
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
  elif scancode == SCANCODE_RIGHT and down:
    if ctrl:
      # next pattern
      s.setPattern(s.currentPattern+1)
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
  elif scancode == SCANCODE_UP and down:
    s.currentStep -= (if ctrl: s.ticksPerBeat else: 1)
    if s.currentStep < 0:
      s.currentStep = pattern.rows.high
    return true
  elif scancode == SCANCODE_DOWN and down:
    s.currentStep += (if ctrl: s.ticksPerBeat else: 1)
    if s.currentStep > pattern.rows.high:
      s.currentStep = 0
    return true
  elif scancode == SCANCODE_PAGEUP and down:
    if ctrl:
      let length = s.patterns[s.currentPattern].rows.len
      s.patterns[s.currentPattern].rows.setLen(max(length div 2, 1))
      return true
    else:
      s.currentStep = max(s.currentStep - s.beatsPerBar * s.ticksPerBeat, 0)
      return true
  elif scancode == SCANCODE_PAGEDOWN and down:
    if ctrl:
      let length = s.patterns[s.currentPattern].rows.len
      s.patterns[s.currentPattern].rows.setLen(length * 2)
      # fill the new spaces with Blank
      for i in length..(length*2)-1:
        for c in 0..colsPerPattern-1:
          s.patterns[s.currentPattern].rows[i][c] = Blank
      return true
    else:
      s.currentStep = clamp(s.currentStep + s.beatsPerBar * s.ticksPerBeat, 0, s.patterns[s.currentPattern].rows.high)
      return true
  elif scancode == SCANCODE_SPACE and down:
    if s.currentPattern == s.playingPattern:
      s.playing = not s.playing
      if s.playing:
        if ctrl:
          s.step = s.currentStep
        s.subTick = 0.0
    else:
      s.globalParams[0].value = s.currentPattern.float
      s.globalParams[0].onchange(s.currentPattern.float, -1)
      s.playing = true
    return true
  elif scancode == SCANCODE_HOME and down:
    if ctrl:
      s.step = 0
      s.subTick = 0.0
    else:
      s.currentStep = 0
    return true
  elif scancode == SCANCODE_END and down:
    s.currentStep = pattern.rows.high
    return true
  elif scancode == SCANCODE_MINUS and down:
    # lower tpb
    var param = s.getParameterByName("tpb")
    s.ticksPerBeat -= 1
    param.value = s.ticksPerBeat.float
    param.onchange(param.value, -1)
    return true
  elif scancode == SCANCODE_EQUALS and down:
    # increase tpb
    var param = s.getParameterByName("tpb")
    s.ticksPerBeat += 1
    param.value = s.ticksPerBeat.float
    param.onchange(param.value, -1)
    return true
  elif down and scancode == SCANCODE_BACKSPACE:
    s.setValue(Blank)
  elif down and scancode == SCANCODE_DELETE:
    if ctrl:
      # remove current cell and move everything up one
      let pat = s.patterns[s.currentPattern]
      # copy all rows below current up one
      for i in s.currentStep..<pat.rows.high:
        pat.rows[i][s.currentColumn] = pat.rows[i+1][s.currentColumn]
      pat.rows[pat.rows.high][s.currentColumn] = Blank
      return true

    else:
      # remove current row and move everything up one row
      let pat = s.patterns[s.currentPattern]
      # copy all rows below current up one
      for i in s.currentStep..<pat.rows.high:
        pat.rows[i] = pat.rows[i+1]
      for col in 0..<colsPerPattern:
        pat.rows[pat.rows.high][col] = Blank
      return true

  elif down and scancode == SCANCODE_INSERT:
    if ctrl:
      # insert a new row, move everything down one row
      let pat = s.patterns[s.currentPattern]
      # copy all rows below current down one
      for i in countdown(pat.rows.high, s.currentStep+1):
        pat.rows[i][s.currentColumn] = pat.rows[i-1][s.currentColumn]
      pat.rows[s.currentStep][s.currentColumn] = Blank
      return true

    else:
      # insert a new row, move everything down one row
      let pat = s.patterns[s.currentPattern]
      # copy all rows below current down one
      for i in countdown(pat.rows.high, s.currentStep+1):
        pat.rows[i] = pat.rows[i-1]
      for col in 0..<colsPerPattern:
        pat.rows[s.currentStep][col] = Blank
      return true

  elif scancode == SCANCODE_T and ctrl and down:
    var menu = newMenu(vec2f(
      (s.currentColumn * 16 + 12).float,
      8.float
    ), "bind machine")

    if s.bindings[s.currentColumn].machine != nil:
      menu.items.add(newMenuItem("- unbind -") do():
        s.bindings[s.currentColumn].machine = nil
        popMenu()
      )

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
        let note = keyToNote(event.keycode)
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
          of SCANCODE_0:
            s.setValue(0)
            return true
          of SCANCODE_1:
            s.setValue(1)
            return true
          of SCANCODE_2:
            s.setValue(2)
            return true
          of SCANCODE_3:
            s.setValue(3)
            return true
          of SCANCODE_4:
            s.setValue(4)
            return true
          of SCANCODE_5:
            s.setValue(5)
            return true
          of SCANCODE_6:
            s.setValue(6)
            return true
          of SCANCODE_7:
            s.setValue(7)
            return true
          of SCANCODE_8:
            s.setValue(8)
            return true
          of SCANCODE_9:
            s.setValue(9)
            return true
          of SCANCODE_PERIOD:
            s.setValue(Blank)
            return true
          else:
            discard
    of Int, Float, Trigger, Bool:
      if down:
        case scancode:
        of SCANCODE_0:
          s.setValue(0)
          return true
        of SCANCODE_1:
          s.setValue(1)
          return true
        of SCANCODE_2:
          s.setValue(2)
          return true
        of SCANCODE_3:
          s.setValue(3)
          return true
        of SCANCODE_4:
          s.setValue(4)
          return true
        of SCANCODE_5:
          s.setValue(5)
          return true
        of SCANCODE_6:
          s.setValue(6)
          return true
        of SCANCODE_7:
          s.setValue(7)
          return true
        of SCANCODE_8:
          s.setValue(8)
          return true
        of SCANCODE_9:
          s.setValue(9)
          return true
        of SCANCODE_PERIOD:
          s.setValue(Blank)
          return true
        else:
          discard

  return false

method event(self: SequencerView, event: Event): bool =
  var s = Sequencer(self.machine)
  case event.kind:
  of ekKeyUp, ekKeyDown:
    let down = event.kind == ekKeyDown
    if self.key(event):
      return true

  of ekMouseButtonDown, ekMouseButtonUp:
    let mv = mouseVec()
    let down = event.kind == ekMouseButtonDown
    let ctrl = (event.mods and KMOD_CTRL) != 0

    # select pattern cell
    if mv.y > 24 and mv.x <= (colsPerPattern * 17) + 9:
      if event.button == 1 and down:
        let row = (mv.y - 24) div 8 - scroll
        s.currentStep = clamp(row, 0, s.patterns[s.currentPattern].rows.high)
        let col = (mv.x - 9) div 17
        s.currentColumn = clamp(col, 0, colsPerPattern-1)
        return true

    # if mouse is in pattern selector, select pattern
    elif down and mv.y > 24 and mv.x > colsPerPattern * 17 + 9 and mv.x < screenWidth - 128:
      const squareSize = 12
      const padding = 2
      let y = clamp((mv.y - 24) div (squareSize + padding), 0, 7)
      let x = clamp((mv.x - (colsPerPattern * 17 + 9 + 12)) div (squareSize + padding), 0, 7)
      let patId = clamp(y * 8 + x, 0, 63)

      if event.button == 1:
        if ctrl():
          if s.patterns[patId] != nil:
            s.nextPattern = patId
          return
        else:
          s.setPattern(patId)
          return
      elif event.button == 3 and down:
        if s.patterns[patId] == nil:
          s.patterns[patId] = newPattern()
        else:
          if s.patterns[patId].color == PatternColor.high:
            s.patterns[patId].color = Green
          else:
            s.patterns[patId].color.inc()

  of ekMouseMotion:
    discard

  else:
   discard
  return false

proc `$`(self: Pattern): string =
  result = ""
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
  patterns = newSeq[Pattern](maxPatterns)
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

method getMenu*(self: Sequencer, mv: Vec2f): Menu =
  result = procCall getMenu(Machine(self), mv)
  if not self.recording:
    result.items.add(newMenuItem("record") do():
      self.recording = true
      popMenu()
    )
  else:
    result.items.add(newMenuItem("stop record") do():
      self.recording = false
      popMenu()
    )

method midiEvent*(self: Sequencer, event: MidiEvent) =
  if recording:
    if event.command == 1:
      patterns[currentPattern].rows[currentStep][currentColumn] = event.data1.int
      if currentStep < patterns[currentPattern].rows.high:
        currentStep += 1

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
  Pattern* = ref object of RootObj
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
    #bindings*: array[colsPerPattern, tuple[machine: Machine, param: int]]
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
  SequencerView* = ref object of MachineView
    menu: Menu

proc newPattern*(): Pattern =
  result = new(Pattern)
  result.rows = newSeq[array[colsPerPattern, int]](16)
  for row in mitems(result.rows):
    for col in mitems(row):
      col = Blank

method init*(self: Sequencer) =
  procCall init(Machine(self))

  patterns = newSeq[Pattern]()
  patterns.add(newPattern())
  ticksPerBeat = 4
  subTick = 0.0
  name = "seq"
  nOutputs = 0
  nInputs = 0
  nBindings = 8
  bindings.setLen(8)

  globalParams.add([
    Parameter(kind: Int, name: "pattern", min: -1.0, max: 128.0, default: 0.0, value: 0.0, onchange: proc(newValue: float, voice: int) =
      if newValue < 0.0:
        self.subTick = 0.0
        self.step = 0
        self.playing = false
      else:
        self.playingPattern = clamp(newValue.int, 0, self.patterns.high)
        self.subTick = 0.0
        self.step = 0
        self.playing = true
    , getValueString: proc(value: float, voice: int): string =
      return $self.playingPattern
    ),
    Parameter(kind: Int, name: "tpb", min: -32.0, max: 32.0, default: 4.0, value: 4.0, onchange: proc(newValue: float, voice: int) =
      self.ticksPerBeat = newValue.int
    , getValueString: proc(value: float, voice: int): string =
      return (if self.ticksPerBeat < 0: "1/" & $(-self.ticksPerBeat) else: $self.ticksPerBeat)
    ),
  ])

  for param in mitems(self.globalParams):
    param.value = param.default
    param.onchange(param.value, -1)

proc newSequencerView(machine: Machine): View =
  var v = new(SequencerView)
  v.machine = machine
  v.menu = nil
  return v

method getMachineView*(self: Sequencer): View =
  return newSequencerView(self)

proc newSequencer*(): Machine =
  var sequencer = new(Sequencer)
  sequencer.init()
  return sequencer

registerMachine("sequencer", newSequencer)

method drawBox*(self: Sequencer) =
  # draw container
  let x = pos.x - 15
  let y = pos.y - 15

  setColor(1)
  rectfill(pos.x - 17, pos.y - 17, pos.x + 17, pos.y + 17)
  setColor(6)
  rect(pos.x.int - 17, pos.y.int - 17, pos.x.int + 17, pos.y.int + 17)

  var pattern = patterns[playingPattern]
  # draw binding lights
  for i in 0..7:
    setColor(
      if bindings[i].machine != nil:
        if pattern.rows[step][i] != 0: 10
        else: 9
      else: 0)
    rectfill(x + i * 4, y, x + i * 4 + 2, y + 2)

  for i in 0..7:
    setColor(if (step / pattern.rows.len) * 8 == i: 8 else: 0)
    rectfill(x + i * 4, y + 4, x + i * 4 + 2, y + 4 + 2)

  for j in 0..4:
    for i in 0..7:
      let patId = j * 8 + i
      setColor(if patId > patterns.high: 0 elif patId == playingPattern: 11 else: 3)
      rectfill(x + i * 4, y + j * 4 + 8, x + i * 4 + 2, y + j * 4 + 8 + 2)

method getAABB*(self: Sequencer): AABB =
  result.min.x = pos.x - 17
  result.min.y = pos.y - 17
  result.max.x = pos.x + 17
  result.max.y = pos.y + 17

method draw*(self: SequencerView) =
  cls()
  var sequencer = Sequencer(machine)
  let pattern = sequencer.patterns[sequencer.currentPattern]
  let startStep = clamp(sequencer.currentStep-7,0,pattern.rows.high)

  print("editing pattern: " & $(sequencer.currentPattern+1) & "/" & $sequencer.patterns.len, 1, 1)
  # draw bindings
  setColor(4)
  if sequencer.bindings[sequencer.currentColumn].machine != nil:
    var binding = sequencer.bindings[sequencer.currentColumn]
    var (voice, param) = binding.machine.getParameter(binding.param)
    print(binding.machine.name & ": " & (if voice != -1: $voice & ": " else: "") & param.name, 1, 9+8)
  else:
    print("unbound", 1, 9+8)
  for i in 0..colsPerPattern-1:
    if sequencer.bindings[i].machine == nil:
      rect(i * 16 + 16, 8, i * 16 + 14 + 16, 15)
    else:
      rectfill(i * 16 + 16, 8, i * 16 + 14 + 16, 15)

  if sequencer.playingPattern == sequencer.currentPattern:
    setColor(4)
    let y = (sequencer.step - startStep) * 8 + (sequencer.subTick * 8.0).int + 9 + 16
    line(1, y, 1 + 16 * 8 + 8, y)

  for i in startStep..pattern.rows.high:
    let y = (i - startStep) * 8 + 16
    let row = pattern.rows[i]

    setColor(if i == sequencer.currentStep: 8 elif sequencer.ticksPerBeat > 0 and i %% sequencer.ticksPerBeat == 0: 6 else: 13)
    print($(i+1), 1, y + 8)

    for col,val in row:
      setColor(if i == sequencer.currentStep and col == sequencer.currentColumn: 8 elif sequencer.ticksPerBeat > 0 and i %% sequencer.ticksPerBeat == 0: 6 else: 13)
      if sequencer.bindings[col].machine != nil:
        var targetMachine = sequencer.bindings[col].machine
        var (voice, targetParam) = targetMachine.getParameter(sequencer.bindings[col].param)
        if targetParam.kind == Note:
          var str = if val == Blank: "..." else: noteToNoteName(val.int)
          setColor(if i == sequencer.currentStep and col == sequencer.currentColumn and sequencer.subColumn == 0: 8 elif sequencer.ticksPerBeat > 0 and i %% sequencer.ticksPerBeat == 0: 6 else: 13)
          print(str[0..1], col * 16 + 12, y + 8)
          setColor(if i == sequencer.currentStep and col == sequencer.currentColumn and sequencer.subColumn == 1: 8 elif sequencer.ticksPerBeat > 0 and i %% sequencer.ticksPerBeat == 0: 6 else: 13)
          print(str[2..2], col * 16 + 12 + 8, y + 8)
        elif targetParam.kind == Int or targetParam.kind == Float:
          # we want to split this into 3 columns, one for each char
          var str = if val == Blank: "..." else: align($val, 3, '0')
          for c in 0..2:
            setColor(if i == sequencer.currentStep and col == sequencer.currentColumn and c == sequencer.subColumn: 8 elif sequencer.ticksPerBeat > 0 and i %% sequencer.ticksPerBeat == 0: 6 else: 13)
            print(str[c..c], col * 16 + 12 + c * 4, y + 8)
        elif targetParam.kind == Trigger:
          print(if val == 1: "X" else: ".", col * 16 + 12, y + 8)
      else:
          print(" - ", col * 16 + 12, y + 8)
  setColor(7)
  printr("bpm: " & $Master(masterMachine).beatsPerMinute, screenWidth - 1, 0)
  printr("tpb: " & $sequencer.ticksPerBeat, screenWidth - 1, 8)
  printr("tick: " & $sequencer.step & "/" & $pattern.rows.high, screenWidth - 1, 16)
  printr((if sequencer.playing: "playing" else: "stopped") & ": " & $sequencer.playingPattern, screenWidth - 1, 32)
  printr("octave: " & $baseOctave, screenWidth - 1, 48)

  if menu != nil:
    menu.draw()

  var mv = mouse()
  spr(20, mv.x, mv.y)

method process*(self: Sequencer) =
  let pattern = patterns[playingPattern]
  if playing:
    if subTick == 0.0:
      for i,binding in bindings:
        if binding.machine != nil:
          var targetMachine = binding.machine
          var (voice,param) = targetMachine.getParameter(binding.param)
          if pattern.rows[step][i] == Blank:
            continue
          else:
            let value = pattern.rows[step][i]
            case param.kind:
            of Note, Int, Trigger:
              param.value = value.float
              param.onchange(value.float, voice)
            of Float:
              # convert 0-999 to 0.0-1.0 to param.min-max
              let normalised = invLerp(0.0, 999.0, value.float)
              let mapped = lerp(param.min, param.max, normalised)
              param.value = mapped
              param.onchange(mapped, voice)
    let ticksPerBeat = if ticksPerBeat < 0: 1.0 / -ticksPerBeat.float else: ticksPerBeat.float
    subTick += invSampleRate * (Master(masterMachine).beatsPerMinute.float / 60.0 * ticksPerBeat).float
    if subTick >= 1.0:
      step += 1
      if step > pattern.rows.high:
        step = 0
      subTick = 0.0

proc setValue(self: Sequencer, newValue: int) =
  var pattern = patterns[currentPattern]

  var machine = bindings[currentColumn].machine
  if machine == nil:
    return
  var (voice, param) = machine.getParameter(bindings[currentColumn].param)

  var value = pattern.rows[currentStep][currentColumn]

  if param.kind == Int or param.kind == Float:
    if newValue == Blank:
      value = Blank
    else:
      if value == Blank:
        value = 0
      let k = if subColumn == 0: 2 elif subColumn == 1: 1 else: 0
      let d = (value/(10^k)) mod 10
      value = value + (newValue - d) * (10^k)

  elif param.kind == Note:
    if newValue == Blank:
      value = Blank
    else:
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
  if menu != nil:
    if menu.key(key, down):
      return true

  let scancode = key.keysym.scancode
  let ctrl = (int16(key.keysym.modstate) and int16(KMOD_CTRL)) != 0


  let pattern = s.patterns[s.currentPattern]

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
    of Int, Float, Trigger:
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
    else:
      discard

  if scancode == SDL_SCANCODE_LEFT and down:
    if ctrl:
      # prev pattern
      s.currentPattern -= 1
      if s.currentPattern < 0:
        s.currentPattern = s.patterns.high
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
          maxSubCol = if targetParam.kind == Note: 1 else: 2
        s.subColumn = maxSubCol
      if s.currentColumn < 0:
        s.currentColumn = colsPerPattern - 1
      return true
  if scancode == SDL_SCANCODE_RIGHT and down:
    if ctrl:
      # next pattern
      s.currentPattern += 1
      if s.currentPattern > s.patterns.high:
        s.patterns.add(newPattern())
      return true
    else:
      var maxSubCol = 0
      var targetMachine = s.bindings[s.currentColumn].machine
      if targetMachine == nil:
        maxSubCol = 0
      else:
        var (voice, targetParam) = targetMachine.getParameter(s.bindings[s.currentColumn].param)
        maxSubCol = if targetParam.kind == Note: 1 else: 2

      s.subColumn += 1
      if s.subColumn > maxSubCol:
        s.subColumn = 0
        s.currentColumn += 1
        if s.currentColumn > colsPerPattern - 1:
          s.currentColumn = 0
      return true
  if scancode == SDL_SCANCODE_UP and down:
    s.currentStep -= (if ctrl: s.ticksPerBeat else: 1)
    if s.currentStep < 0:
      s.currentStep = pattern.rows.high
    return true
  if scancode == SDL_SCANCODE_DOWN and down:
    s.currentStep += (if ctrl: s.ticksPerBeat else: 1)
    if s.currentStep > pattern.rows.high:
      s.currentStep = 0
    return true

  if key.keysym.scancode == SDL_SCANCODE_PAGEUP and down:
    if ctrl:
      let length = s.patterns[s.currentPattern].rows.len
      s.patterns[s.currentPattern].rows.setLen(max(length div 2, 1))
      return true
  if key.keysym.scancode == SDL_SCANCODE_PAGEDOWN and down:
    if ctrl:
      let length = s.patterns[s.currentPattern].rows.len
      s.patterns[s.currentPattern].rows.setLen(length * 2)
      return true

  if key.keysym.scancode == SDL_SCANCODE_RETURN and down:
    if s.currentPattern == s.playingPattern:
      s.playing = not s.playing
    else:
      s.playingPattern = s.currentPattern
      s.step = 0
      s.subTick = 0.0
      s.playing = true
    return true

  if key.keysym.scancode == SDL_SCANCODE_HOME and down:
    if ctrl:
      s.step = 0
      s.subTick = 0.0
    else:
      s.currentStep = 0
    return true
  if key.keysym.scancode == SDL_SCANCODE_END and down:
    s.currentStep = pattern.rows.high
    return true

  if key.keysym.scancode == SDL_SCANCODE_MINUS and down:
    s.ticksPerBeat -= 1
    return true
  if key.keysym.scancode == SDL_SCANCODE_EQUALS and down:
    s.ticksPerBeat += 1
    return true

  if key.keysym.scancode == SDL_SCANCODE_BACKSPACE and down:
    menu = newMenu(point2d(
      (s.currentColumn * 16 + 12).float,
      8.float
    ), "bind machine")
    menu.back = proc() =
      self.menu = nil

    for i in 0..machines.high:
      if machines[i] == self.machine:
        continue
      (proc() =
        let targetMachine = machines[i]
        self.menu.items.add(newMenuItem(targetMachine.name) do():
          echo "selected ", s.currentColumn, " to ", targetMachine.name
          self.menu = newMenu(self.menu.pos, "bind param")
          self.menu.pos.x = (s.currentColumn * 16 + 12).float
          self.menu.pos.y = 8.float
          self.menu.back = proc() =
            self.menu = nil
          for i in 0..targetMachine.getParameterCount()-1:
            (proc() =
              var paramIndex = i
              var (voice, targetParam) = targetMachine.getParameter(i)
              self.menu.items.add(newMenuItem(targetParam.name) do():
                s.bindings[s.currentColumn].machine = targetMachine
                s.bindings[s.currentColumn].param = paramIndex
                echo "bound ", s.currentColumn, " to ", targetMachine.name, " : ", targetParam.name
                self.menu = nil
              )
            )()
        )
      )()
    return true


  return false

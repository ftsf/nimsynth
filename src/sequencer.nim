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

const colsPerPattern = 8

type
  Pattern* = ref object of RootObj
    rows*: seq[array[colsPerPattern, int]]
  Sequencer* = ref object of Machine
    patterns*: seq[Pattern]
    bindings*: array[colsPerPattern, tuple[machine: Machine, param: int]]
    currentPattern*: int
    currentStep*: int
    currentColumn*: int
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

method init*(self: Sequencer) =
  procCall init(Machine(self))

  patterns = newSeq[Pattern]()
  patterns.add(newPattern())
  ticksPerBeat = 4
  subTick = 0.0
  name = "seq"
  nOutputs = 0
  nInputs = 0

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
  setColor(1)
  rectfill(pos.x - 17, pos.y - 17, pos.x + 17, pos.y + 17)
  setColor(6)
  rect(pos.x.int - 17, pos.y.int - 17, pos.x.int + 17, pos.y.int + 17)

  setColor(8)
  pset(pos.x - 15 + (step / patterns[playingPattern].rows.len) * 30, pos.y - 3)
  setColor(10)
  pset(pos.x - 15 + (playingPattern / patterns.len) * 30, pos.y - 2)
  if ticksPerBeat < 0:
    setColor(9)
    pset(pos.x - 15 + subTick * 30, pos.y - 1)
  setColor(11)
  for col in 0..colsPerPattern-1:
    var pattern = patterns[playingPattern]
    if pattern.rows[step][col] != 0:
      pset(pos.x - 15 + col * 2, pos.y + 3)

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
  for i in startStep..pattern.rows.high:
    let y = (i - startStep) * 8
    let row = pattern.rows[i]
    if i == sequencer.step:
      setColor(4)
      line(1, y + 8, 1 + 16 * 8 + 8, y + 8)
    setColor(if i == sequencer.currentStep: 8 elif i %% sequencer.ticksPerBeat == 0: 6 else: 13)
    print($(i+1), 1, y + 8)
    for col,val in row:
      setColor(if i == sequencer.currentStep and col == sequencer.currentColumn: 8 elif i %% sequencer.ticksPerBeat == 0: 6 else: 13)
      if sequencer.bindings[col].machine != nil:
        var targetMachine = sequencer.bindings[col].machine
        var (voice, targetParam) = targetMachine.getParameter(sequencer.bindings[col].param)
        if targetParam.kind == Note:
          print(if val == 0: "..." else: noteToNoteName(val.int), col * 16 + 12, y + 8)
        elif targetParam.kind == Int:
          print(align($val, 3, '0'), col * 16 + 12, y + 8)
      else:
          print("...", col * 16 + 12, y + 8)
  setColor(7)
  printr("bpm: " & $Master(masterMachine).beatsPerMinute, screenWidth - 1, 0)
  printr("tpb: " & $sequencer.ticksPerBeat, screenWidth - 1, 8)
  printr("tick: " & $sequencer.step & "/" & $pattern.rows.high, screenWidth - 1, 16)
  printr("pattern: " & $sequencer.currentPattern & "/" & $sequencer.patterns.high, screenWidth - 1, 24)
  printr((if sequencer.playing: "playing" else: "stopped") & ": " & $sequencer.playingPattern, screenWidth - 1, 32)
  printr("octave: " & $baseOctave, screenWidth - 1, 48)

  if menu != nil:
    menu.draw()

method process*(self: Sequencer) =
  let pattern = patterns[playingPattern]
  if playing:
    if subTick == 0.0:
      for i,binding in bindings:
        if binding.machine != nil:
          var targetMachine = binding.machine
          var (voice,param) = targetMachine.getParameter(binding.param)
          if param.kind == Note and pattern.rows[step][i] == 0:
            continue
          else:
            param.onchange(pattern.rows[step][i].float, voice)
    let ticksPerBeat = if ticksPerBeat < 0: 1.0 / -ticksPerBeat.float else: ticksPerBeat.float
    subTick += invSampleRate * (Master(masterMachine).beatsPerMinute.float / 60.0 * ticksPerBeat).float
    if subTick >= 1.0:
      step += 1
      if step > pattern.rows.high:
        step = 0
      subTick = 0.0



method key*(self: SequencerView, key: KeyboardEventPtr, down: bool): bool =
  var s = Sequencer(machine)
  if menu != nil:
    if menu.key(key, down):
      return true

  let scancode = key.keysym.scancode
  let ctrl = (int16(key.keysym.modstate) and int16(KMOD_CTRL)) != 0


  let pattern = s.patterns[s.currentPattern]

  # if current column is a note type:
  if s.bindings[s.currentColumn].machine != nil:
    var targetMachine = s.bindings[s.currentColumn].machine
    var (voice, targetParam) = targetMachine.getParameter(s.bindings[s.currentColumn].param)
    case targetParam.kind:
    of Note:
      let note = keyToNote(key)
      if note > 0 and down:
        pattern.rows[s.currentStep][s.currentColumn] = note
        s.currentStep += 1
        if s.currentStep > pattern.rows.high:
          s.currentStep = 0
        return true
      if note == -2 and down:
        pattern.rows[s.currentStep][s.currentColumn] = -2
        s.currentStep += 1
        if s.currentStep > pattern.rows.high:
          s.currentStep = 0
        return true
      if note == -1 and down:
        pattern.rows[s.currentStep][s.currentColumn] = 0
        s.currentStep += 1
        if s.currentStep > pattern.rows.high:
          s.currentStep = 0
        return true
    of Int:
      if down:
        case scancode:
        of SDL_SCANCODE_0:
          pattern.rows[s.currentStep][s.currentColumn] = 0
          return true
        of SDL_SCANCODE_1:
          pattern.rows[s.currentStep][s.currentColumn] = 1
          return true
        of SDL_SCANCODE_2:
          pattern.rows[s.currentStep][s.currentColumn] = 2
          return true
        of SDL_SCANCODE_3:
          pattern.rows[s.currentStep][s.currentColumn] = 3
          return true
        of SDL_SCANCODE_4:
          pattern.rows[s.currentStep][s.currentColumn] = 4
          return true
        of SDL_SCANCODE_5:
          pattern.rows[s.currentStep][s.currentColumn] = 5
          return true
        of SDL_SCANCODE_6:
          pattern.rows[s.currentStep][s.currentColumn] = 6
          return true
        of SDL_SCANCODE_7:
          pattern.rows[s.currentStep][s.currentColumn] = 7
          return true
        of SDL_SCANCODE_8:
          pattern.rows[s.currentStep][s.currentColumn] = 8
          return true
        of SDL_SCANCODE_9:
          pattern.rows[s.currentStep][s.currentColumn] = 9
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
    s.currentColumn -= 1
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
    s.currentColumn += 1
    if s.currentColumn > colsPerPattern - 1:
      s.currentColumn = 0
    return true
  if scancode == SDL_SCANCODE_UP and down:
    s.currentStep -= (if ctrl: s.ticksPerBeat else: 1)
    if s.currentStep < 0:
      s.currentStep = 0
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

  if key.keysym.scancode == SDL_SCANCODE_BACKSPACE and down:
    menu = newMenu()
    menu.pos.x = (s.currentColumn * 16 + 12).float
    menu.pos.y = 8.float
    menu.back = proc() =
      self.menu = nil

    for i in 0..machines.high:
      if machines[i] == self.machine:
        continue
      (proc() =
        let targetMachine = machines[i]
        self.menu.items.add(newMenuItem(targetMachine.name) do():
          echo "selected ", s.currentColumn, " to ", targetMachine.name
          self.menu = newMenu()
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

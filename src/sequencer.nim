{.this:self.}

import strutils
import pico
import common
import sdl2
import util

const colsPerPattern = 8

type
  Pattern* = ref object of RootObj
    rows*: seq[array[colsPerPattern, int]]
  Sequencer* = ref object of Machine
    patterns*: seq[Pattern]
    bindings*: array[colsPerPattern, tuple[machine: int, param: int, voice: int]]
    currentPattern*: int
    currentStep*: int
    currentColumn*: int
    playingPattern*: int
    step*: int
    ticksPerBeat*: int
    playing: bool
    subTick: float

proc newPattern*(): Pattern =
  result = new(Pattern)
  result.rows = newSeq[array[colsPerPattern, int]](16)

proc newSequencer*(): Sequencer =
  result = new(Sequencer)
  result.patterns = newSeq[Pattern]()
  result.patterns.add(newPattern())
  result.ticksPerBeat = 4
  result.subTick = 0.0
  result.bindings[0][0] = 0

method draw*(self: Sequencer) =
  cls()
  let pattern = patterns[currentPattern]
  let startStep = clamp(currentStep-7,0,pattern.rows.high)
  for i in startStep..pattern.rows.high:
    let y = (i - startStep) * 8
    let row = pattern.rows[i]
    if i == step:
      setColor(4)
      line(0, y + 8, 16 * 8 + 8, y + 8)
    setColor(if i == currentStep: 8 elif i %% ticksPerBeat == 0: 6 else: 13)
    print($(i+1), 0, y + 8)
    for j,col in row:
      setColor(if i == currentStep and j == currentColumn: 8 elif i %% ticksPerBeat == 0: 6 else: 13)
      print(if col == 0: "..." else: noteToNoteName(col.int), j * 16 + 12, y + 8)
  setColor(7)
  printr("bpm: " & $beatsPerMinute, screenWidth, 0)
  printr("tick: " & $step & "/" & $pattern.rows.high, screenWidth, 8)
  printr("pattern: " & $currentPattern & "/" & $patterns.high, screenWidth, 16)
  printr((if playing: "playing" else: "stopped") & ": " & $playingPattern, screenWidth, 24)
  printr("octave: " & $baseOctave, screenWidth, 32)

method updateUI*(self: Sequencer, dt: float) =
  let pattern = patterns[currentPattern]


method update*(self: Sequencer) =
  let pattern = patterns[playingPattern]
  if playing:
    subTick += invSampleRate * (beatsPerMinute.float / 60.0 * ticksPerBeat.float).float
    if subTick > 1.0:
      subTick -= 1.0
      step += 1
      if step > pattern.rows.high:
        step = 0
      if pattern.rows[step][0] != 0:
        var targetMachine = machines[bindings[0].machine]
        var targetParam: ptr Parameter
        if bindings[0].voice == -1:
          targetParam = addr(targetMachine.globalParams[bindings[0].param])
        else:
          targetParam = addr(targetMachine.voices[bindings[0].voice].parameters[bindings[0].param])
        targetParam.onchange(pattern.rows[step][0].float, bindings[0].voice)


method key*(self: Sequencer, key: KeyboardEventPtr, down: bool): bool =
  let scancode = key.keysym.scancode
  let ctrl = (int16(key.keysym.modstate) and int16(KMOD_CTRL)) != 0

  let pattern = patterns[currentPattern]
  let note = keyToNote(key)

  if note > 0 and down:
    pattern.rows[currentStep][currentColumn] = note
    currentStep += 1
    if currentStep > pattern.rows.high:
      currentStep = 0
    return true
  if note == -2 and down:
    pattern.rows[currentStep][currentColumn] = -2
    currentStep += 1
    if currentStep > pattern.rows.high:
      currentStep = 0
    return true
  if note == -1 and down:
    pattern.rows[currentStep][currentColumn] = 0
    currentStep += 1
    if currentStep > pattern.rows.high:
      currentStep = 0
    return true

  if scancode == SDL_SCANCODE_LEFT and down:
    if ctrl:
      # prev pattern
      currentPattern -= 1
      if currentPattern < 0:
        currentPattern = patterns.high
      return true
    currentColumn -= 1
    if currentColumn < 0:
      currentColumn = colsPerPattern - 1
    return true
  if scancode == SDL_SCANCODE_RIGHT and down:
    if ctrl:
      # next pattern
      currentPattern += 1
      if currentPattern > patterns.high:
        patterns.add(newPattern())
      return true
    currentColumn += 1
    if currentColumn > colsPerPattern - 1:
      currentColumn = 0
    return true
  if scancode == SDL_SCANCODE_UP and down:
    currentStep -= (if ctrl: ticksPerBeat else: 1)
    if currentStep < 0:
      currentStep = 0
    return true
  if scancode == SDL_SCANCODE_DOWN and down:
    currentStep += (if ctrl: ticksPerBeat else: 1)
    if currentStep > pattern.rows.high:
      currentStep = 0
    return true

  if key.keysym.scancode == SDL_SCANCODE_PAGEUP and down:
    baseOctave += 1
    if baseOctave > 9:
      baseOctave = 9
    return true
  if key.keysym.scancode == SDL_SCANCODE_PAGEDOWN and down:
    baseOctave -= 1
    if baseOctave < 0:
      baseOctave = 0
    return true

  if key.keysym.scancode == SDL_SCANCODE_RETURN and down:
    if currentPattern == playingPattern:
      playing = not playing
    else:
      playingPattern = currentPattern
      step = 0
      subTick = 0.0
      playing = true
    return true

  if key.keysym.scancode == SDL_SCANCODE_KP_PLUS and down:
    beatsPerMinute += 1
    return true
  if key.keysym.scancode == SDL_SCANCODE_KP_MINUS and down:
    beatsPerMinute -= 1
    return true

  if key.keysym.scancode == SDL_SCANCODE_HOME and down:
    if ctrl:
      step = 0
      subTick = 0.0
    else:
      currentStep = 0
    return true
  if key.keysym.scancode == SDL_SCANCODE_END and down:
    currentStep = pattern.rows.high
    return true


  return false

import std/math
import std/strutils
import std/strformat

import nico

import common

import core/basemachine
import core/envelope
import core/sample
import ui/menu

import util

import machines/master

const inputFadeTime = 4096 * 2

type
  Tape = seq[array[2, float32]]

  RecorderState = enum
    Stopped
    RecordingInitialLoop
    Overdubbing
    Playing

  Recorder = ref object of Machine
    state: RecorderState
    loop: bool
    monitor: bool
    readHead: float32 # in samples, interpolated
    writeHead: float32
    readSpeed: float32 # samples per second
    writeSpeed: float32
    tapeLength: int # in frames
    maxTapeLengthInSteps: float32
    tapeData: Tape
    undoData: Tape
    overdubGain: float32 # when overdubbing reduce the original sample by this much
    recordArmed: bool
    stopRecordingAt: float32 # automatically stop recording when writeHead reaches here
    startRecordingThreshold: float32 # start recording when input over this threshold
    startRecordingAtLoopStart: bool
    fromStart: bool
    empty: bool
    playbackOffset: float32
    inputFadeOutTimer: int
    inputFadeInTimer: int

proc `[]`(self: Tape, x: int, c: int): float32 =
  if self.len == 0:
    return 0f
  return self[floorMod(x, self.len)][c]

proc `[]`(self: Tape, x: float32, c: int): float32 =
  if self.len == 0:
    return 0f
  let a = self[floorMod(math.floor(x), self.len).int, c]
  let b = self[floorMod(math.ceil(x), self.len).int, c]
  let t = floorMod(x, 1.0)
  return lerp(a,b,t)

proc `[]=`(self: var Tape, x: float32, c: int, v: float32) =
  if self.len == 0:
    return
  let i = floorMod(math.floor(x), self.len).int
  self[i][c] = v

proc setMaxTapeLength(self: Recorder, samples: int) =
  # truncate or extend the tape
  self.tapeData.setLen(samples)
  self.tapeLength = min(self.tapeLength, self.tapeData.len)
  echo "setMaxTapeLength: ", samples

proc setMaxTapeLengthInSteps(self: Recorder, steps: float32) =
  var seconds = steps * (secondsPerBeat() / 4.0f)
  var newTapeLengthInSamples = (seconds * sampleRate).int
  self.setMaxTapeLength(newTapeLengthInSamples)

proc erase(self: Recorder) =
  for i in 0..<self.tapeData.len:
    self.tapeData[i][0] = 0f
    self.tapeData[i][1] = 0f
  self.writeHead = 0
  self.readHead = self.writeHead + self.playbackOffset
  self.empty = true

proc stop(self: Recorder) =
  self.state = Stopped
  self.stopRecordingAt = -10
  self.recordArmed = false

proc startOverdubbing(self: Recorder) =
  self.state = Overdubbing

proc startPlaying(self: Recorder) =
  self.state = Playing
  self.stopRecordingAt = -10

proc startNewInitialLoop(self: Recorder) =
  self.state = RecordingInitialLoop
  self.erase()
  self.tapeLength = 0
  self.empty = false

proc endInitialLoop(self: Recorder) =
  if self.writeHead != 0:
    #self.setMaxTapeLength(self.writeHead.int)
    self.tapeLength = self.writeHead.int
    echo &"ended initial loop, tapeLength: {self.tapeLength} / {self.tapeData.len}"

  if self.tapeLength == 0:
    self.empty = true
  else:
    self.empty = false

proc setState(self: Recorder, newState: RecorderState) =
  echo "setState: ", self.state, " -> ", newState
  # from Stopped:
  # A (no data) -> RecordingInitialLoop
  # A (with data) -> Playing
  # B -> Clear data

  # from RecordingInitialLoop:
  # A -> Overdubbing (set tape length)
  # B -> Playing (set tape length)

  # from Overdubbing:
  # A -> Playing
  # B -> Stopped

  # from Playing:
  # A -> Overdubbing
  # B -> Stopped
  var oldState = self.state

  case oldState:
    of Stopped:
      case newState:
        of Stopped:
          raise newException(Exception, "Invalid State transition Stopped -> Stopped")
        of RecordingInitialLoop:
          echo "starting RecordingInitialLoop, fading in"
          self.inputFadeInTimer = inputFadeTime
          self.startNewInitialLoop()
        of Overdubbing:
          echo "starting overdubbing, fading in"
          self.inputFadeInTimer = inputFadeTime
          self.startOverdubbing()
        of Playing:
          self.startPlaying()

    of RecordingInitialLoop:
      case newState:
        of Stopped:
          self.stop()
        of RecordingInitialLoop:
          raise newException(Exception, "Invalid State transition RecordingInitialLoop -> RecordingInitialLoop")
        of Overdubbing:
          self.endInitialLoop()
          self.startOverdubbing()
        of Playing:
          self.endInitialLoop()
          self.startPlaying()
          echo "ended initial loop, fading out"
          self.inputFadeOutTimer = inputFadeTime

    of Overdubbing:
      case newState:
        of Stopped:
          self.stop()
        of RecordingInitialLoop:
          raise newException(Exception, "Invalid State transition Overdubbing -> RecordingInitialLoop")
        of Overdubbing:
          raise newException(Exception, "Invalid State transition Overdubbing -> Overdubbing")
        of Playing:
          echo "ended overdubbing, fading out"
          self.inputFadeOutTimer = inputFadeTime
          self.startPlaying()

    of Playing:
      case newState:
        of Stopped:
          self.stop()
        of RecordingInitialLoop:
          raise newException(Exception, "Invalid State transition Playing -> RecordingInitialLoop")
        of Overdubbing:
          echo "starting overdubbing, fading in"
          self.inputFadeInTimer = inputFadeTime
          self.startOverdubbing()
        of Playing:
          raise newException(Exception, "Invalid State transition Playing -> Playing")

  self.state = newState

proc saveUndo(self: Recorder) =
  for i in 0..<self.tapeData.len:
    self.undoData[i][0] = self.tapeData[i][0]
    self.undoData[i][1] = self.tapeData[i][1]

method init(self: Recorder) =
  procCall init(Machine(self))

  self.name = "rec"
  self.nOutputs = 1
  self.nInputs = 1
  self.stereo = true

  self.readHead = 1

  self.stopRecordingAt = -10

  self.maxTapeLengthInSteps = 64.0
  self.setMaxTapeLengthInSteps(self.maxTapeLengthInSteps)
  self.tapeLength = 0

  self.empty = true
  self.state = Stopped

  self.globalParams.add([
    Parameter(name: "rec", separator: true, deferred: true, kind: Trigger, min: 0.0, max: 1.0, onchange: proc(newValue: float32, voice: int) =
      if self.state == Stopped:
        if self.empty:
          self.setState(RecordingInitialLoop)
        else:
          self.setState(Overdubbing)
      elif self.state == Playing:
        self.setState(Overdubbing)
    ),
    Parameter(name: "rec one", separator: false, deferred: true, kind: Trigger, min: 0.0, max: 1.0, onchange: proc(newValue: float32, voice: int) =
      if self.state == Stopped:
        self.recordArmed = true
      elif self.state == Playing:
        self.recordArmed = true
      elif self.state == Overdubbing:
        self.stopRecordingAt = floorMod(self.writeHead, self.tapeLength)
    ),
    Parameter(name: "stop", separator: false, deferred: true, kind: Trigger, min: 0.0, max: 1.0, onchange: proc(newValue: float32, voice: int) =
      if self.state != Stopped:
        self.setState(Stopped)
    ),
    Parameter(name: "play", separator: false, deferred: true, kind: Trigger, min: 0.0, max: 1.0, onchange: proc(newValue: float32, voice: int) =
      if self.state != Playing:
        self.setState(Playing)
    ),
    Parameter(name: "clear", separator: false, deferred: true, kind: Trigger, min: 0.0, max: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.erase()
    ),

    Parameter(name: "loop", kind: Bool, separator: true, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.loop = newValue.bool
    ),
    Parameter(name: "monitor", kind: Bool, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.monitor = newValue.bool
    ),
    Parameter(name: "fromStart", kind: Bool, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.fromStart = newValue.bool
    ),
    Parameter(name: "quantized", kind: Bool, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.startRecordingAtLoopStart = newValue.bool
    ),
    Parameter(name: "threshold", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.startRecordingThreshold = newValue
    ),
    Parameter(name: "play offset", kind: Float, min: -64.0, max: 64.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.playbackOffset = newValue
    ),
    Parameter(name: "speed", kind: Float, min: -4.0, max: 4.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.readSpeed = newValue
      self.writeSpeed = newValue
    ),
    Parameter(name: "overdub", kind: Float, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float32, voice: int) =
      self.overdubGain = newValue
    ),
    Parameter(name: "length", kind: Int, min: 1.0, max: 256.0, default: 64.0, onchange: proc(newValue: float32, voice: int) =
      self.maxTapeLengthInSteps = newValue
      self.setMaxTapeLengthInSteps(self.maxTapeLengthInSteps)
    ),
  ])

  self.setDefaults()

method onBPMChange(self: Recorder, bpm: int) =
  self.setMaxTapeLengthInSteps(self.maxTapeLengthInSteps)

method process*(self: Recorder) {.inline.} =
  var input = self.getInput(0)

  if self.state in [Overdubbing, Playing] and self.empty:
    echo "can't play back empty buffer, stopping"
    self.setState(Stopped)

  let playback = self.state in [Overdubbing, Playing, RecordingInitialLoop]
  let recording = self.state in [RecordingInitialLoop, Overdubbing] or self.inputFadeOutTimer > 0

  var fadeInput = 1f

  if self.inputFadeOutTimer > 0:
    fadeInput *= lerp(1f, 0f, self.inputFadeOutTimer.float32 / inputFadeTime.float32)
    #echo &"fadeOut: {self.inputFadeOutTimer} fadeInput: {fadeInput} sc: {sampleChannel}"
    if sampleChannel == 0:
      self.inputFadeOutTimer -= 1

  if self.inputFadeInTimer > 0:
    fadeInput *= lerp(0f, 1f, self.inputFadeInTimer.float32 / inputFadeTime.float32)
    #echo &"fadeIn: {self.inputFadeInTimer} fadeInput: {fadeInput} sc: {sampleChannel}"
    if sampleChannel == 0:
      self.inputFadeInTimer -= 1

  if self.recordArmed:
    if self.state == Playing:
      if self.startRecordingAtLoopStart:
        if self.empty:
          self.setState(RecordingInitialLoop)
        else:
          self.setState(Overdubbing)
        self.recordArmed = false
        self.stopRecordingAt = floorMod(self.writeHead - 1, self.tapeLength)
    elif abs(input) > self.startRecordingThreshold:
      if self.empty:
        self.setState(RecordingInitialLoop)
      else:
        self.setState(Overdubbing)
      self.recordArmed = false
      self.stopRecordingAt = floorMod(self.writeHead - 1, self.tapeLength)

  if playback:
    if sampleChannel == 0:
      self.writeHead += self.writeSpeed
      self.readHead = self.writeHead + self.playbackOffset

      if self.loop == false and self.readHead >= self.tapeLength:
        self.stop()

      if self.state == RecordingInitialLoop:
        self.tapeLength += 1
        if self.tapeLength >= self.tapeData.len:
          self.tapeLength = self.tapeData.len
          self.setState(Overdubbing)

      self.readHead = floorMod(self.readHead, self.tapeLength)
      self.writeHead = floorMod(self.writeHead, self.tapeLength)

    if sampleChannel == 0:
      self.outputSamples[0] = self.tapeData[self.readHead, 0]
    else:
      self.outputSamples[0] = self.tapeData[self.readHead, 1]
  else:
    self.outputSamples[0] = 0f

  if recording:
    var writeData = input * fadeInput
    var writeHeadData = self.tapeData[self.writeHead, sampleChannel]
    if sampleChannel == 0:
      self.tapeData[self.writeHead, 0] = writeData + writeHeadData * self.overdubGain
    else:
      self.tapeData[self.writeHead, 1] = writeData + writeHeadData * self.overdubGain

    if self.writeHead.int == self.stopRecordingAt.int:
      echo "reached target recording length, writeHead: ", self.writeHead
      self.setState(Playing)

  if self.monitor:
    self.outputSamples[0] += self.getInput(0)

proc drawRecorder(self: Recorder, x,y,w,h: int) =
  if self.tapeLength == 0:
    return

  var left0,left1: int
  var right0,right1: int
  setColor(1)
  rect(x,y,x+w-1,y+h-1)
  let startSample = 0
  let endSample = self.tapeLength - 1
  let length = self.tapeLength
  for i in 0..<w:
    let sample = startSample.float32 + ((i.float32 / w.float32) * length.float32).float32
    let left1s = self.tapeData[sample, 0]
    let right1s = self.tapeData[sample, 1]
    left1 = lerp((y+h-1).float32, y.float32, left1s * 0.5'f + 0.5'f).int
    right1 = lerp((y+h-1).float32, y.float32, right1s * 0.5'f + 0.5'f).int
    if i > 0:
      setColor(3)
      line(x+i-1, left0, x+i, left1)
      setColor(4)
      line(x+i-1, right0, x+i, right1)
    left0 = left1
    right0 = right1

  let readHeadT = floorMod(self.readHead.float32 / self.tapeLength.float32, 1.0)
  let writeHeadT = floorMod(self.writeHead.float32 / self.tapeLength.float32, 1.0)

  setColor(if self.state in [Playing, Overdubbing]: 11 else: 3)
  vline(x + (readHeadT * w.float32).int, y, y + h - 1)
  print($(floorMod(self.readHead, self.tapeLength)), x + 4, y + 2)
  setColor(if self.state in [Overdubbing, RecordingInitialLoop]: 8 else: 4)
  vline(x + (writeHeadT * w.float32).int, y, y + h - 1)
  print($(floorMod(self.writeHead, self.tapeLength)), x + 4, y + h - 1 - 8 - 2)

method drawExtraData(self: Recorder, x,y,w,h: int) =
  var yv = y
  setColor(6)
  yv += 9
  self.drawRecorder(x,y,w,h)

method getAABB*(self: Recorder): AABB =
  result.min.x = self.pos.x - 16
  result.min.y = self.pos.y - 4
  result.max.x = self.pos.x + 16
  result.max.y = self.pos.y + 16

proc getButtonA_AABB(self: Recorder): AABB =
  result.min.x = self.pos.x - 16 + 2
  result.min.y = self.pos.y - 4 + 2
  result.max.x = result.min.x + 4
  result.max.y = result.min.y + 4

proc getButtonB_AABB(self: Recorder): AABB =
  result.min.x = self.pos.x + 16 - 2 - 4
  result.min.y = self.pos.y - 4 + 2
  result.max.x = result.min.x + 4
  result.max.y = result.min.y + 4

method handleClick(self: Recorder, mouse: Vec2f): bool =
  if pointInAABB(mouse, self.getButtonA_AABB()):
    return true
  elif pointInAABB(mouse, self.getButtonB_AABB()):
    return true
  return false

method event(self: Recorder, event: Event, camera: Vec2f): (bool, bool) =
  echo "camera.x: ", camera.x, " event.x: ", event.x, " pos.x: ", self.pos.x
  let buttonA = event.x - camera.x < self.pos.x
  if event.kind == ekMouseButtonDown:
    if buttonA:
      echo "recorder button A got pressed"
      if self.state == Stopped:
        if self.empty:
          if self.recordArmed:
            self.setState(RecordingInitialLoop)
            self.recordArmed = false
          else:
            self.recordArmed = true
        else:
          self.setState(Playing)

      elif self.state == RecordingInitialLoop:
        self.setState(Overdubbing)
        self.recordArmed = false

      elif self.state == Overdubbing:
        self.setState(Playing)
        self.recordArmed = false

      elif self.state == Playing:
        if self.recordArmed:
          self.setState(Overdubbing)
          self.recordArmed = false
        else:
          self.recordArmed = true
    else:
      echo "recorder button B got pressed"
      if self.state == Stopped:
        self.erase()
      elif self.state == RecordingInitialLoop:
        self.setState(Playing)
      elif self.state == Overdubbing:
        self.setState(Stopped)
      elif self.state == Playing:
        self.setState(Stopped)

    return (true, false)

  if event.kind == ekMouseButtonDown:
    echo "recorder button got mousedown"
    return (true, true)

  elif event.kind == ekMouseButtonUp:
    echo "recorder button got mouseup"
    return (false, false)
  return (false, true)

method drawBox*(self: Recorder) =
  setColor(1)
  rectfill(self.getAABB())
  setColor(6)
  rect(self.getAABB())

  let pos = self.pos

  printc(self.name, pos.x, pos.y - 2)

  setColor(8)
  rectfill(self.getButtonA_AABB())

  setColor(4)
  rectfill(self.getButtonB_AABB())

  setColor(0)
  rectfill(pos.x - 15, pos.y + 4, pos.x + 15, pos.y + 14)
  if self.state in [RecordingInitialLoop, Overdubbing]:
    setColor(8)
    rect(pos.x - 15, pos.y + 4, pos.x - 15 + 1, pos.y + 4 + 1)
  elif self.recordArmed and frame mod 30 < 15:
    setColor(4)
    rect(pos.x - 15, pos.y + 4, pos.x - 15 + 1, pos.y + 4 + 1)

  if self.state in [Playing, Overdubbing]:
    setColor(11)
    rect(pos.x + 15 - 2, pos.y + 4, pos.x + 15 - 2 + 1, pos.y + 4 + 1)

  let w = self.getAABB().w()

  setColor(5)
  hline(pos.x - 15, pos.y + 8, pos.x + 15)
  if self.stopRecordingAt >= 0:
    let stopRecordingAtT = floorMod(self.stopRecordingAt.float32 / self.tapeData.len.float32, 1.0)
    setColor(4)
    vline(pos.x - 15 + (stopRecordingAtT * (w - 1f).float32).int, pos.y + 4, pos.y + 14)
  setColor(7)
  let readHeadT = floorMod(self.readHead.float32 / self.tapeData.len.float32, 1.0)
  pset(pos.x - 15 + (readHeadT * (w - 1.0).float32).int, pos.y + 8)
  #for i in -15..15:
  #  if i == 0:
  #    setColor(7)
  #  else:
  #    setColor(1)
  #  let val = osc.peek(osc.phase + ((i.float32 / 30.float32)))
  #  pset(pos.x + i, pos.y + 9 - val * 4.0)

method getMenu(self: Recorder, mv: Vec2f): Menu =
  result = procCall getMenu(Machine(self), mv)
  result.items.add(newMenuItem("oneshot rec"))
  result.items.add(newMenuItem("oneshot play"))
  result.items.add(newMenuItem("x2") do:
    var newLength = min(self.tapeData.len, self.tapeLength) * 2
    self.tapeData.setLen(newLength)
    for i in 0..<self.tapeLength:
      self.tapeData[self.tapeLength + i, 0] = self.tapeData[i][0]
      self.tapeData[self.tapeLength + i, 1] = self.tapeData[i][1]
    self.tapeLength = newLength
    self.maxTapeLengthInSteps *= 2
  )


proc newMachine(): Machine =
  var m = new(Recorder)
  m.init()
  return m

registerMachine("recorder", newMachine, "util")

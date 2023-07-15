import nico
import nico/vec

import common
import util

import core/basemachine
import core/scales


const polyphony = 16

type Keyboard = ref object of Machine
  nOctaves: int
  noteBuffer: array[polyphony, tuple[note: int, age: int]]
  size: int
  scale: int
  baseNote: int

{.this:self.}

method init*(self: Keyboard) =
  procCall init(Machine(self))

  name = "keyboard"
  nOutputs = 0
  nInputs = 0
  nBindings = polyphony * 2
  bindings.setLen(nBindings)
  useMidi = true
  useKeyboard = true
  midiChannel = 0

  for i in 0..<polyphony:
    noteBuffer[i].note = OffNote

  self.globalParams.add([
    Parameter(name: "channel", kind: Int, min: 0.0, max: 15.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.midiChannel = newValue.int
    ),
    Parameter(name: "octaves", kind: Int, min: 1.0, max: 10.0, default: 7.0, onchange: proc(newValue: float32, voice: int) =
      self.nOctaves = newValue.int
    ),
    Parameter(name: "size", kind: Int, min: 1.0, max: 6.0, default: 2.0, onchange: proc(newValue: float32, voice: int) =
      self.size = newValue.int
    ),
    Parameter(name: "scale", kind: Int, min: 0.0, max: scaleList.high.float32, default: scaleList.high.float32, onchange: proc(newValue: float32, voice: int) =
      self.scale = newValue.int
    , getValueString: proc(value: float32, voice: int): string =
      return scaleList[value.int].name
    ),
    Parameter(name: "baseNote", kind: Note, min: 0.0, max: 255.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.baseNote = newValue.int
    ),
  ])

  setDefaults()

method process*(self: Keyboard) =
  discard

proc noteOn(self: Keyboard, note: int, vel: int) =
  var done = false
  for i in 0..<polyphony:
    if noteBuffer[i].note != OffNote:
      noteBuffer[i].age += 1

  for i in 0..<polyphony:
    if not bindings[i*2].isBound:
      continue
    if noteBuffer[i].note == OffNote:
      noteBuffer[i].note = note
      noteBuffer[i].age = 0

      if bindings[i*2].isBound:
        var (voice,param) = bindings[i*2].getParameter()
        param.value = note.float32
        param.onchange(param.value, voice)

      if bindings[i*2+1].isBound:
        var (voice,param) = bindings[i*2+1].getParameter()
        param.value = vel.float32 / 127.0
        param.onchange(param.value, voice)

      done = true
      break

  if not done:
    # find oldest note and replace it
    var oldestAge = 0
    var oldestVoice = 0
    for i in 0..<polyphony:
      if not bindings[i*2].isBound:
        continue
      if noteBuffer[i].age > oldestAge:
        oldestAge = noteBuffer[i].age
        oldestVoice = i

    noteBuffer[oldestVoice].note = note
    noteBuffer[oldestVoice].age = 0
    if bindings[oldestVoice*2].isBound:
      var (voice,param) = bindings[oldestVoice*2].getParameter()
      param.value = note.float32
      param.onchange(param.value, voice)

    if bindings[oldestVoice*2+1].isBound:
      var (voice,param) = bindings[oldestVoice*2+1].getParameter()
      param.value = vel.float32 / 127.0
      param.onchange(param.value, voice)

proc noteOff(self: Keyboard, note: int) =
  for i in 0..<polyphony:
    if noteBuffer[i].note == note:
      noteBuffer[i].note = OffNote
      if bindings[i*2].isBound:
        var (voice,param) = bindings[i*2].getParameter()
        param.value = OffNote
        param.onchange(param.value, voice)


method midiEvent*(self: Keyboard, event: MidiEvent) =
  if event.command == 1:
    noteOn(event.data1.int, event.data2.int)
  elif event.command == 0:
    noteOff(event.data1.int)

proc newKeyboard(): Machine =
  var k = new(Keyboard)
  k.init()
  return k

method getAABB*(self: Keyboard): AABB =
  let w = nOctaves * 12 * size
  result.min.x = pos.x - (w div 2).float32
  result.min.y = pos.y - 13
  result.max.x = pos.x + (w div 2).float32
  result.max.y = pos.y + 7

method getKeyboardAABB*(self: Keyboard): AABB =
  let w = nOctaves * 12 * size
  result.min.x = pos.x - (w div 2).float32
  result.min.y = pos.y - 6
  result.max.x = pos.x + (w div 2).float32
  result.max.y = pos.y + 6

method drawBox*(self: Keyboard) =
  setColor(2)
  rectfill(getAABB())

  setColor(6)
  let w = nOctaves * 12 * size
  rectfill(getKeyboardAABB())
  # draw keyboard
  var x = pos.x - w div 2
  for n in baseOctave*12..<baseOctave*12+nOctaves*12:
    let key = n mod 12
    var down = false
    for i in noteBuffer:
      if i.note == n:
        down = true
        break

    case key:
    of 1,3,6,8,10:
      # black notes
      setColor(if down: 12 else: 1)
      rectfill(x, pos.y - 6, x + size - 1, pos.y + 6)
    else:
      if key == 0:
        setColor(if baseOctave == n div 12: 12 else: 13)
        print($(n div 12), x + 1, pos.y - 12)

      if key in [11,4]:
        setColor(6)
        vline(x + size, if key == 11: pos.y - 13 else: pos.y - 6, pos.y + 6)

      setColor(if down: 11 else: 7)
      rectfill(x, pos.y - 6, x + size - 1, pos.y + 6)
    x += size

method handleClick(self: Keyboard, mouse: Vec2f): bool =
  if pointInAABB(mouse, getKeyboardAABB()):
    let w = nOctaves * 12 * size
    let x = mouse.x - (pos.x - w div 2)
    let k = x div size + baseOctave * 12
    # find key under mouse
    if k mod 12 in scaleList[scale].notes:
      noteOn(k, 127)
    return true
  return false

method event(self: Keyboard, event: Event, camera: Vec2f): (bool, bool) =
  case event.kind:
  of ekMouseButtonDown:
    return (true,true)
  of ekMouseButtonUp:
    # find key under mouse
    let shift = shift()
    if not shift:
      for i in 0..<noteBuffer.len:
        if noteBuffer[i].note != OffNote:
          noteOff(noteBuffer[i].note)
    return (true,false)

  of ekMouseMotion:
      # find key under mouse
      let w = nOctaves * 12 * size
      let mouse = mouseVec() - camera
      let x = mouse.x - (pos.x - w div 2)
      let k = x div size + baseOctave * 12
      if k mod 12 in scaleList[scale].notes:
        noteOn(k, 127)
      return (false,true)
  else:
    discard

  return (false,true)

method trigger*(self: Keyboard, note: int) =
  self.noteOn(note, 255)

method release*(self: Keyboard, note: int) =
  self.noteOff(note)

registerMachine("keyboard", newKeyboard, "io")

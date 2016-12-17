import common
import basemachine
import util
import pico
import basic2d

const polyphony = 16

type Keyboard = ref object of Machine
  baseOctave: int
  nOctaves: int
  noteBuffer: array[polyphony, tuple[note: int, age: int]]
  scale: int

{.this:self.}

method init*(self: Keyboard) =
  procCall init(Machine(self))

  name = "keyboard"
  nOutputs = 0
  nInputs = 0
  nBindings = polyphony * 2
  bindings.setLen(nBindings)
  useMidi = true
  midiChannel = 0

  for i in 0..<polyphony:
    noteBuffer[i].note = OffNote

  self.globalParams.add([
    Parameter(name: "channel", kind: Int, min: 0.0, max: 15.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.midiChannel = newValue.int
    ),
    Parameter(name: "octaves", kind: Int, min: 1.0, max: 10.0, default: 7.0, onchange: proc(newValue: float, voice: int) =
      self.nOctaves = newValue.int
    ),
    Parameter(name: "baseoct", kind: Int, min: 0.0, max: 9.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.baseOctave = newValue.int
    ),
    Parameter(name: "scale", kind: Int, min: 1.0, max: 6.0, default: 2.0, onchange: proc(newValue: float, voice: int) =
      self.scale = newValue.int
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
        param.value = note.float
        param.onchange(param.value, voice)

      if bindings[i*2+1].isBound:
        var (voice,param) = bindings[i*2+1].getParameter()
        param.value = vel.float / 127.0
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
      param.value = note.float
      param.onchange(param.value, voice)

    if bindings[oldestVoice*2+1].isBound:
      var (voice,param) = bindings[oldestVoice*2+1].getParameter()
      param.value = vel.float / 127.0
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
  let w = nOctaves * 12 * scale
  result.min.x = pos.x - (w div 2).float
  result.min.y = pos.y - 13
  result.max.x = pos.x + (w div 2).float
  result.max.y = pos.y + 7

method getKeyboardAABB*(self: Keyboard): AABB =
  let w = nOctaves * 12 * scale
  result.min.x = pos.x - (w div 2).float
  result.min.y = pos.y - 6
  result.max.x = pos.x + (w div 2).float
  result.max.y = pos.y + 6

method drawBox*(self: Keyboard) =
  setColor(2)
  rectfill(getAABB())

  setColor(6)
  let w = nOctaves * 12 * scale
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
      setColor(if down: 12 else: 1)
      rectfill(x, pos.y - 6, x + scale - 1, pos.y + 2)
    of 0:
      setColor(if down: 11 else: 13)
      rectfill(x, pos.y - 6, x + scale - 1, pos.y + 6)
      setColor(13)
      print($(n div 12), x + 1, pos.y - 12)
    else:
      setColor(if down: 11 else: 6)
      rectfill(x, pos.y - 6, x + scale - 1, pos.y + 6)
    x += scale

method handleClick(self: Keyboard, mouse: Point2d): bool =
  if pointInAABB(mouse, getKeyboardAABB()):
    let w = nOctaves * 12 * scale
    let x = mouse.x - (pos.x - w div 2)
    let k = x div scale + baseOctave * 12
    # find key under mouse
    noteOn(k, 127)
    return true
  return false

method event(self: Keyboard, event: Event, camera: Point2d): (bool, bool) =

  case event.kind:
  of MouseButtonUp:
    # find key under mouse
    let shift = shift()
    if not shift:
      let w = nOctaves * 12 * scale
      let mouse = mouse() + camera
      let x = mouse.x - (pos.x - w div 2)
      let k = x div scale + baseOctave * 12
      noteOff(k)
    return (true,false)

  of MouseMotion:
      # find key under mouse
      return (true,true)
  else:
    discard

  return (false,true)



registerMachine("keyboard", newKeyboard, "util")

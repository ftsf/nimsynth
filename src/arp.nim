import common
import math
import master
import pico

{.this:self.}

type Chord = tuple[name: string, intervals: seq[int]]

const chords = [
  ("oct", @[0]),
  ("maj", @[0,4,7]),
  ("min", @[0,3,7]),
  ("dim", @[0,3,6]),
  ("aug", @[0,4,8]),
  ("sus4", @[0,5,7]),
  ("sus2", @[0,2,7]),
  ("7", @[0,4,7,10]),
  ("maj7", @[0,4,7,11]),
  ("min7", @[0,3,7,9]),
  ("mmaj7", @[0,3,7,11]),
  ("hdim", @[0,3,6,10]),
  ("dim7", @[0,3,6,9]),
  ("7dim5", @[0,4,6,10]),
  ("maj7dim5", @[0,4,6,11]),
  ("maj7aug5", @[0,4,8,11]),
  ("7sus4", @[0,5,7,10]),
  ("maj7sus4", @[0,5,7,11]),
]

type ArpMode = enum
  Up
  Down
  UpDown

type Arp = ref object of Machine
  note: int
  chord: int
  speed: float # tpb
  nNotes: int  # how many notes in the sequence to loop over
  mode: ArpMode

  step: float
  playing: bool

method init(self: Arp) =
  procCall init(Machine(self))

  nInputs = 0
  nOutputs = 0
  nBindings = 1
  bindings.setLen(1)
  name = "arp"

  setDefaults()

  globalParams.add([
    Parameter(kind: Note, name: "note", min: OffNote, max: 256.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      self.note = newValue.int
      self.step = 0.0
      self.playing = if self.note == OffNote: false else: true
      if self.note == OffNote:
        # send target OffNote too
        if bindings[0].machine != nil:
          var (voice, param) = bindings[0].getParameter()
          param.value = newValue
          param.onchange(newValue, voice)
    , getValueString: proc(value: float, voice: int): string =
      return noteToNoteName(value.int)
    ),
    Parameter(kind: Int, name: "chord", min: 0.0, max: chords.high.float, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.chord = newValue.int
    , getValueString: proc(value: float, voice: int): string =
      return chords[value.int][0]
    ),
    Parameter(kind: Int, name: "mode", min: mode.low.float, max: mode.high.float, default: Up.float, onchange: proc(newValue: float, voice: int) =
      self.mode = newValue.ArpMode
    , getValueString: proc(value: float, voice: int): string =
      return $value.ArpMode
    ),
    Parameter(kind: Int, name: "speed", min: 1.0, max: 16.0, default: 4.0, onchange: proc(newValue: float, voice: int) =
      self.speed = newValue
    ),
    Parameter(kind: Int, name: "notes", min: 1.0, max: 16.0, default: 4.0, onchange: proc(newValue: float, voice: int) =
      self.nNotes = newValue.int
    ),
  ])

  setDefaults()

method process(self: Arp) =
  if playing:
    let lastTick = step.int
    step += (beatsPerSecond() * speed) * invSampleRate
    if step.int >= nNotes:
      step = step mod nNotes.float
    let i = step.int
    if bindings[0].machine != nil:
      if lastTick != i:
        var (voice, param) = bindings[0].getParameter()
        let intervals = chords[chord][1]

        var j = i
        case mode:
        of Up:
          j = i
        of Down:
          j = nNotes - i
        of UpDown:
          j = if i < nNotes div 2: i else: nNotes - i
        let oct = j div intervals.len
        param.value = (note + intervals[j mod intervals.len] + oct * 12).float
        param.onchange(param.value, voice)

method drawExtraInfo(self: Arp, x,y,w,h: int) =
  let intervals = chords[chord][1]
  var yv = y
  for i in 0..nNotes-1:
    setColor(if i == step.int: 8 else: 6)
    var j = i
    case mode:
    of Up:
      j = i
    of Down:
      j = (nNotes - 1) - i
    of UpDown:
      j = if i < nNotes div 2: i else: nNotes - i

    let oct = j div intervals.len
    print(noteToNoteName(note + intervals[j mod intervals.len] + oct * 12), x + 1, yv)

    yv += 8


proc newArp(): Machine =
  var arp = new(Arp)
  arp.init()
  return arp

registerMachine("arp", newArp)

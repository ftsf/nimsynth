import math

import nico

import common

import machines/master

import core/chords


{.this:self.}

type ArpMode = enum
  Up
  Down
  UpDown

type Arp = ref object of Machine
  note: int
  chord: int
  speed: float32 # tpb
  nNotes: int  # how many notes in the sequence to loop over
  mode: ArpMode

  step: float32
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
    Parameter(kind: Note, name: "note", min: OffNote, max: 256.0, default: OffNote, onchange: proc(newValue: float32, voice: int) =
      self.note = newValue.int
      self.step = 0.0
      self.playing = if self.note == OffNote: false else: true
      if self.note == OffNote:
        # send target OffNote too
        if self.bindings[0].isBound():
          var (voice, param) = self.bindings[0].getParameter()
          param.value = newValue
          param.onchange(newValue, voice)
    , getValueString: proc(value: float32, voice: int): string =
      return noteToNoteName(value.int)
    ),
    Parameter(kind: Int, name: "chord", min: 0.0, max: chordList.high.float32, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.chord = newValue.int
    , getValueString: proc(value: float32, voice: int): string =
      return chordList[value.int][0]
    ),
    Parameter(kind: Int, name: "mode", min: mode.low.float32, max: mode.high.float32, default: Up.float32, onchange: proc(newValue: float32, voice: int) =
      self.mode = newValue.ArpMode
    , getValueString: proc(value: float32, voice: int): string =
      return $value.ArpMode
    ),
    Parameter(kind: Int, name: "speed", min: 1.0, max: 16.0, default: 4.0, onchange: proc(newValue: float32, voice: int) =
      self.speed = newValue
    ),
    Parameter(kind: Int, name: "notes", min: 1.0, max: 16.0, default: 4.0, onchange: proc(newValue: float32, voice: int) =
      self.nNotes = newValue.int
    ),
  ])

  setDefaults()

method process(self: Arp) =
  if playing:
    let lastTick = step.int
    step += (beatsPerSecond() * speed) * invSampleRate
    if step.int >= nNotes:
      step = step mod nNotes.float32
    let i = step.int
    if bindings[0].machine != nil:
      if lastTick != i:
        var (voice, param) = bindings[0].getParameter()
        let intervals = chordList[chord][1]

        var j = i
        case mode:
        of Up:
          j = i
        of Down:
          j = nNotes - i
        of UpDown:
          j = if i < nNotes div 2: i else: nNotes - i
        let oct = j div intervals.len
        param.value = (note + intervals[j mod intervals.len] + oct * 12).float32
        param.onchange(param.value, voice)

method drawExtraData(self: Arp, x,y,w,h: int) =
  let intervals = chordList[chord][1]
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

registerMachine("arp", newArp, "util")

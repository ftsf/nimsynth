import math

import nico

import ../../common

{.this:self.}

import ../../core/chords

type ChordMachine = ref object of Machine
  root: int
  chord: int
  inversion: int
  delay: float32
  reverse: bool
  currentChord: seq[int]
  chordNoteIndex: int
  nextNoteTimer: float32

proc startChord(self: ChordMachine, root: int, chord: int, inversion: int) =
  self.root = root
  self.chord = chord
  self.inversion = inversion

  if root == OffNote:
    currentChord = @[]
    for i in 0..<4:
      if self.bindings[i].isBound():
        var (voice, param) = self.bindings[i].getParameter()
        param.value = OffNote
        param.onchange(OffNote, voice)
  else:
    currentChord = @[]
    for i in 0..<4:
      let chordIntervals = chordList[chord].intervals
      let chordNote = if i < chordIntervals.len: root + chordIntervals[i] else: OffNote
      currentChord.add(chordNote)
      chordNoteIndex = 0
      nextNoteTimer = 0
    for i in 0..<self.inversion:
      # move lowest note up an octave
      var newNote = currentChord[0]+12
      currentChord.delete(0)
      currentChord.add(newNote)

method init(self: ChordMachine) =
  procCall init(Machine(self))

  nInputs = 0
  nOutputs = 0
  nBindings = 4
  bindings.setLen(4)
  for i in 0..<nBindings:
    bindings[i].kind = bkNote

  name = "chord"

  setDefaults()

  globalParams.add([
    Parameter(kind: Note, name: "note", min: OffNote, max: 256.0, default: OffNote, deferred: true, onchange: proc(newValue: float, voice: int) =
      self.root = newValue.int
      self.startChord(self.root, self.chord, self.inversion)

    , getValueString: proc(value: float, voice: int): string =
      return noteToNoteName(value.int)
    ),
    Parameter(kind: Int, name: "chord", min: 0.0, max: chordList.high.float, deferred: true, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.chord = newValue.int
      self.startChord(self.root, self.chord, self.inversion)
    , getValueString: proc(value: float, voice: int): string =
      return chordList[value.int][0]
    ),
    Parameter(kind: Int, name: "inversion", min: 0.0, max: 4.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.inversion = newValue.int
      self.startChord(self.root, self.chord, self.inversion)
    ),
    Parameter(kind: Float, name: "delay", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.delay = newValue.float32
    ),
    Parameter(kind: Int, name: "reverse", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.reverse = newValue.bool
    ),
  ])

  setDefaults()

method process(self: ChordMachine) =
  if self.nextNoteTimer > 0:
    self.nextNoteTimer -= invSampleRate

  if self.currentChord.len > 0:
    for i in 0..<4:
      if self.nextNoteTimer <= 0 and i == self.chordNoteIndex and self.bindings[i].isBound():
        if i < self.currentChord.len:
          var (voice, param) = self.bindings[i].getParameter()
          var chordNote = if self.reverse: self.currentChord[^(self.chordNoteIndex+1)] else: self.currentChord[self.chordNoteIndex]
          param.value = chordNote.float32
          param.onchange(chordNote.float32, voice)
        else:
          var (voice, param) = self.bindings[i].getParameter()
          param.value = OffNote
          param.onchange(OffNote, voice)
        self.chordNoteIndex += 1
        self.nextNoteTimer = self.delay

proc newChordMachine(): Machine =
  var m = new(ChordMachine)
  m.init()
  return m

registerMachine("chord", newChordMachine, "util")

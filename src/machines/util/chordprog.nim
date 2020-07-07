import math

import nico

import common

{.this:self.}

import core/chords
import core/scales

type ChordProgMachine = ref object of Machine
  baseNote: int
  scale: int
  degree: int
  chordsInScale: seq[seq[int]]

proc populateChords(self: ChordProgMachine) =
  self.chordsInScale = @[]
  let realScale = instantiateScale(scaleList[self.scale], self.baseNote)
  for note in realScale.notes:
    var foundChord = false
    for chord in chordList:
      if chord.intervals.len < 3:
        continue
      let realChord = instantiateChord(chord, note)
      var allNotesInScale = true
      for n in realChord.intervals:
        var noteInScale = false
        for n2 in realScale.notes:
          if n mod 12 == n2 mod 12:
            noteInScale = true
            break
        if noteInScale == false:
          allNotesInScale = false
          break
      if allNotesInScale:
        self.chordsInScale.add(realChord.intervals)
        foundChord = true
        break
    if foundChord == false:
      echo "no chord for note ", noteToNoteStr(note)

proc playChord(self: ChordProgMachine) =
  if self.degree < 1 or self.degree > 6:
    for i in 0..<4:
      if self.bindings[i].isBound():
        var (voice, param) = self.bindings[i].getParameter()
        param.value = OffNote
        param.onchange(param.value, voice)
    return

  if self.chordsInScale.len == 0:
    return
  for i in 0..<4:
    let chordIntervals = self.chordsInScale[(self.degree - 1) mod 7]
    if self.bindings[i].isBound():
      let chordNote = if i < chordIntervals.len: chordIntervals[i] else: OffNote
      var (voice, param) = self.bindings[i].getParameter()
      param.value = chordNote.float32
      param.onchange(chordNote.float32, voice)

method init(self: ChordProgMachine) =
  procCall init(Machine(self))

  nInputs = 0
  nOutputs = 0
  nBindings = 4
  bindings.setLen(4)
  for i in 0..<nBindings:
    bindings[i].kind = bkNote

  name = "chordp"

  setDefaults()

  globalParams.add([
    Parameter(kind: Note, name: "key", min: 0, max: 256, default: 0, deferred: true, onchange: proc(newValue: float, voice: int) =
      self.baseNote = newValue.int
      # populate chords in scale
      if self.baseNote != OffNote:
        self.populateChords()
    ),
    Parameter(kind: Int, name: "scale", min: 0'f, max: scaleList.high.int.float32, default: 0'f, deferred: true, onchange: proc(newValue: float, voice: int) =
      self.scale = newValue.int
      if self.baseNote != OffNote:
        self.populateChords()
    , getValueString: proc(value: float, voice: int): string =
      return scaleList[value.int].name
    ),
    Parameter(kind: Int, name: "degree", min: 0, max: 6, default: 0, onchange: proc(newValue: float, voice: int) =
      self.degree = newValue.int
      self.playChord()
    , getValueString: proc(value: float, voice: int): string =
      # show number and notes in chord
      let degree = value.int
      if degree < 1 or degree > 6:
        return $degree
      result = $(degree) & ": "
      for i in 0..<self.chordsInScale[degree-1].len:
        result &= noteToNoteStr(self.chordsInScale[degree-1][i])
        result &= " "
    ),
  ])

  setDefaults()

proc newChordProgMachine(): Machine =
  var m = new(ChordProgMachine)
  m.init()
  return m

registerMachine("chordp", newChordProgMachine, "util")

type Scale* = object
  name*: string
  notes*: seq[int]

type ConcreteScale* = object
  name*: string
  baseNote*: int
  notes*: seq[int]

const scaleMajor* = Scale(name: "Major", notes: @[0, 2, 4, 5, 7, 9, 11])
const scaleMinor* = Scale(name: "Minor", notes: @[0, 2, 3, 5, 7, 8, 10])
const scaleMajorTriad* = Scale(name: "MajorTriad", notes: @[0, 4, 7, 11])
const scaleMinorTriad* = Scale(name: "MinorTriad", notes: @[0, 3, 7, 10])
const scaleDorian* = Scale(name: "Dorian", notes: @[0, 2, 3, 6, 7, 9, 10])
const scalePentatonic* = Scale(name: "Pentatonic", notes: @[0, 2, 5, 7, 9])
const scaleBlues* = Scale(name: "Blues", notes: @[0, 3, 5, 6, 7, 10])
const scaleChromatic* = Scale(name: "Chromatic", notes: @[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])

const scaleList* = [
  scaleMajor,
  scaleMinor,
  scaleMajorTriad,
  scaleMinorTriad,
  scaleDorian,
  scalePentatonic,
  scaleBlues,
  scaleChromatic,
]

proc instantiateScale*(scale: Scale, baseNote: int): ConcreteScale =
  result.name = scale.name
  result.baseNote = baseNote
  result.notes = scale.notes
  for i in 0..<result.notes.len:
    result.notes[i] += baseNote

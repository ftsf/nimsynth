type Chord* = tuple[name: string, intervals: seq[int]]
const chordList*: seq[Chord] = @[
  ("oct", @[0]),
  ("maj", @[0,4,7]),
  ("min", @[0,3,7]),
  ("dim", @[0,3,6]),
  ("aug", @[0,4,8]),
  ("sus4", @[0,5,7]),
  ("sus2", @[0,2,7]),
  ("7", @[0,4,7,10]),
  ("maj7", @[0,4,7,11]),
  ("min7", @[0,3,7,10]),
  ("mmaj7", @[0,3,7,11]),
  ("hdim", @[0,3,6,10]),
  ("dim7", @[0,3,6,9]),
  ("7dim5", @[0,4,6,10]),
  ("maj7dim5", @[0,4,6,11]),
  ("maj7aug5", @[0,4,8,11]),
  ("7sus4", @[0,5,7,10]),
  ("maj7sus4", @[0,5,7,11]),
]

proc instantiateChord*(chord: Chord, baseNote: int): Chord =
  result.name = chord.name
  result.intervals = chord.intervals
  for i in 0..<result.intervals.len:
    result.intervals[i] += baseNote

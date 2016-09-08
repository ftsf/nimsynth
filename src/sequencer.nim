{.this:self.}

import strutils
import pico
import common

const colsPerPattern = 16

type
  Pattern* = ref object of RootObj
    rows*: seq[array[colsPerPattern, uint8]]
  Sequencer* = ref object of View
    patterns*: seq[Pattern]
    bindings*: array[colsPerPattern, tuple[machine: int, param: int]]
    currentPattern*: int
    currentStep*: int
    currentColumn*: int
    step*: int
    stepsPerSecond*: float

proc newPattern*(): Pattern =
  result = new(Pattern)
  result.rows = newSeq[array[colsPerPattern, uint8]](16)

proc newSequencer*(): Sequencer =
  result = new(Sequencer)
  result.patterns = newSeq[Pattern]()
  result.patterns.add(newPattern())

method draw*(self: Sequencer) =
  cls()
  let pattern = patterns[currentPattern]
  for i,row in pattern.rows:
    for j,col in row:
      setColor(if i == currentStep and j == currentColumn: 7 else: 13)
      print(if col == 0: "..." else: toHex(col.int), j * 16, i * 8)

method update*(self: Sequencer, dt: float) =
  let pattern = patterns[currentPattern]
  if btnp(0):
    currentColumn -= 1
    if currentColumn < 0:
      currentColumn = colsPerPattern - 1
  if btnp(1):
    currentColumn += 1
    if currentColumn > colsPerPattern:
      currentColumn = 0
  if btnp(2):
    currentStep -= 1
    if currentStep < 0:
      currentStep = 0
  if btnp(3):
    currentStep += 1
    if currentStep > pattern.rows.high:
      pattern.rows.setLen(currentStep+1)

import common
import filter
import math
import util
import pico

{.this:self.}

type
  Operation = enum
    Add
    Sub
    Mul
    Div
  Dummy = ref object of Machine
    operation: Operation

method init(self: Dummy) =
  procCall init(Machine(self))
  name = "."
  nInputs = 2
  nOutputs = 1
  stereo = true

  globalParams.add([
    Parameter(kind: Int, name: "op", min: Operation.low.float, max: Operation.high.float, default: Add.float, onchange: proc(newValue: float, voice: int) =
      self.operation = newValue.Operation
    , getValueString: proc(value: float, voice: int): string =
      return $value.Operation
    ),
  ])

  setDefaults()


method process(self: Dummy) {.inline.} =
  case operation:
  of Add:
    outputSamples[0] = getInput(0) + getInput(1)
  of Sub:
    outputSamples[0] = getInput(0) - getInput(1)
  of Mul:
    outputSamples[0] = getInput(0) * getInput(1)
  of Div:
    let divisor = getInput(1)
    if divisor == 0:
      outputSamples[0] = 0.0
    else:
      outputSamples[0] = getInput(0) / divisor

method getAABB(self: Dummy): AABB =
  result.min.x = pos.x - 4
  result.min.y = pos.y - 4
  result.max.x = pos.x + 4
  result.max.y = pos.y + 4

method drawBox(self: Dummy) =
  setColor(1)
  circfill(pos.x, pos.y, 4)
  setColor(6)

  printc(
    case operation:
    of Add:
      "+"
    of Sub:
      "-"
    of Mul:
      "*"
    of Div:
      "/"
    , pos.x + 1, pos.y - 2)

  circ(pos.x, pos.y, 4)

proc newDummy(): Machine =
  var m = new(Dummy)
  m.init()
  return m

registerMachine("dummy", newDummy, "util")

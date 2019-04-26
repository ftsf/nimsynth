import math

import nico

import common
import util

import core/filter


{.this:self.}

type
  Operation = enum
    Add
    Sub
    Mul
    Div
    Exp
  Operator = ref object of Machine
    operation: Operation
  OperatorE = ref object of Machine
    operation: Operation
    v1,v2: float

method init(self: Operator) =
  procCall init(Machine(self))
  name = "."
  nInputs = 2
  nOutputs = 1
  stereo = false

  globalParams.add([
    Parameter(kind: Int, name: "op", min: Operation.low.float, max: Operation.high.float, default: Add.float, onchange: proc(newValue: float, voice: int) =
      self.operation = newValue.Operation
    , getValueString: proc(value: float, voice: int): string =
      return $value.Operation
    ),
  ])

  setDefaults()

proc send(self: OperatorE) =
  if bindings[0].isBound():
    var (voice,param) = bindings[0].getParameter()
    case self.operation:
    of Add:
      param.value = self.v1 + self.v2
    of Sub:
      param.value = self.v1 - self.v2
    of Mul:
      param.value = self.v1 * self.v2
    of Div:
      if self.v2 != 0:
        param.value = self.v1 / self.v2
    of Exp:
      param.value = pow(self.v1,self.v2)
    param.onchange(param.value, voice)

method init(self: OperatorE) =
  procCall init(Machine(self))
  name = "."
  nInputs = 0
  nOutputs = 0
  stereo = false

  bindings = newSeq[Binding](1)
  nBindings = 1

  globalParams.add([
    Parameter(kind: Int, name: "op", min: Operation.low.float, max: Operation.high.float, default: Add.float, onchange: proc(newValue: float, voice: int) =
      self.operation = newValue.Operation
    , getValueString: proc(value: float, voice: int): string =
      return $value.Operation
    ),
    Parameter(kind: Float, name: "v1", min: -1000.0, max: 1000.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.v1 = newValue
      self.send()

    ),
    Parameter(kind: Float, name: "v2", min: -1000.0, max: 1000.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.v2 = newValue
      self.send()
    ),
  ])

  setDefaults()


method process(self: Operator) {.inline.} =
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
  of Exp:
    outputSamples[0] = pow(getInput(0), getInput(1))

method getAABB(self: Operator): AABB =
  result.min.x = pos.x - 4
  result.min.y = pos.y - 4
  result.max.x = pos.x + 4
  result.max.y = pos.y + 4

method getAABB(self: OperatorE): AABB =
  result.min.x = pos.x - 4
  result.min.y = pos.y - 4
  result.max.x = pos.x + 4
  result.max.y = pos.y + 4

method drawBox(self: Operator) =
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
    of Exp:
      "^"
    , pos.x + 1, pos.y - 2)

  circ(pos.x, pos.y, 4)

method drawBox(self: OperatorE) =
  setColor(2)
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
    of Exp:
      "^"
    , pos.x + 1, pos.y - 2)

  circ(pos.x, pos.y, 4)

proc newOperator(): Machine =
  var m = new(Operator)
  m.init()
  return m

proc newOperatorE(): Machine =
  var m = new(OperatorE)
  m.init()
  return m

registerMachine("op-a", newOperator, "math")
registerMachine("op-e", newOperatorE, "math")

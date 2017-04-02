import math

import common
import util

import core.filter


{.this:self.}


type
  FilterMachine = ref object of Machine
    filter: BiquadFilter

method init(self: FilterMachine) =
  procCall init(Machine(self))
  name = "filter"
  nInputs = 1
  nOutputs = 1
  stereo = false
  filter.init()

  self.globalParams.add([
    Parameter(name: "type", kind: Int, min: FilterKind.low.float, max: FilterKind.high.float, default: Lowpass.float, onchange: proc(newValue: float, voice: int) =
      self.filter.kind = newValue.FilterKind
    , getValueString: proc(value: float, voice: int): string =
      return $value.FilterKind
    ),
    Parameter(name: "cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      self.filter.cutoff = exp(lerp(-8.0, -0.8, newValue))
    , getValueString: proc(value: float, voice: int): string =
      return $(exp(lerp(-8.0, -0.8, value)) * sampleRate).int & " hZ"
    ),
    Parameter(name: "q", kind: Float, min: 0.00001, max: 10.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      self.filter.resonance = newValue
    ),
  ])

  setDefaults()


method process(self: FilterMachine) {.inline.} =
  outputSamples[0] = getInput()
  filter.calc()
  outputSamples[0] = filter.process(outputSamples[0])

proc newFilterMachine(): Machine =
  result = new(FilterMachine)
  result.init()

registerMachine("filter", newFilterMachine, "fx")

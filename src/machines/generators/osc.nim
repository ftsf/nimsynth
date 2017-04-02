import common

import core.oscillator


{.this:self.}

type
  OscMachine = ref object of Machine
    osc: Osc
    phaseOffset: float

method init(self: OscMachine) =
  procCall init(Machine(self))
  name = "osc"
  nInputs = 0
  nOutputs = 1
  stereo = false

  globalParams.add([
    Parameter(kind: Int, name: "shape", min: OscKind.low.float, max: OscKind.high.float, onchange: proc(newValue: float, voice: int) =
      osc.kind = newValue.OscKind
    , getValueString: proc(value: float, voice: int): string =
      return $value.OscKind
    ),
    Parameter(kind: Float, name: "freq", min: 0.0001, max: 24000.0, default: 440.0, onchange: proc(newValue: float, voice: int) =
      osc.freq = newValue
    ),
    Parameter(kind: Float, name: "pw", min: 0.0001, max: 0.9999, default: 0.5, onchange: proc(newValue: float, voice: int) =
      osc.pulseWidth = newValue
    ),
    Parameter(kind: Float, name: "phmod", min: 0.0, max: 10.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      phaseOffset = newValue
    ),
  ])

  setDefaults()

method process(self: OscMachine) =
  osc.phase += phaseOffset
  outputSamples[0] = osc.process()
  osc.phase -= phaseOffset

proc newOscMachine(): Machine =
 var m = new(OscMachine)
 m.init()
 return m

#registerMachine("osc", newOscMachine, "generator")

proc createMachine*(): Machine {.cdecl, exportc, dynlib.} =
  echo "create machine called"
  var m = new(OscMachine)
  m.init()
  return m

proc processSample*(self: OscMachine) {.cdecl, exportc, dynlib.} =
  self.process()

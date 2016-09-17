import common
import osc
import util

type
  LFO = ref object of Machine
    osc: Osc
    min,max: float
    freq: float
    bpmSync: bool

{.this:self.}

proc setFreq(self: LFO) =
  if bpmSync:
    osc.freq = freq * (beatsPerMinute.float / 60.0)
  else:
    osc.freq = freq

method init(self: LFO) =
  procCall init(Machine(self))
  nOutputs = 0
  nInputs = 0
  name = "lfo"
  nBindings = 1
  bindings.setLen(1)

  globalParams.add([
    Parameter(name: "freq", kind: Float, min: 0.0001, max: 100.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.freq = newValue
      self.setFreq()
    , getValueString: proc(value: float, voice: int): string =
      if self.bpmSync:
        return $(self.freq).int & " hZ"
      else:
        return $(self.freq * (beatsPerMinute.float / 60.0)).int & " beats"
    ),
    Parameter(name: "shape", kind: Int, min: OscKind.low.float, max: OscKind.high.float, default: Sin.float, onchange: proc(newValue: float, voice: int) =
      self.osc.kind = newValue.OscKind
    ),
    Parameter(name: "min", kind: Float, min: 0.0, max: 1.0, default: 0.1, onchange: proc(newValue: float, voice: int) =
      self.min = newValue
    ),
    Parameter(name: "max", kind: Float, min: 0.0, max: 1.0, default: 0.9, onchange: proc(newValue: float, voice: int) =
      self.max = newValue
    ),
    Parameter(name: "sync", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.bpmSync = newValue.bool
      self.setFreq()
    ),
  ])

  setDefaults()

method process(self: LFO) {.inline.} =
  for binding in bindings:
    if binding.machine != nil:
      var (voice, param) = binding.machine.getParameter(binding.param)
      param.value = lerp(param.min, param.max, lerp((osc.process() + 1.0) / 2.0, min, max))
      param.onchange(param.value, voice)

proc newLFO(): Machine =
  var lfo = new(LFO)
  lfo.init()
  return lfo

registerMachine("lfo", newLFO)

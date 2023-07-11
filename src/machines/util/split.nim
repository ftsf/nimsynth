import ../../common

{.this:self.}

type
  SplitMachine = ref object of Machine

# takes an event input and duplicates it

method init(self: SplitMachine) =
  procCall init(Machine(self))
  name = "split"
  nInputs = 0
  nOutputs = 0
  stereo = false

  nBindings = 8
  bindings = newSeq[Binding](8)

  globalParams.add([
    Parameter(name: "value", kind: Float, min: -1000.0, max: 1000.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      for i in 0..7:
        if bindings[i].isBound():
          var (voice,param) = bindings[i].getParameter()
          param.value = newValue
          param.onchange(newValue, voice)
    ),
  ])

  setDefaults()

method createBinding(self: SplitMachine, slot: int, target: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, target, paramId)
  var binding = bindings[0].addr
  var (voice, param) = binding.machine.getParameter(binding.param)
  globalParams[0].kind = param.kind

proc newSplitMachine(): Machine =
  var m = new(SplitMachine)
  m.init()
  return m

registerMachine("split", newSplitMachine, "util")

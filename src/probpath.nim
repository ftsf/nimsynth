## When triggered sends a signal to a weighted random binding

import common
import random


{.this:self.}

type
  ProbPathVoice = ref object of Voice
    value: float
    weight: float
  ProbPath = ref object of Machine

method init(self: ProbPathVoice, machine: Machine) =
  procCall init(Voice(self), machine)

method addVoice(self: ProbPath) =
  var voice = new(ProbPathVoice)
  voice.init(self)
  voices.add(voice)

method init(self: ProbPath) =
  procCall init(Machine(self))
  nInputs = 0
  nOutputs = 0
  nBindings = 1
  name = "probpath"
  bindings.setLen(1)

  globalParams.add([
    Parameter(kind: Trigger, name: "trigger", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      # sum up all the voices
      var weight = 0.0
      if self.bindings[0].isBound():
        for voice in self.voices:
          var v = ProbPathVoice(voice)
          weight += v.weight
        let r = random(weight)
        var vr = 0.0
        for voice in self.voices:
          var v = ProbPathVoice(voice)
          vr += v.weight
          if vr >= r:
            var (voice,param) = self.bindings[0].getParameter()
            param.value = v.value
            param.onchange(v.value, voice)
            break
    ),
  ])
  voiceParams.add([
    Parameter(kind: Float, name: "output", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      var v = ProbPathVoice(self.voices[voice])
      v.value = newValue
    ),
    Parameter(kind: Float, name: "weight", min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      var v = ProbPathVoice(self.voices[voice])
      v.weight = newValue
    ),
  ])

  setDefaults()

method createBinding*(self: ProbPath, slot: int, target: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, target, paramId)

  # match input to be the same as the target param
  var (voice,param) = target.getParameter(paramId)
  var inputParam = globalParams[1].addr
  inputParam.kind = param.kind
  inputParam.min = param.min
  inputParam.max = param.max
  inputParam.default = param.default
  inputParam.getValueString = param.getValueString

  inputParam = voiceParams[0].addr
  inputParam.kind = param.kind
  inputParam.min = param.min
  inputParam.max = param.max
  inputParam.default = param.default
  inputParam.getValueString = param.getValueString

  for voice in mitems(voices):
    var v = ProbPathVoice(voice)
    v.parameters[0].kind = param.kind
    v.parameters[0].min = param.min
    v.parameters[0].max = param.max
    v.parameters[0].default = param.default
    v.parameters[0].getValueString = param.getValueString

proc newProbPath(): Machine =
  var pp = new(ProbPath)
  pp.init()
  return pp


registerMachine("probpath", newProbPath)

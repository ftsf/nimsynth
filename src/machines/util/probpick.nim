## When triggered sends a weighted random signal

import ../../common
import random


{.this:self.}

type
  ProbPickVoice = ref object of Voice
    value: float
    weight: float
  ProbPick = ref object of Machine

method init(self: ProbPickVoice, machine: Machine) =
  procCall init(Voice(self), machine)

method addVoice(self: ProbPick) =
  var voice = new(ProbPickVoice)
  voices.add(voice)
  voice.init(self)

method init(self: ProbPick) =
  procCall init(Machine(self))
  nInputs = 0
  nOutputs = 0
  nBindings = 1
  name = "probpick"
  bindings.setLen(1)

  globalParams.add([
    Parameter(kind: Trigger, name: "trigger", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      # sum up all the voices
      var weight = 0.0
      if self.bindings[0].isBound():
        for voice in self.voices:
          var v = ProbPickVoice(voice)
          weight += v.weight
        let r = rand(weight)
        var vr = 0.0
        for voice in self.voices:
          var v = ProbPickVoice(voice)
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
      var v = ProbPickVoice(self.voices[voice])
      v.value = newValue
    ),
    Parameter(kind: Float, name: "weight", min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
      var v = ProbPickVoice(self.voices[voice])
      v.weight = newValue
    ),
  ])

  setDefaults()

method createBinding*(self: ProbPick, slot: int, target: Machine, paramId: int) =
  procCall createBinding(Machine(self), slot, target, paramId)

  # match input to be the same as the target param
  var (voice,param) = target.getParameter(paramId)

  var inputParam = voiceParams[0].addr
  inputParam.kind = param.kind
  inputParam.min = param.min
  inputParam.max = param.max
  inputParam.default = param.default
  inputParam.getValueString = param.getValueString

  for voice in mitems(voices):
    var v = ProbPickVoice(voice)
    v.parameters[0].kind = param.kind
    v.parameters[0].min = param.min
    v.parameters[0].max = param.max
    v.parameters[0].default = param.default
    v.parameters[0].getValueString = param.getValueString

proc newProbPick(): Machine =
  var pp = new(ProbPick)
  pp.init()
  return pp


registerMachine("%pick", newProbPick, "util")

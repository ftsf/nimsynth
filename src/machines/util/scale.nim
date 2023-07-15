import math
import strutils

import random

import nico
import nico/vec

import common
import util

import core/scales

import core/basemachine
import ui/machineview
import machines/master

type
  ScaleMachine = ref object of Machine
    scale: int
    baseNote: int

method init(self: ScaleMachine) =
  procCall init(Machine(self))

  self.name = "scale"
  self.nOutputs = 0
  self.nInputs = 0
  self.nBindings = 1
  self.bindings.setLen(1)

  self.globalParams.add([
    Parameter(kind: Note, name: "base", min: 0.0, max: 255.0, default: 48.0, onchange: proc(newValue: float32, voice: int) =
      self.baseNote = newValue.int
    ),
    Parameter(kind: Int, name: "scale", min: 0.0, max: scaleList.high.float32, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      self.scale = newValue.int
    , getValueString: proc(value: float32, voice: int): string =
      return scaleList[value.int].name
    ),
    Parameter(kind: Int, name: "input", min: 0.0, max: 255.0, default: 0.0, onchange: proc(newValue: float32, voice: int) =
      if self.bindings[0].isBound():
        var (voice,param) = self.bindings[0].getParameter()
        let scale = scaleList[self.scale]
        let n = newValue.int
        let oct = n div scale.notes.len
        param.value = (self.baseNote + 12 * oct + scale.notes[n mod scale.notes.len]).float32
        param.onchange(param.value, voice)

    ),
  ])

  self.setDefaults()

proc newMachine(): Machine =
  var m = new(ScaleMachine)
  m.init()
  return m

registerMachine("scale", newMachine, "util")

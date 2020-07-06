import math
import strutils

import nico

import common

import core/envelope
import core/sample
import ui/menu

import machines.master


type
  Looper = ref object of Machine
    playing: bool
    osc: SampleOsc

{.this:self.}

method init(self: Looper) =
  procCall init(Machine(self))
  name = "looper"
  nOutputs = 1
  nInputs = 0
  stereo = true

  osc.stereo = true

  globalParams.add([
    Parameter(name: "trigger", separator: true, deferred: true, kind: Trigger, min: 0.0, max: 1.0, onchange: proc(newValue: float, voice: int) =
      if osc.sample != nil:
        playing = true
        osc.reset()
    ),
    Parameter(name: "loop", kind: Bool, min: 0.0, max: 1.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      osc.loop = newValue.bool
    ),
    Parameter(name: "speed", kind: Float, min: 0.00001, max: 4.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      osc.speed = newValue
    ),
    Parameter(name: "length", kind: Int, min: 1.0, max: 64.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      osc.setSpeedByLength(newValue.int.float / beatsPerSecond())
      globalParams[2].value = osc.speed
    ),
    Parameter(name: "offset", kind: Float, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      osc.offset = newValue
    ),
  ])

  setDefaults()

method onBPMChange(self: Looper, bpm: int) =
  let length = globalParams[3].value.int
  osc.setSpeedByLength(length.float / beatsPerSecond())
  globalParams[2].value = osc.speed

method process*(self: Looper) {.inline.} =
  if osc.sample != nil:
    if playing:
      outputSamples[0] = osc.process()
      if osc.finished:
        playing = false

method updateExtraData(self: Looper, x,y,w,h: int) =
  if mousebtnp(0):
    let (mx,my) = mouse()
    # open sample selection menu
    pushMenu(newSampleMenu(vec2f(mx,my), "samples/") do(sample: Sample):
      self.osc.sample = sample
      self.osc.reset()
    )


method saveExtraData(self: Looper): string =
  result = ""
  if osc.sample != nil:
    result = osc.sample.filename

method loadExtraData(self: Looper, data: string) =
  if data != "":
    osc.sample = loadSample(data, data)

proc newMachine(): Machine =
  var m = new(Looper)
  m.init()
  return m

registerMachine("looper", newMachine, "generator")

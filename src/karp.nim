import common
import math
import master
import pico

{.this:self.}

type KArpMode = enum
  Up
  Down
  UpDown
  Random

const maxSteps = 16

type
  KArp = ref object of Machine
    speed: float # tpb
    mode: KArpMode

    steps: array[maxSteps, int]
    step: float

method init(self: KArp) =
  procCall init(Machine(self))

  nInputs = 0
  nOutputs = 0
  nBindings = 1
  bindings.setLen(1)
  name = "Karp"

  setDefaults()

  for i in 0..<maxSteps:
    steps[i] = OffNote

  globalParams.add([
    Parameter(kind: Int, name: "mode", min: mode.low.float, max: mode.high.float, default: Up.float, onchange: proc(newValue: float, voice: int) =
      self.mode = newValue.KArpMode
    , getValueString: proc(value: float, voice: int): string =
      return $value.KArpMode
    ),
    Parameter(kind: Int, name: "speed", min: 1.0, max: 16.0, default: 4.0, onchange: proc(newValue: float, voice: int) =
      self.speed = newValue
    ),
    Parameter(kind: Trigger, name: "reset", min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.step = 0.0
    ),

  ])

  voiceParams.add([
    Parameter(kind: Note, name: "note", min: OffNote, max: 256.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      self.steps[voice] = newValue.int
    ),
  ])

  setDefaults()

method process(self: KArp) =
  if voices.len == 0:
    return

  var nSteps = 0
  for i in 0..voices.high:
    if steps[i] != OffNote:
      nSteps += 1

  let lastStep = step.int

  if nSteps > 0:
    var trigger = false
    step += (beatsPerSecond() * speed) * invSampleRate
    if step.int != lastStep:
      trigger = true
    step = step mod nSteps.float
    let i = step.int
    if trigger:
      if bindings[0].machine != nil:
        var k = 0
        for j in 0..voices.high:
          if steps[j] != OffNote:
            if k == i:
              var (voice, param) = bindings[0].getParameter()
              param.value = steps[j].float
              param.onchange(param.value, voice)
              break
            k += 1
  else:
    step = 0.0

method drawExtraData(self: KArp, x,y,w,h: int) =
  var yv = y
  for i in 0..voices.high:
    let note = steps[i]
    if note != OffNote:
      setColor(if step.int == i: 8 else: 7)
      print($i & ": " & noteToNoteName(note), x + 1, yv)
      yv += 8

proc newKArp(): Machine =
  var arp = new(KArp)
  arp.init()
  return arp

registerMachine("Karp", newKArp, "util")

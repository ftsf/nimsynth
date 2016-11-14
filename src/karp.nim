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

type
  KArpVoice = ref object of Voice
    note: int
  KArp = ref object of Machine
    speed: float # tpb
    mode: KArpMode

    step: float

method addVoice*(self: KArp) =
  pauseAudio(1)
  var voice = new(KArpVoice)
  voices.add(voice)
  voice.init(self)
  pauseAudio(0)

method init(self: KArp) =
  procCall init(Machine(self))

  nInputs = 0
  nOutputs = 0
  nBindings = 1
  bindings.setLen(1)
  name = "Karp"

  setDefaults()

  globalParams.add([
    Parameter(kind: Int, name: "mode", min: mode.low.float, max: mode.high.float, default: Up.float, onchange: proc(newValue: float, voice: int) =
      self.mode = newValue.KArpMode
    , getValueString: proc(value: float, voice: int): string =
      return $value.KArpMode
    ),
    Parameter(kind: Int, name: "speed", min: 1.0, max: 16.0, default: 4.0, onchange: proc(newValue: float, voice: int) =
      self.speed = newValue
    ),
  ])

  voiceParams.add([
    Parameter(kind: Note, name: "note", min: OffNote, max: 256.0, default: OffNote, onchange: proc(newValue: float, voice: int) =
      var voice = KArpVoice(self.voices[voice])
      voice.note = newValue.int
    ),
  ])

  setDefaults()

method process(self: KArp) =
  if voices.len == 0:
    return

  var nSteps = 0
  for i in 0..voices.high:
    if KArpVoice(voices[i]).note != OffNote:
      nSteps += 1

  let lastStep = step.int
  step += (beatsPerSecond() * speed) * invSampleRate
  step = step mod voices.len.float
  let i = step.int

  var whichVoice = 0
  var note: int = OffNote
  for j in 0..voices.high:
    if KArpVoice(voices[j]).note != OffNote:
      whichVoice += 1
      if whichVoice == i:
        note = KArpVoice(voices[j]).note
        break

  if bindings[0].machine != nil:
    if lastStep != i:
      var (voice, param) = bindings[0].getParameter()

      param.value = note.float
      param.onchange(param.value, voice)

proc newKArp(): Machine =
  var arp = new(KArp)
  arp.init()
  return arp

registerMachine("Karp", newKArp, "util")

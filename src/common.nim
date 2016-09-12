const sampleRate* = 48000.0
const invSampleRate* = 1.0/sampleRate

import sdl2
import sdl2.audio
import math
import basic2d

export sdl2

var baseOctave* = 4
var beatsPerMinute* = 128

var sampleId*: int
var sampleBuffer*: array[1024, float32]

type
  Modulator* = object of RootObj
    amplitude: float
  ParameterKind* = enum
    Float
    Int
    Note
  Parameter* = object of RootObj
    kind*: ParameterKind
    name*: string
    modulators*: seq[Modulator]
    min*,max*: float
    value*: float
    default*: float
    onchange*: proc(newValue: float, voice: int = -1)
    getValueString*: proc(value: float, voice: int = -1): string
  Input* = object of RootObj
    machine*: Machine
    output*: int
    gain*: float
  Voice* = ref object of RootObj
    parameters*: seq[Parameter]
  Machine* = ref object of RootObj
    name*: string
    pos*: Point2d
    globalParams*: seq[Parameter]
    voiceParams*: seq[Parameter]
    voices*: seq[Voice]
    inputs*: seq[Input]
    outputs*: seq[Machine]
    nOutputs*: int
    nInputs*: int
    cachedOutputSampleId: int
    cachedOutputSample*: float32
  View* = ref object of RootObj
    discard
  Knob* = ref object of RootObj
    pos*: Point2d
    machine*: Machine
    param*: ptr Parameter

var machines*: seq[Machine]
var knobs*: seq[Knob]

var currentView*: View
var vLayoutView*: View
var vMachineView*: View
var masterMachine*: Machine
var recordMachine*: Machine

{.this:self.}

method init*(self: Machine) {.base.} =
  globalParams = newSeq[Parameter]()
  voiceParams = newSeq[Parameter]()
  voices = newSeq[Voice]()
  inputs = newSeq[Input]()
  outputs = newSeq[Machine]()

method init*(self: Voice, machine: Machine) {.base.} =
  parameters = newSeq[Parameter]()
  for p in machine.voiceParams:
    parameters.add(p)

method rename*(self: Machine, newName: string) {.base.} =
  self.name = newName

method addVoice*(self: Machine) {.base.} =
  var voice = new(Voice)
  voice.init(self)
  self.voices.add(voice)

proc getAdjacent(self: Machine): seq[Machine] =
  result = newSeq[Machine]()
  for input in mitems(inputs):
    result.add(input.machine)

proc DFS[T](current: T, white: var seq[T], grey: var seq[T], black: var seq[T]): bool =
  grey.add(current)
  for adj in current.getAdjacent():
    if adj in black:
      continue
    if adj in grey:
      # contains cycle
      return true
    if DFS(adj, white, grey, black):
      return true
  # fully explored: move from grey to black
  grey.del(grey.find(current))
  black.add(current)
  return false

proc hasCycle[T](G: seq[T]): bool =
  var white = newSeq[T]()
  white.add(G)
  var grey = newSeq[T]()
  var black = newSeq[T]()

  while white.len > 0:
    var current = white.pop()
    if(DFS(current, white, grey, black)):
      return true
  return false

proc connectMachines*(source, dest: Machine): bool =
  # check dest accepts inputs
  if dest.nInputs == 0:
    return false
  if source.nOutputs == 0:
    return false
  # check not already connected
  if dest in source.outputs:
    return false
  # check not connected the other way
  for input in source.inputs:
    if input.machine == dest:
      return false
  # add it and test for cycle
  source.outputs.add(dest)
  dest.inputs.add(Input(machine: source, output: 0, gain: 1.0))
  if hasCycle(machines):
    # undo
    discard dest.inputs.pop()
    discard source.outputs.pop()
    return false
  return true

proc disconnectMachines*(source, dest: Machine) =
  pauseAudio(1)
  for i,input in dest.inputs:
    if input.machine == source:
      dest.inputs.del(i)
      break
  for i,output in source.outputs:
    if output == dest:
      source.outputs.del(i)
  pauseAudio(0)

proc delete*(self: Machine) =
  pauseAudio(1)
  # remove all connections and references to it
  for output in mitems(self.outputs):
    for i,input in output.inputs:
      if input.machine == self:
        output.inputs.del(i)
        break
  machines.del(machines.find(self))
  if recordMachine == self:
    recordMachine = nil
  pauseAudio(0)

var machineTypes* = newSeq[tuple[name: string, factory: proc(): Machine]]()

proc registerMachine*(name: string, factory: proc(): Machine) =
  machineTypes.add((name: name, factory: factory))

proc savePatch*(machine: Machine, name: string) =
  # TODO add patch saving code
  # save each parameter
  # as json
  discard

proc loadPatch*(machine: Machine, name: string) =
  # TODO add patch loading code
  # load each parameter value
  # from json
  discard

proc getPatches*(machine: Machine): seq[string] =
  result = newSeq[string]()
  # scan directory for json files
  # each machine gets its own directory
  # each patch has its own json file

method trigger*(self: Machine, note: int) {.base.} =
  discard

method release*(self: Machine, note: int) {.base.} =
  discard

method popVoice*(self: Machine) {.base.} =
  discard self.voices.pop()

method getParameterCount*(self: Machine): int {.base.} =
  # TODO: add support for input gain params
  return self.globalParams.len + self.voiceParams.len * self.voices.len

method getParameter*(self: Machine, paramId: int): (int, ptr Parameter) {.base.} =
  # TODO: add support for input gain params
  let voice = if paramId < globalParams.len: -1 else: (paramId - globalParams.len) div voiceParams.len
  if voice == -1:
    return (voice, addr(self.globalParams[paramId]))
  elif voice > self.voices.len:
    return (-1, nil)
  else:
    let voiceParam = (paramId - globalParams.len) mod voiceParams.len
    return (voice, addr(self.voices[voice].parameters[voiceParam]))

method process*(self: Machine): float32 {.base.} =
  return 0.0

proc outputSample*(self: Machine): float32 =
  if self.cachedOutputSampleId == sampleId:
    return self.cachedOutputSample
  else:
    self.cachedOutputSample = self.process()
    self.cachedOutputSampleId = sampleId
    return self.cachedOutputSample

method update*(self: View, dt: float) {.base.} =
  discard

method draw*(self: View) {.base.} =
  discard

method key*(self: View, key: KeyboardEventPtr, down: bool): bool {.base.} =
  return false

proc keyToNote*(key: KeyboardEventPtr): int =
  baseOctave = clamp(baseOctave, 0, 8)
  let scancode = key.keysym.scancode
  case scancode:
  of SDL_SCANCODE_Z:
    return baseOctave * 12 + 0
  of SDL_SCANCODE_S:
    return baseOctave * 12 + 1
  of SDL_SCANCODE_X:
    return baseOctave * 12 + 2
  of SDL_SCANCODE_D:
    return baseOctave * 12 + 3
  of SDL_SCANCODE_C:
    return baseOctave * 12 + 4
  of SDL_SCANCODE_V:
    return baseOctave * 12 + 5
  of SDL_SCANCODE_G:
    return baseOctave * 12 + 6
  of SDL_SCANCODE_B:
    return baseOctave * 12 + 7
  of SDL_SCANCODE_H:
    return baseOctave * 12 + 8
  of SDL_SCANCODE_N:
    return baseOctave * 12 + 9
  of SDL_SCANCODE_J:
    return baseOctave * 12 + 10
  of SDL_SCANCODE_M:
    return baseOctave * 12 + 11
  of SDL_SCANCODE_COMMA:
    return baseOctave * 12 + 12

  of SDL_SCANCODE_Q:
    return baseOctave * 12 + 12 + 0
  of SDL_SCANCODE_2:
    return baseOctave * 12 + 12 + 1
  of SDL_SCANCODE_W:
    return baseOctave * 12 + 12 + 2
  of SDL_SCANCODE_3:
    return baseOctave * 12 + 12 + 3
  of SDL_SCANCODE_E:
    return baseOctave * 12 + 12 + 4
  of SDL_SCANCODE_R:
    return baseOctave * 12 + 12 + 5
  of SDL_SCANCODE_5:
    return baseOctave * 12 + 12 + 6
  of SDL_SCANCODE_T:
    return baseOctave * 12 + 12 + 7
  of SDL_SCANCODE_6:
    return baseOctave * 12 + 12 + 8
  of SDL_SCANCODE_Y:
    return baseOctave * 12 + 12 + 9
  of SDL_SCANCODE_7:
    return baseOctave * 12 + 12 + 10
  of SDL_SCANCODE_U:
    return baseOctave * 12 + 12 + 11
  of SDL_SCANCODE_I:
    return baseOctave * 12 + 12 + 12
  of SDL_SCANCODE_1:
    # off note
    return -2
  of SDL_SCANCODE_PERIOD:
    # blank
    return -1
  else:
    return -3

proc noteToHz*(note: float): float =
  return pow(2.0,((note - 69.0) / 12.0)) * 440.0

proc hzToNote*(hz: float): int =
  return (12.0 * log2(hz / 440.0) + 69.0).int

proc noteToNoteName*(note: int): string =
  let oct = note div 12 - 1
  case note mod 12:
  of 0:
    return "C-" & $oct
  of 1:
    return "C#" & $oct
  of 2:
    return "D-" & $oct
  of 3:
    return "D#" & $oct
  of 4:
    return "E-" & $oct
  of 5:
    return "F-" & $oct
  of 6:
    return "F#" & $oct
  of 7:
    return "G-" & $oct
  of 8:
    return "G#" & $oct
  of 9:
    return "A-" & $oct
  of 10:
    return "A#" & $oct
  of 11:
    return "B-" & $oct
  of -2:
    return "OFF"
  else:
    return "???"

proc hzToNoteName*(hz: float): string =
  return noteToNoteName(hzToNote(hz))

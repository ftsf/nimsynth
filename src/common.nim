const sampleRate* = 48000.0
const invSampleRate* = 1.0/sampleRate

import sdl2
import sdl2.audio
import math
import basic2d

export sdl2

export pauseAudio

var baseOctave* = 4
var beatsPerMinute* = 128

var sampleId*: int
var sampleBuffer*: array[1024, float32]

type
  # used for connecting a machine to another machine's parameter
  Binding* = tuple[machine: Machine, param: int]
  ParameterKind* = enum
    Float
    Int
    Note
    Trigger
  Parameter* = object of RootObj
    kind*: ParameterKind
    name*: string
    min*,max*: float
    value*: float
    default*: float
    onchange*: proc(newValue: float, voice: int = -1)
    getValueString*: proc(value: float, voice: int = -1): string
  Input* = object of RootObj
    machine*: Machine
    output*: int  # which output to read
    gain*: float
  Voice* = ref object of RootObj
    parameters*: seq[Parameter]
  Machine* = ref object of RootObj
    name*: string
    className*: string
    pos*: Point2d
    globalParams*: seq[Parameter]
    voiceParams*: seq[Parameter]
    voices*: seq[Voice]
    inputs*: seq[Input]
    outputs*: seq[Machine]
    nOutputs*: int
    nInputs*: int
    bindings*: seq[Binding]
    nBindings*: int
    stereo*: bool
    outputSampleId*: int  # updated externally each sample, maybe this could be a global
    outputSamples*: seq[float32]
  View* = ref object of RootObj
    discard
  Knob* = ref object of RootObj
    pos*: Point2d
    machine*: Machine
    paramId*: int

var machines*: seq[Machine]
var knobs*: seq[Knob]

var currentView*: View
var vLayoutView*: View
var masterMachine*: Machine
var recordMachine*: Machine

{.this:self.}

method init*(self: Machine) {.base.} =
  globalParams = newSeq[Parameter]()
  voiceParams = newSeq[Parameter]()
  voices = newSeq[Voice]()
  inputs = newSeq[Input]()
  outputs = newSeq[Machine]()
  bindings = newSeq[Binding]()
  outputSamples = newSeq[float32]()

method init*(self: Voice, machine: Machine) {.base.} =
  parameters = newSeq[Parameter]()
  for p in machine.voiceParams:
    parameters.add(p)

method rename*(self: Machine, newName: string) {.base.} =
  self.name = newName

method addVoice*(self: Machine) {.base.} =
  pauseAudio(1)
  var voice = new(Voice)
  voice.init(self)
  self.voices.add(voice)
  pauseAudio(0)

method setDefaults*(self: Machine) {.base.} =
  for param in mitems(self.globalParams):
    param.value = param.default
    param.onchange(param.value, -1)

  outputSamples.setLen(nOutputs)

method createBinding*(self: Machine, slot: int, target: Machine, paramId: int) {.base.} =
  assert(target != nil)
  bindings[slot].machine = target
  bindings[slot].param = paramId

method removeBinding*(self: Machine, slot: int) {.base.} =
  bindings[slot].machine = nil
  bindings[slot].param = 0

method handleClick*(self: Machine, mouse: Point2d): bool {.base.} =
  return false

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

  # remove all bindings to this machine
  for machine in mitems(machines):
    if machine != self:
      if machine.bindings != nil:
        for i, binding in mpairs(machine.bindings):
          if binding.machine == self:
            removeBinding(machine, i)
  pauseAudio(0)

var machineTypes* = newSeq[tuple[name: string, factory: proc(): Machine]]()

proc registerMachine*(name: string, factory: proc(): Machine) =
  machineTypes.add((name: name, factory: proc(): Machine =
    var m = factory()
    m.className = name
    return m
  ))

proc getSample*(self: Input): float32 =
  if machine.outputSamples.len < output:
    raise newException(Exception, "machine not initialised properly: " & machine.name)
  return machine.outputSamples[output] * gain

method getParameterCount*(self: Machine): int {.base.} =
  # TODO: add support for input gain params
  return self.globalParams.len + self.voiceParams.len * self.voices.len

method getParameter*(self: Machine, paramId: int): (int, ptr Parameter) {.base.} =
  let voice = if paramId <= globalParams.high: -1 else: (paramId - globalParams.len) div voiceParams.len
  if voice == -1:
    return (voice, addr(self.globalParams[paramId]))
  elif voice > self.voices.high or voice < -1:
    return (-1, nil)
  else:
    let voiceParam = (paramId - globalParams.len) mod voiceParams.len
    return (voice, addr(self.voices[voice].parameters[voiceParam]))

method trigger*(self: Machine, note: int) {.base.} =
  for i in 0..getParameterCount()-1:
    var (voice,param) = getParameter(i)
    if param.kind == Note:
      param.value = note.float
      param.onchange(param.value, voice)
      break

method release*(self: Machine, note: int) {.base.} =
  discard

type
  ParamMarshal = object of RootObj
    name: string
    voice: int
    value: float
  PatchMarshal = object of RootObj
    name: string
    parameters: seq[ParamMarshal]
    extraData: string
  BindMarshal = object of RootObj
    targetMachineId: int
    paramId: int
  InputMarshal = object of RootObj
    targetMachineId: int
    outputId: int
    gain: float
  MachineMarshal = object of RootObj
    name: string
    className: string # needs to match the name used to create it
    pos: Point2d
    parameters: seq[ParamMarshal]
    bindings: seq[BindMarshal]
    inputs: seq[InputMarshal]
    voices: int
    extraData: string
  LayoutMarhsal = object of RootObj
    name: string
    machines: seq[MachineMarshal]

import marshal
import streams
import os

method saveExtraData*(self: Machine): string {.base.} =
  return nil

method loadExtraData*(self: Machine, data: string) {.base.} =
  discard

proc getMarshaledParams(self: Machine): seq[ParamMarshal] =
  result = newSeq[ParamMarshal]()
  for i in 0..getParameterCount()-1:
    var (voice, param) = getParameter(i)
    var pp: ParamMarshal
    pp.name = param.name
    pp.voice = voice
    pp.value = param.value
    result.add(pp)

proc getMarshaledBindings(self: Machine): seq[BindMarshal] =
  result = newSeq[BindMarshal]()
  if bindings != nil:
    for i in 0..nBindings-1:
      var bm: BindMarshal
      var binding = bindings[i]
      if binding.machine != nil:
        bm.targetMachineId = machines.find(binding.machine)
        bm.paramId = binding.param
        result.add(bm)
      else:
        bm.targetMachineId = -1
        bm.paramId = -1
        result.add(bm)

proc getMarshaledInputs(self: Machine): seq[InputMarshal] =
  result = newSeq[InputMarshal]()
  for i in 0..inputs.high:
    var im: InputMarshal
    var input = inputs[i]
    im.targetMachineId = machines.find(input.machine)
    im.outputId = input.output
    im.gain = input.gain
    result.add(im)

proc savePatch*(machine: Machine, name: string) =
  var p: PatchMarshal
  p.name = name
  p.parameters = machine.getMarshaledParams()
  p.extraData = machine.saveExtraData()

  createDir("patches")
  createDir("patches/" & machine.name)

  var fp = newFileStream("patches/" & machine.name & "/" & name & ".json", fmWrite)
  if fp == nil:
    echo "error opening file for saving"
    return
  fp.write($$p)
  fp.close()

proc loadMarshaledParams(self: Machine, parameters: seq[ParamMarshal], setDefaults = false) =
  var nRealParams = getParameterCount()
  for i,p in parameters:
    while i > nRealParams-1:
      self.addVoice()
      nRealParams = getParameterCount()
    var (voice,param) = getParameter(i)
    if param.name == p.name:
      param.value = p.value
      if setDefaults:
        param.default = p.value
      if param.kind == Note or param.kind == Trigger:
        continue
      param.onchange(param.value, voice)
    else:
      echo "parameter name does not match: " & param.name & " vs " & p.name

proc loadMarshaledBindings(self: Machine, bindings: seq[BindMarshal]) =
  for i,binding in bindings:
    self.bindings[i].machine = if binding.targetMachineId != -1: machines[binding.targetMachineId] else: nil
    self.bindings[i].param = binding.paramId

proc loadMarshaledInputs(self: Machine, inputs: seq[InputMarshal]) =
  for i,input in inputs:
    if input.targetMachineId > machines.high or input.targetMachineId < 0:
      echo "invalid targetMachineId: ", input.targetMachineId
    else:
      var ip: Input
      ip.machine = machines[input.targetMachineId]
      ip.output = input.outputId
      ip.gain = input.gain
      self.inputs.add(ip)

proc loadPatch*(machine: Machine, name: string) =
  var fp = newFileStream("patches/" & machine.name & "/" & name & ".json", fmRead)
  if fp == nil:
    echo "error opening file for reading"
    return
  var p: PatchMarshal
  fp.load(p)
  fp.close()

  machine.loadMarshaledParams(p.parameters, true)
  machine.loadExtraData(p.extraData)

proc saveLayout*(name: string) =
  var l: LayoutMarhsal
  l.name = name
  l.machines = newSeq[MachineMarshal]()
  for i, machine in machines:
    var m: MachineMarshal
    m.name = machine.name
    m.className = machine.className
    m.pos = machine.pos
    m.parameters = machine.getMarshaledParams()
    m.bindings = machine.getMarshaledBindings()
    m.inputs = machine.getMarshaledInputs()
    m.voices = machine.voices.len
    m.extraData = machine.saveExtraData()
    l.machines.add(m)

  createDir("layouts")

  var fp = newFileStream("layouts/" & name & ".json", fmWrite)
  if fp == nil:
    echo "error opening file for saving"
    return
  fp.write($$l)
  fp.close()

  echo "saved layout to ", name

proc getLayouts*(): seq[string] =
  result = newSeq[string]()
  let prefix = "layouts/"
  for file in walkFiles("layouts/*.json"):
    result.add(file[prefix.len..file.high-5])

proc loadLayout*(name: string) =
  var l: LayoutMarhsal
  var fp = newFileStream("layouts/" & name & ".json", fmRead)
  fp.load(l)
  fp.close()

  var machineMap = newSeq[Machine]()

  for i, machine in l.machines:
    if machine.className == "master":
      machineMap.add(masterMachine)
      masterMachine.loadMarshaledParams(machine.parameters)
      masterMachine.loadMarshaledInputs(machine.inputs)
      masterMachine.pos = machine.pos
      continue
    for mt in machineTypes:
      if mt.name == machine.className:
        var m = mt.factory()
        m.pos = machine.pos
        m.name = machine.name
        while m.voices.len < machine.voices:
          m.addVoice()
        machines.add(m)
        m.loadMarshaledParams(machine.parameters)
        machineMap.add(m)
        break
    # TODO: throw warning if couldn't find machineType

  for i, machine in l.machines:
    var m = machineMap[i]
    m.loadMarshaledBindings(machine.bindings)
    m.loadMarshaledInputs(machine.inputs)
    m.loadExtraData(machine.extraData)

  echo "loaded layout: ", name

proc getPatches*(self: Machine): seq[string] =
  result = newSeq[string]()
  let prefix = "patches/" & name
  for file in walkFiles(prefix & "*.json"):
    result.add(file[prefix.len..file.high-5])

method popVoice*(self: Machine) {.base.} =
  pauseAudio(1)
  # find anything bound to this voice
  for machine in mitems(machines):
    if machine != self:
      if machine.bindings != nil:
        for i,binding in mpairs(machine.bindings):
          if binding.machine == self:
            var (voice,param) = machine.getParameter(binding.param)
            if voice == self.voices.high:
              removeBinding(machine, i)
  discard self.voices.pop()
  pauseAudio(0)



method process*(self: Machine) {.base.} =
  discard

method update*(self: View, dt: float) {.base.} =
  discard

method draw*(self: View) {.base.} =
  discard

method drawExtraInfo*(self: Machine, x,y,w,h: int) {.base.} =
  discard

method key*(self: View, key: KeyboardEventPtr, down: bool): bool {.base.} =
  return false

const OffNote* = -2
const Blank* = -1

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
    return OffNote
  of SDL_SCANCODE_PERIOD:
    return Blank
  else:
    return -3

proc noteToHz*(note: float): float =
  return pow(2.0,((note - 69.0) / 12.0)) * 440.0

proc hzToNote*(hz: float): float =
  if hz == 0.0:
    return 0
  return (12.0 * log2(hz / 440.0) + 69.0)

proc noteToNoteName*(note: int): string =
  if note == OffNote:
    return "OFF"
  elif note == Blank:
    return "..."

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
  else:
    return "???"

proc hzToNoteName*(hz: float): string =
  return noteToNoteName(hzToNote(hz).int)

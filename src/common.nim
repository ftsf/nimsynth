import math
import math
import strutils

var sampleRate* = 48000.0
var nyquist* = sampleRate / 2.0
var invSampleRate* = 1.0/sampleRate
const middleC* = 261.625565

import nico
import nico/vec

var frame*: uint32 = 0

import core/ringbuffer

var baseOctave* = 4

var sampleId*: int

var oscilliscopeBuffer*: RingBuffer[float32]

var inputSample*: float32

var statusMessage: string = "ready to rok"
var statusUpdateTime: int = 0

var nextMachineId = 0

var layoutName*: string = "untitled"

proc setStatus*(text: string) =
  statusMessage = text
  statusUpdateTime = time().int

proc getStatus*(): string =
  return statusMessage

proc clearLayout*()

proc getStatusUpdateTime*(): int =
  return statusUpdateTime

const MidiStatusNoteOff = 0x00000000
const MidiStatusNoteOn =  0x00000001
const MidiStatusControlChange = 0x00000011

type
  InvalidParamException = object of Exception

type
  # used for connecting a machine to another machine's parameter
  Binding* = tuple[machine: Machine, param: int]
  ParameterKind* = enum
    Float # 0x0000 - 0xffff (min - max)
    Bool # 0 - 1
    Int
    Note # 8 bits
    Trigger # 0 - 1
  ParameterSequencerKind* = enum
    skAuto
    skBool
    skInt4 # 0x0 - 0xf
    skInt8 # 0x00 - 0xff
    skInt16 # 0x0000 - 0xffff (min - max)
    skNote # 0 - 0xff (off)
    skPattern
  Parameter* = object of RootObj
    kind*: ParameterKind
    seqkind*: ParameterSequencerKind
    name*: string
    min*,max*: float
    value*: float
    default*: float
    onchange*: proc(newValue: float, voice: int)
    getValueString*: proc(value: float, voice: int = -1): string
    deferred*: bool # deferred attributes get changed by a sequencer last
    separator*: bool # put a space above it
  MidiEvent* = object of RootObj
    time*: int
    channel*: range[0..15]
    command*: uint8
    data1*,data2*: uint8
  Input* = object of RootObj
    machine*: Machine
    output*: int  # which output to read
    gain*: float
    inputId*: int # for machines that have more than one input
  Voice* = ref object of RootObj
    parameters*: seq[Parameter]
  Machine* = ref object of RootObj
    id*: int
    name*: string
    className*: string
    pos*: Vec2f
    globalParams*: seq[Parameter]
    voiceParams*: seq[Parameter]
    voices*: seq[Voice]
    inputs*: seq[Input]
    nOutputs*: int
    nInputs*: int
    bindings*: seq[Binding]
    nBindings*: int
    hideBindings*: bool
    stereo*: bool
    outputSampleId*: int  # updated externally each sample, maybe this could be a global
    outputSamples*: seq[float32]
    mute*: bool
    bypass*: bool
    disabled*: bool # mute and don't call process
    useMidi*: bool
    midiChannel*: int
  View* = ref object of RootObj
    discard
  Knob* = ref object of RootObj
    pos*: Vec2f
    machine*: Machine
    paramId*: int

var machines*: seq[Machine]
var currentView*: View
var vLayoutView*: View
var masterMachine*: Machine
var sampleMachine*: Machine

var shortcuts*: array[10, Machine]

{.this:self.}

var sortingEnabled = true

proc sortMachines()

when defined(jack):
  import jack.midiport

  proc newMidiEvent*(rawEvent: JackMidiEvent): MidiEvent =
    let status = cast[ptr array[3, uint8]](rawEvent.buffer)[0]
    result.time = rawEvent.time.int
    result.channel = status.int and 0b00001111
    result.command = ((status.int shr 4) and 0b00000111)
    if rawEvent.size >= 2:
      result.data1 = cast[ptr array[3, uint8]](rawEvent.buffer)[1]
    if rawEvent.size >= 3:
      result.data2 = cast[ptr array[3, uint8]](rawEvent.buffer)[2]

method init*(self: Machine) {.base.} =
  globalParams = newSeq[Parameter]()
  voiceParams = newSeq[Parameter]()
  voices = newSeq[Voice]()
  inputs = newSeq[Input]()
  bindings = newSeq[Binding]()
  outputSamples = newSeq[float32]()

method init*(self: Voice, machine: Machine) {.base.} =
  parameters = newSeq[Parameter]()
  for p in machine.voiceParams:
    var newP = p
    parameters.add(newP)

  for p in mitems(self.parameters):
    p.value = p.default
    p.onchange(p.value, machine.voices.high)

method event*(self: Machine, event: Event, camera: Vec2f): (bool, bool) {.base.} =
  return (false, false)

method event*(self: View, event: Event): bool {.base.} =
  return false

method rename*(self: Machine, newName: string) {.base.} =
  self.name = newName

method addVoice*(self: Machine) {.base.} =
  var voice = new(Voice)
  self.voices.add(voice)
  voice.init(self)

method setDefaults*(self: Machine) {.base.} =
  for param in mitems(self.globalParams):
    param.value = param.default
    param.onchange(param.value, -1)

  outputSamples.setLen(nOutputs)

method createBinding*(self: Machine, slot: int, target: Machine, paramId: int) {.base.} =
  assert(target != nil)
  bindings[slot].machine = target
  bindings[slot].param = paramId

  sortMachines()

method removeBinding*(self: Machine, slot: int) {.base.} =
  bindings[slot].machine = nil
  bindings[slot].param = 0

  sortMachines()

method onBPMChange*(self: Machine, bpm: int) {.base.} =
  discard

method handleClick*(self: Machine, mouse: Vec2f): bool {.base.} =
  return false

proc getAdjacent(self: Machine): seq[Machine] =
  result = newSeq[Machine]()
  for input in mitems(inputs):
    result.add(input.machine)

proc getAdjacentWithBindings(self: Machine): seq[Machine] =
  result = newSeq[Machine]()
  for input in mitems(inputs):
    result.add(input.machine)

  for m in machines:
    if m != self:
      if m.nBindings > 0:
        for binding in m.bindings:
          if binding.machine == self:
            result.add(m)

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
    if DFS(current, white, grey, black):
      return true
  return false

proc findLeaves(m: Machine, machines: var seq[Machine]) =

  var adj = m.getAdjacentWithBindings()

  for a in adj:
    a.findLeaves(machines)

  if not (m in machines):
    machines.add(m)

proc sortMachines() =
  if not sortingEnabled:
    return

  # sort by depth from master
  var newMachines = newSeq[Machine]()

  masterMachine.findLeaves(newMachines)

  # add any detached machines at the end
  for machine in mitems(machines):
    if not (machine in newMachines):
      newMachines.add(machine)

  machines = newMachines

proc connectMachines*(source, dest: Machine, gain: float = 1.0, inputId: int = 0, outputId: int = 0): bool =
  echo "connecting: ", source.name, ": ", outputId, " -> ", dest.name, ": ", inputId
  # check dest accepts inputs
  if dest.nInputs == 0:
    echo dest.name, " does not have any inputs"
    return false
  if source.nOutputs == 0:
    echo source.name, " does not have any outputs"
    return false
  # check not already connected
  for input in dest.inputs:
    if input.machine == source:
      echo source.name, " is already connected to ", dest.name
      return false
  # check not connected the other way
  for input in source.inputs:
    if input.machine == dest:
      echo source.name, " is already connected to ", dest.name, " the other way"
      return false
  # add it and test for cycle
  dest.inputs.add(Input(machine: source, output: outputId, gain: gain, inputId: inputId))
  if hasCycle(machines):
    # undo
    discard dest.inputs.pop()
    echo "would create a cycle"
    return false

  sortMachines()
  return true

proc disconnectMachines*(source, dest: Machine) =
  for i,input in dest.inputs:
    if input.machine == source:
      dest.inputs.del(i)
      break
  sortMachines()

proc swapMachines*(a,b: Machine) =
  # check they are compatible
  if a == masterMachine or b == masterMachine:
    return
  if a.nOutputs == b.nOutputs and a.nInputs == b.nInputs:
    swap(a.pos, b.pos)
    swap(a.inputs, b.inputs)
    var aOutputs = newSeq[tuple[machine: Machine, input: ptr Input]]()
    var bOutputs = newSeq[tuple[machine: Machine, input: ptr Input]]()
    for machine in mitems(machines):
      for input in mitems(machine.inputs):
        if input.machine == a:
          aOutputs.add((machine,addr(input)))
        if input.machine == b:
          bOutputs.add((machine,addr(input)))

    for v in aOutputs:
      v.input.machine = b
    for v in bOutputs:
      v.input.machine = a
    sortMachines()

proc delete*(self: Machine) =
  # remove all connections and references to it
  for machine in mitems(machines):
    if machine != self:
      for i,input in machine.inputs:
        if input.machine == self:
          disconnectMachines(self, machine)
  # remove all bindings to this machine
  for machine in mitems(machines):
    if machine != self:
      for i, binding in mpairs(machine.bindings):
        if binding.machine == self:
          removeBinding(machine, i)
  for i,shortcut in mpairs(shortcuts):
    if shortcut == self:
      shortcuts[i] = nil

  machines.del(machines.find(self))

  if sampleMachine == self:
    sampleMachine = masterMachine

  sortMachines()

type MachineType* = tuple[name: string, factory: proc(): Machine]

var machineTypes* = newSeq[MachineType]()

import tables

type MachineCategory = Table[string, seq[MachineType]]

var machineTypesByCategory* = initOrderedTable[string, seq[MachineType]]()

proc clearLayout*() =
  # removes all machines and resets thing to init
  machines = newSeq[Machine]()
  nextMachineId = 0
  baseOctave = 4
  sampleId = 0
  oscilliscopeBuffer = newRingBuffer[float32](1024)
  statusMessage = "ready to rok"
  statusUpdateTime = 0
  currentView = vLayoutView
  for i in 0..shortcuts.high:
    shortcuts[i] = nil

proc registerMachine*(name: string, factory: proc(): Machine, category: string = "") =

  var mCreator = proc(): Machine =
    var m = factory()
    m.id = nextMachineId
    nextMachineId += 1
    m.className = name
    return m

  machineTypes.add((name: name, factory: mCreator))

  if category != "":
    if not machineTypesByCategory.hasKey(category):
      machineTypesByCategory.add(category, newSeq[MachineType]())
    machineTypesByCategory[category].add((name: name, factory: mCreator))

proc createMachine*(name: string): Machine =
  for mt in machineTypes:
    if mt.name == name:
      result = mt.factory()
  if result == nil:
    raise newException(Exception, "no machine type named: " & name)

proc newLayout*() =
  clearLayout()
  masterMachine = createMachine("master")
  machines.add(masterMachine)
  sampleMachine = masterMachine

proc getInput*(self: Machine, inputId: int = 0): float32

proc getSample*(self: Input): float32 =
  if machine.mute:
    return 0.0
  elif machine.bypass:
    return machine.getInput() * gain
  return machine.outputSamples[output] * gain

proc getInput*(self: Machine, inputId: int = 0): float32 =
  for input in inputs:
    if input.inputId == inputId:
      result += input.getSample()

proc hasInput*(self: Machine, inputId: int = 0): bool =
  for input in inputs:
    if input.inputId == inputId:
      return true
  return false

method reset*(self: Machine) {.base.} =
  discard

method getOutputName*(self: Machine, outputId: int = 0): string {.base.} =
  if stereo:
    return "stereo"
  else:
    return "mono"

method getInputName*(self: Machine, inputId: int = 0): string {.base.} =
  return "main"

method getParameterCount*(self: Machine): int {.base.} =
  # TODO: add support for input gain params
  return self.globalParams.len + (self.voiceParams.len * self.voices.len)

method getParameter*(self: Machine, paramId: int): (int, ptr Parameter) {.base.} =

  if paramId > globalParams.len + (voiceParams.len * voices.len):
    raise newException(InvalidParamException, "invalid ParamId: " & $paramId & ". " & self.name & " only has " & $getParameterCount() & " params.")

  let voice = if paramId <= globalParams.high: -1 else: (paramId - globalParams.len) div voiceParams.len

  if voice == -1:
    return (voice, addr(self.globalParams[paramId]))
  elif voice > self.voices.high or voice < -1:
    return (-1, nil)
  else:
    let voiceParam = (paramId - globalParams.len) mod voiceParams.len
    return (voice, addr(self.voices[voice].parameters[voiceParam]))

proc isBound*(self: Binding): bool =
  return (self.machine != nil)

proc getParameter*(self: Binding): (int, ptr Parameter) =
  if self.machine != nil:
    return self.machine.getParameter(self.param)
  else:
    return (-1, nil)

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
    slotId: int
    targetMachineId: int
    targetMachineName: string
    paramId: int
    paramName: string
    paramVoice: int
  InputMarshal = object of RootObj
    targetMachineId: int
    outputId: int
    gain: float
    inputId: int
  MachineMarshal = object of RootObj
    id: int
    name: string
    className: string # needs to match the name used to create it
    pos: Vec2f
    parameters: seq[ParamMarshal]
    bindings: seq[BindMarshal]
    hideBindings: bool
    inputs: seq[InputMarshal]
    voices: int
    extraData: string
  LayoutMarhsal = object of RootObj
    name: string
    machines: seq[MachineMarshal]
    shortcuts: array[10,int]

import marshal
import streams
import os

method saveExtraData*(self: Machine): string {.base.} =
  return ""

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
  for i in 0..nBindings-1:
    var bm: BindMarshal
    var binding = bindings[i]
    if binding.machine != nil:
      bm.slotId = i
      bm.targetMachineId = binding.machine.id
      bm.targetMachineName = binding.machine.name
      var (voice,param) = binding.getParameter()
      bm.paramId = binding.param
      bm.paramName = param.name
      bm.paramVoice = voice
      result.add(bm)
    else:
      bm.slotId = i
      bm.targetMachineId = -1
      bm.paramId = -1
      bm.paramVoice = -1
      result.add(bm)

proc getMarshaledInputs(self: Machine): seq[InputMarshal] =
  result = newSeq[InputMarshal]()
  for i in 0..inputs.high:
    var im: InputMarshal
    var input = inputs[i]
    im.targetMachineId = input.machine.id
    im.outputId = input.output
    im.gain = input.gain
    im.inputId = input.inputId
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

proc getMachineById(machineId: int): Machine =
  for m in machines:
    if m.id == machineId:
      result = m
      break
  if result == nil:
    raise newException(Exception, "no machine with id: " & $machineId)

proc loadMarshaledBindings(self: Machine, bindings: seq[BindMarshal]) =
  for i,binding in bindings:
    if binding.targetMachineId != -1:
      echo "binding ", self.name, " to ", binding.targetMachineName, ": ", binding.paramName
      try:
        self.createBinding(i, getMachineById(binding.targetMachineId), binding.paramId)
      except InvalidParamException:
        echo "failed binding: ", binding.targetMachineName, ": ", binding.paramName
        discard

proc loadMarshaledInputs(self: Machine, inputs: seq[InputMarshal]) =
  for i,input in inputs:
    var ip: Input
    ip.machine = getMachineById(input.targetMachineId)
    ip.output = input.outputId
    ip.gain = input.gain
    ip.inputId = input.inputId
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
  sortMachines()
  var l: LayoutMarhsal
  l.name = name
  l.machines = newSeq[MachineMarshal]()
  l.shortcuts = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]
  for i, machine in machines:
    var m: MachineMarshal
    m.id = machine.id
    m.name = machine.name
    m.className = machine.className
    m.pos = machine.pos
    m.parameters = machine.getMarshaledParams()
    m.bindings = machine.getMarshaledBindings()
    m.hideBindings = machine.hideBindings
    m.inputs = machine.getMarshaledInputs()
    m.voices = machine.voices.len
    m.extraData = machine.saveExtraData()
    l.machines.add(m)
    let j = shortcuts.find(machine)
    if j != -1:
      l.shortcuts[j] = i

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
  clearLayout()
  sortingEnabled = false
  var l: LayoutMarhsal
  l.shortcuts = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]
  var fp = newFileStream("layouts/" & name & ".json", fmRead)
  fp.load(l)
  fp.close()

  # first clear out layout
  var machineMap = newSeq[Machine]()

  var highestId = 0

  for i, machine in l.machines:
    var m = createMachine(machine.className)
    m.id = machine.id
    if m.id > highestId:
      highestId = m.id
    m.pos = machine.pos
    m.name = machine.name
    m.hideBindings = machine.hideBindings
    while m.voices.len < machine.voices:
      m.addVoice()
    machines.add(m)
    m.loadMarshaledParams(machine.parameters)
    machineMap.add(m)
    echo "loaded machine: ", m.id, ": ", m.name

  echo "loaded machines, binding them"
  for i, machine in l.machines:
    var m = machineMap[i]
    m.loadMarshaledBindings(machine.bindings)
    m.loadMarshaledInputs(machine.inputs)
    m.loadExtraData(machine.extraData)

  for i, shortcut in l.shortcuts:
    if shortcut != -1:
      shortcuts[i] = machines[shortcut]

  sortingEnabled = true
  sortMachines()

  nextMachineId = highestId + 1
  sampleMachine = masterMachine
  layoutName = name

  echo "loaded layout: ", name

proc getPatches*(self: Machine): seq[string] =
  result = newSeq[string]()
  let prefix = "patches/" & name & "/"
  for file in walkFiles(prefix & "*.json"):
    result.add(file[prefix.len..file.high-5])

method popVoice*(self: Machine) {.base.} =
  # find anything bound to this voice
  if self.voices.len > 0:
    for machine in mitems(machines):
      for i,binding in mpairs(machine.bindings):
        if binding.machine == self:
          echo machine.name & " is bound to " & self.name & ":" & $binding.param
          var (voice,param) = self.getParameter(binding.param)
          if voice == self.voices.high:
            echo "voice matches: " & $voice
            removeBinding(machine, i)
    discard self.voices.pop()

method process*(self: Machine) {.base.} =
  discard

method midiEvent*(self: Machine, event: MidiEvent) {.base.} =
  discard

method update*(self: View, dt: float) {.base.} =
  discard

method draw*(self: View) {.base.} =
  discard

method drawExtraData*(self: Machine, x,y,w,h: int) {.base.} =
  discard

method updateExtraData*(self: Machine, x,y,w,h: int) {.base.} =
  discard

const OffNote* = -2
const Blank* = -1

proc keyToNote*(key: Keycode): int =
  baseOctave = clamp(baseOctave, 0, 8)
  case key:
  of K_Z:
    return baseOctave * 12 + 0
  of K_S:
    return baseOctave * 12 + 1
  of K_X:
    return baseOctave * 12 + 2
  of K_D:
    return baseOctave * 12 + 3
  of K_C:
    return baseOctave * 12 + 4
  of K_V:
    return baseOctave * 12 + 5
  of K_G:
    return baseOctave * 12 + 6
  of K_B:
    return baseOctave * 12 + 7
  of K_H:
    return baseOctave * 12 + 8
  of K_N:
    return baseOctave * 12 + 9
  of K_J:
    return baseOctave * 12 + 10
  of K_M:
    return baseOctave * 12 + 11
  of K_COMMA:
    return baseOctave * 12 + 12

  of K_Q:
    return baseOctave * 12 + 12 + 0
  of K_2:
    return baseOctave * 12 + 12 + 1
  of K_W:
    return baseOctave * 12 + 12 + 2
  of K_3:
    return baseOctave * 12 + 12 + 3
  of K_E:
    return baseOctave * 12 + 12 + 4
  of K_R:
    return baseOctave * 12 + 12 + 5
  of K_5:
    return baseOctave * 12 + 12 + 6
  of K_T:
    return baseOctave * 12 + 12 + 7
  of K_6:
    return baseOctave * 12 + 12 + 8
  of K_Y:
    return baseOctave * 12 + 12 + 9
  of K_7:
    return baseOctave * 12 + 12 + 10
  of K_U:
    return baseOctave * 12 + 12 + 11
  of K_I:
    return baseOctave * 12 + 12 + 12
  of K_1:
    return OffNote
  of K_PERIOD:
    return Blank
  else:
    return -3

proc noteToHz*(note: float): float =
  return pow(2.0,((note - 69.0) / 12.0)) * 440.0

proc hzToSampleRateFraction*(hz: float): float =
  return hz / sampleRate

proc sampleRateFractionToHz*(srf: float): float =
  return sampleRate * srf

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

proc dbToLinear*(db: float): float =
  if db == 0.0:
    return 1.0
  else:
    return pow(10.0, db / 20.0)

proc linearToDb*(linear: float): float =
  if linear == 0:
    return -Inf
  return 10.0 * log10(linear)

proc valueString*(self: Parameter, value: float): string =
  if self.getValueString != nil:
    return self.getValueString(value, -1)
  else:
    case kind:
    of Note:
      return noteToNoteName(value.int)
    of Trigger:
      return (if value.int == 1: "x" else: "0")
    of Int:
      return $value.int
    of Bool:
      return (if value.bool: "on" else: "off")
    of Float:
      return value.formatFloat(ffDecimal, 4)

proc ctrl*(): bool =
  when defined(osx):
    return key(K_LGUI)
  else:
    return key(K_LCTRL)

proc shift*(): bool =
  return key(K_LSHIFT)

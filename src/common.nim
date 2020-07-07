import math
import strutils
import tables
import sequtils

var sampleRate* = 48000.0
var nyquist* = sampleRate / 2.0
var invSampleRate* = 1.0/sampleRate
const middleC* = 261.625565

import nico
import nico/vec

export vec

var frame*: uint32 = 0

var oscilliscopeBufferSize*: int = 1024
var oscilliscopeFreeze*: bool

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
  BindingKind* = enum
    bkAny = "Any"
    bkNote = "Note"
    bkInt = "Int"
    bkFloat = "Float"
    bkTrigger = "Trigger"
  Binding* = tuple[machine: Machine, param: int, kind: BindingKind]
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
  Parameter* = object
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
    ignoreSave*: bool # value wont be saved to file
    fav*: bool

  MidiEvent* = object
    time*: int
    channel*: range[0..15]
    command*: uint8
    data1*,data2*: uint8
  Input* = object
    machine*: Machine
    output*: int  # which of the input machine's output slots to read
    gain*: float
    inputId*: int # for machines that have more than one input
    peak*: float
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
    outputtingToMachines*: seq[tuple[machine: Machine, count: int]]
    nOutputs*: int
    nInputs*: int
    bindings*: seq[Binding]
    nBindings*: int
    hideBindings*: bool
    stereo*: bool
    outputSampleId*: int  # updated externally each sample, maybe this could be a global
    outputSamples*: seq[float32]
    bypass*: bool
    disabled*: bool # mute and don't call process
    useMidi*: bool
    useKeyboard*: bool
    midiChannel*: int
    currentParam*: int
    scroll*: int

  View* = ref object of RootObj
    windows*: seq[Window]
    dragWindow*: Window
    resizeWindow*: Window
    resizeStart*: Vec2f
    resizeStartSize*: Vec2f
    camera*: Vec2f

  Window* = ref object of RootObj
    view*: View
    pos*: Vec2f
    w*,h*: int
    title*: string
    resize*: bool
    shade*: bool
    close*: bool
    pin*: bool

proc sendToTop*(self: Window) =
  let i = self.view.windows.find(self)
  if i >= 0:
    swap(self.view.windows[self.view.windows.high], self.view.windows[i])

proc close*(self: Window) =
  self.close = true

method eventContents*(self: Window, x,y,w,h: int, e: Event): bool {.base.} =
  discard

method event*(self: Window, e: Event): bool {.base.} =
  let pos = self.pos + self.view.camera
  let x = pos.x.int
  let y = pos.y.int
  let w = self.w
  let h = self.h

  if not self.shade:
    if self.eventContents(x+2,y+10,w-4,h-14,e):
      return true

  case e.kind:
  of ekMouseButtonDown:
    if e.x >= x and e.x <= x + w and e.y >= y and e.y <= y + h:
      if e.button == 1:
        # check if on topbar
        if e.y < y + 9:
          if e.x > x + w - 8:
            self.close = true
            return true
          elif e.clicks == 2:
            self.shade = not self.shade
          self.sendToTop()
          self.view.dragWindow = self
        elif not self.shade and e.y > y + h - 4:
          self.view.resizeWindow = self
          self.view.resizeStart = vec2f(e.x, e.y)
          self.view.resizeStartSize = vec2f(w, h)
        return true
  of ekMouseMotion:
    if self.view.dragWindow == self:
      self.pos += vec2f(e.xrel, e.yrel)
    elif self.view.resizeWindow == self:
      self.w = self.view.resizeStartSize.x.int + (e.x - self.view.resizeStart.x.int)
      self.h = self.view.resizeStartSize.y.int + (e.y - self.view.resizeStart.y.int)
      if self.w < 32:
        self.w = 32
      if self.h < 32:
        self.h = 32
  of ekMouseButtonUp:
    if e.button == 1:
      if self.view.dragWindow == self:
        self.view.dragWindow = nil
      if self.view.resizeWindow == self:
        self.view.resizeWindow = nil
  else:
    discard
  return false

method drawContents*(self: Window, x,y,w,h: int) {.base.} =
  discard

method draw*(self: Window) {.base.} =
  let x = self.pos.x.int
  let y = self.pos.y.int
  let w = self.w
  let h = if self.shade: 9 else: self.h
  setColor(1)
  rrectfill(x,y,x+w-1,y+h-1)
  setColor(5)

  if not self.shade:
    hline(x,y+8,x+w-1)
    hline(x,y+h-4,x+w-1)

  setColor(5)
  rrect(x,y,x+w-1,y+h-1)

  setColor(6)
  print(self.title, x + 2, y + 2)
  print("X", x + w - 8, y + 2)

  if not self.shade:
    self.drawContents(x+2,y+10,w-4,h-14)

var machines*: seq[Machine]
var machinesById*: Table[int,Machine]

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

else:
  proc newMidiEvent*(timestamp: float, rawEvent: pointer, size: int): MidiEvent =
    let status = cast[ptr array[3, uint8]](rawEvent)[0]
    result.time = timestamp.int
    result.channel = status.int and 0b00001111
    result.command = ((status.int shr 4) and 0b00000111).uint8
    if size >= 2:
      result.data1 = cast[ptr array[3, uint8]](rawEvent)[1]
    if size >= 3:
      result.data2 = cast[ptr array[3, uint8]](rawEvent)[2]

method init*(self: Machine) {.base.} =
  globalParams = newSeq[Parameter]()
  voiceParams = newSeq[Parameter]()
  voices = newSeq[Voice]()
  inputs = newSeq[Input]()
  bindings = newSeq[Binding]()
  outputSamples = newSeq[float32]()

method cleanup*(self: Machine) {.base.} =
  discard

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
  for i,param in mpairs(self.globalParams):
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

proc findLeaves(m: Machine, machines: seq[Machine], newMachines: var seq[Machine]) =

  var adj = m.getAdjacentWithBindings()

  for a in adj:
    a.findLeaves(machines, newMachines)

  if m notin newMachines:
    if m in machines:
      newMachines.add(m)

proc sortMachines() =
  if not sortingEnabled:
    return

  # sort by depth from master
  var newMachines = newSeq[Machine]()

  masterMachine.findLeaves(machines, newMachines)

  # add any detached machines at the end
  for machine in mitems(machines):
    if not (machine in newMachines):
      newMachines.add(machine)

  machines = newMachines

proc connectMachines*(source, dest: Machine, gain: float = 1.0, inputId: int = 0, outputId: int = 0): bool =
  #echo "connecting: ", source.name, ": ", outputId, " -> ", dest.name, ": ", inputId
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

  var alreadyConnected = false
  for v in source.outputtingToMachines.mitems:
    if v.machine == dest:
      alreadyConnected = true
      v.count += 1
      #echo "incrementing output"
      break
  if alreadyConnected == false:
    source.outputtingToMachines.add((machine: dest, count: 1))

  sortMachines()
  return true

proc disconnectMachines*(source, dest: Machine) =
  for i,input in dest.inputs:
    if input.machine == source:
      dest.inputs.del(i)
      break
  for i,v in source.outputtingToMachines:
    if v.machine == dest:
      source.outputtingToMachines[i].count -= 1
      if source.outputtingToMachines[i].count <= 0:
        source.outputtingToMachines.del(i)
      break

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
  echo "delete machine ", self.name

  # remove any connections from this machine
  for v in outputtingToMachines:
    echo "outputting to ", v.machine.name
    v.machine.inputs.keepItIf(it.machine != self)

  # remove any connections to this machine
  for input in self.inputs:
    input.machine.outputtingToMachines.keepItIf(it.machine != self)

  # remove all bindings to this machine
  for machine in machines:
    if machine != self:
      for i, binding in mpairs(machine.bindings):
        if binding.machine == self:
          removeBinding(machine, i)

  for i,shortcut in mpairs(shortcuts):
    if shortcut == self:
      shortcuts[i] = nil

  let i = machines.find(self)

  self.cleanup()

  machines.del(i)
  machinesById.del(self.id)

  if sampleMachine == self:
    sampleMachine = masterMachine

  sortMachines()

proc remove*(self: Machine) =
  # like delete, but first attach all our inputs to our outputs
  # TODO: implement
  self.delete()

type MachineType* = tuple[name: string, factory: proc(): Machine]

var machineTypes* = newSeq[MachineType]()

import tables

type MachineCategory = Table[string, seq[MachineType]]

var machineTypesByCategory* = initOrderedTable[string, seq[MachineType]]()

proc clearLayout*() =
  # removes all machines and resets thing to init
  machines = newSeq[Machine]()
  machinesById = initTable[int,Machine]()
  nextMachineId = 0
  baseOctave = 4
  sampleId = 0
  oscilliscopeBuffer = newRingBuffer[float32](oscilliscopeBufferSize)
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

proc createMachine*(name: string, id = -1): Machine =
  for mt in machineTypes:
    if mt.name == name:
      result = mt.factory()
      if id == -1:
        result.id = nextMachineId
        nextMachineId += 1
      else:
        result.id = id
        nextMachineId = max(nextMachineId, result.id + 1)
      machinesById[result.id] = result
  if result == nil:
    raise newException(Exception, "no machine type named: " & name)

proc newLayout*() =
  clearLayout()
  masterMachine = createMachine("master")

  machinesById[masterMachine.id] = masterMachine
  machines.add(masterMachine)

  sampleMachine = masterMachine

proc getInput*(self: Machine, inputId: int = 0): float32

proc getSample*(self: Input): float32 =
  if machine.disabled:
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

method getParameterCount*(self: Machine, favOnly: bool = false): int {.base.} =
  result = 0
  for p in self.globalParams:
    if p.fav or not favOnly:
      result += 1
  for p in self.voiceParams:
    if p.fav or not favOnly:
      result += self.voices.len

iterator parameters*(self: Machine, favOnly: bool = false): (int, ptr Parameter) =
  for p in mitems(self.globalParams):
    if p.fav or not favOnly:
      yield (-1, p.addr)

  for v in 0..<self.voices.len:
    for p in mitems(self.voices[v].parameters):
      if p.fav or not favOnly:
        yield (v, p.addr)

method getParameter*(self: Machine, paramId: int, favOnly: bool = false): (int, ptr Parameter) {.base.} =
  var i = 0
  for p in mitems(self.globalParams):
    if p.fav or not favOnly:
      if i == paramId:
        return (-1,p.addr)
      i += 1

  for v in 0..<self.voices.len:
    for p in mitems(self.voices[v].parameters):
      if p.fav or not favOnly:
        if i == paramId:
          return (v,p.addr)
        i += 1

  raise newException(InvalidParamException, "invalid ParamId: " & $paramId & ". " & self.name & " only has " & $getParameterCount() & " params.")

proc getParameterByName*(self: Machine, paramName: string, voice: int = -1): ptr Parameter =
  if voice == -1:
    for p in self.globalParams.mitems:
      if p.name == paramName:
        return p.addr
  else:
    if self.voices.len > voice:
      for p in self.voices[voice].parameters.mitems:
        if p.name == paramName:
          return p.addr
  echo "machine ", self.name, " has no parameter ", paramName, " on voice: ", voice
  return nil

proc getParameterIdByName*(self: Machine, paramName: string, voice: int = -1): int =
  var i = 0
  for p in self.globalParams.mitems:
    if voice == -1 and p.name == paramName:
      return i
    i += 1
  for vi, v in self.voices:
    for p in v.parameters.mitems:
      if voice == vi and p.name == paramName:
        return i
      i += 1
  echo "machine ", self.name, " has no parameter ", paramName, " on voice: ", voice
  return -1

proc getParameter*(self: Voice, paramId: int): ptr Parameter =
  if paramId > self.parameters.high:
    raise newException(InvalidParamException, "invalid ParamId: " & $paramId)

  return self.parameters[paramId].addr

proc isBound*(self: Binding): bool =
  return (self.machine != nil)

proc getParameter*(self: Binding): (int, ptr Parameter) =
  if self.machine != nil:
    return self.machine.getParameter(self.param)
  else:
    return (-1, nil)

type
  ParamMarshal = object
    name: string
    voice: int
    value: float
    fav: bool
  PatchMarshal = object
    name: string
    className: string
    parameters: seq[ParamMarshal]
    extraData: string
  BindMarshal = object
    slotId: int
    targetMachineId: int
    targetMachineName: string
    paramId: int
    paramName: string
    paramVoice: int
  InputMarshal = object
    targetMachineId: int
    outputId: int
    gain: float
    inputId: int
  MachineMarshal = object
    id: int
    name: string
    className: string # needs to match the name used to create it
    pos: Vec2f
    parameters: seq[ParamMarshal]
    disabled: bool
    bindings: seq[BindMarshal]
    hideBindings: bool
    inputs: seq[InputMarshal]
    voices: int
    extraData: string

  LayoutMarhsal = object
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
    if param.ignoreSave:
      continue
    var pp: ParamMarshal
    pp.name = param.name
    pp.voice = voice
    pp.value = param.value
    pp.fav = param.fav
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
  p.className = machine.className
  p.parameters = machine.getMarshaledParams()
  p.extraData = machine.saveExtraData()

  createDir("patches")
  createDir("patches/" & machine.className)

  var fp = newFileStream("patches/" & machine.className & "/" & name & ".json", fmWrite)
  if fp == nil:
    echo "error opening file for saving"
    return
  fp.write($$p)
  fp.close()

proc loadMarshaledParams(self: Machine, parameters: seq[ParamMarshal], setDefaults = false) =
  var nRealParams = getParameterCount()
  for i,p in parameters:
    var found = false
    for j in 0..<getParameterCount():
      var (voice,param) = getParameter(j)
      if p.voice == voice and p.name == param.name:
        found = true
        if param.ignoreSave:
          break
        param.value = p.value
        if setDefaults:
          param.default = p.value
        param.onchange(param.value, voice)
        param.fav = p.fav
        break
    if not found:
      debug "could not find parameter: " & p.name

proc getMachineById(machineId: int): Machine =
  return machinesById[machineId]

proc loadMarshaledBindings(self: Machine, bindings: seq[BindMarshal]) =
  for i,binding in bindings:
    if binding.targetMachineId != -1:
      echo "binding ", self.name, " to ", binding.targetMachineName, ": ", binding.paramName
      try:
        let m = getMachineById(binding.targetMachineId)
        let paramId = m.getParameterIdByName(binding.paramName, binding.paramVoice)
        if paramId != -1:
          self.createBinding(i, m, paramId)
      except InvalidParamException:
        echo "failed binding: ", binding.targetMachineName, ": ", binding.paramName
        discard

proc loadMarshaledInputs(self: Machine, inputs: seq[InputMarshal]) =
  for i,input in inputs:
    discard connectMachines(getMachineById(input.targetMachineId), self, input.gain, input.inputId, input.outputId)

proc loadPatch*(machine: Machine, name: string) =
  var fp = newFileStream("patches/" & machine.className & "/" & name & ".json", fmRead)
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
    m.disabled = machine.disabled
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
    var m = createMachine(machine.className, machine.id)
    m.pos = machine.pos
    m.name = machine.name
    m.disabled = machine.disabled
    m.hideBindings = machine.hideBindings
    while m.voices.len < machine.voices:
      m.addVoice()

    machinesById[m.id] = m
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

  sampleMachine = masterMachine
  layoutName = name

  echo "loaded layout: ", name

proc getPatches*(self: Machine): seq[string] =
  result = newSeq[string]()
  let prefix = "patches/" & self.className & "/"
  for file in walkFiles(prefix & "*.json"):
    result.add(file[prefix.len..file.high-5])

method popVoice*(self: Machine) {.base.} =
  # find anything bound to this voice
  if self.voices.len > 1:
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

method update*(self: Machine, dt: float32) {.base.} =
  discard

method midiEvent*(self: Machine, event: MidiEvent) {.base.} =
  discard

method trigger*(self: Machine, note: int) {.base.} =
  debug self.className, " does not define trigger"

method release*(self: Machine, note: int) {.base.} =
  debug self.className, " does not define release"

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
    return key(K_GUI)
  else:
    return key(K_LCTRL) or key(K_RCTRL)

proc shift*(): bool =
  return key(K_LSHIFT) or key(K_RSHIFT)

import common
import nico
import nico/vec
import util
import streams

type ParamRecorderMode = enum
  Stop
  Playback
  Recording

const nSlots = 16

type ParamRecorder = ref object of Machine
  buffers: array[nSlots,seq[float32]]
  mode: ParamRecorderMode
  rate: int
  writeHead: int
  readHead: int
  loop: bool
  slot: int
  slotNext: int
  slotLength: int
  nextSample: int

{.this:self.}

proc setMode(self: ParamRecorder, mode: ParamRecorderMode) =
  self.mode = mode
  case mode:
  of Stop:
    self.readHead = 0
    self.writeHead = 0
  of Playback:
    self.readHead = 0
    self.writeHead = 0
    self.slot = self.slotNext
    self.nextSample = 0
    if self.buffers[self.slot].len == 0:
      self.mode = Stop
  of Recording:
    self.readHead = 0
    self.writeHead = 0
    self.slot = self.slotNext
    self.nextSample = 0
    let length = (self.slotLength * sampleRate.int) div self.rate
    echo "new length: ", length
    self.buffers[self.slot].setLen(length)

  var (voice,param) = self.getParameter(2)
  param.value = self.mode.float


method init(self: ParamRecorder) =
  procCall init(Machine(self))

  nBindings = 1
  nInputs = 0
  nOutputs = 0
  bindings.setLen(1)
  name = "prec"

  self.globalParams.add([
    Parameter(name: "slot", kind: Int, min: 0.0, max: (nSlots-1).float, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.slotNext = newValue.int
    ),
    Parameter(name: "length", kind: Float, min: 0.0, max: 60.0, default: 10.0, onchange: proc(newValue: float, voice: int) =
      self.slotLength = newValue.int
    ),
    Parameter(name: "mode", kind: Int, min: 0.0, max: 2.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.setMode(newValue.int.ParamRecorderMode)
    ),
    Parameter(name: "loop", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.loop = newValue.bool
    ),
    Parameter(name: "rate", kind: Int, min: 1.0, max: 10000.0, default: 60.0, onchange: proc(newValue: float, voice: int) =
      self.rate = newValue.int
      self.nextSample = self.rate
    ),
  ])

  setDefaults()

method getAABB*(self: ParamRecorder): AABB =
  result.min.x = pos.x - 17
  result.min.y = pos.y - 6
  result.max.x = pos.x + 17
  result.max.y = pos.y + 10

method getRecordAABB*(self: ParamRecorder): AABB =
  result.min.x = pos.x - 11 - 3
  result.min.y = pos.y + 5 - 3
  result.max.x = pos.x - 11 + 3
  result.max.y = pos.y + 5 + 3

method getPlayAABB*(self: ParamRecorder): AABB =
  result.min.x = pos.x + 11 - 3
  result.min.y = pos.y + 5 - 3
  result.max.x = pos.x + 11 + 3
  result.max.y = pos.y + 5 + 3

method drawBox(self: ParamRecorder) =
  let x = self.pos.x.int
  let y = self.pos.y.int

  setColor(1)
  rectfill(getAABB())
  setColor(6)
  rect(getAABB())

  if bindings[0].machine != nil:
    var (voice,param) = bindings[0].machine.getParameter(bindings[0].param)
    printShadowC(param.name, x, y - 4)

    setColor(if mode == Recording: 8 else: 0)
    circfill(x - 11, y + 5, 2)

    setColor(if mode == Playback: 11 else: 0)
    circfill(x + 11, y + 5, 2)

    setColor(0)
    rectfill(x - 5, y + 1, x + 5, y + 7)

    block:
      setColor(if mode == Playback: 11 else: 3)
      let x = x - 5 + ((readHead.float / buffers[slot].len.float) * 10.0).float
      line(x, y + 1, x, y + 7)

    if mode == Recording:
      setColor(8)
      let x = x - 5 + ((writeHead.float / buffers[slot].len.float) * 10.0).float
      line(x, y + 1, x, y + 7)


method handleClick(self: ParamRecorder, mouse: Vec2f): bool =
  if pointInAABB(mouse, getRecordAABB()):
    if mode == Recording:
      self.setMode(Stop)
    else:
      self.setMode(Recording)
  elif pointInAABB(mouse, getPlayAABB()):
    if mode == Playback:
      self.setMode(Stop)
    else:
      self.setMode(Playback)
  return false


method process(self: ParamRecorder) =
  if self.mode == Stop:
    return

  nextSample -= 1
  if nextSample <= 0:
    nextSample = rate

    if bindings[0].machine != nil:
      var (voice,param) = bindings[0].machine.getParameter(bindings[0].param)
      case self.mode:
      of Recording:
        buffers[slot][writeHead mod buffers[slot].len] = param.value.float32
        writeHead += 1
        if writeHead > buffers[slot].high:
          writeHead = 0
          setMode(Stop)
      of Playback:
        param.value = buffers[slot][readHead mod buffers[slot].len].float
        param.onchange(param.value, voice)
        readHead += 1
        if readHead > buffers[slot].high:
          readHead = 0
          if not loop:
            setMode(Stop)
      of Stop:
        discard

method saveExtraData(self: ParamRecorder): string =
  var ss = newStringStream("")
  for s in 0..<nSlots:
    ss.write(buffers[s].len.int32)
    for i in 0..<buffers[s].len:
      ss.writeData(buffers[s][i].addr, sizeof(float32))

  ss.setPosition(0)
  result = ss.readAll()
  ss.close()

method loadExtraData(self: ParamRecorder, data: string) =
  if data.len > 0:
    var ss = newStringStream(data)
    try:
      for s in 0..<nSlots:
        let bufferLen = ss.readInt32()
        buffers[s] = newSeq[float32](bufferLen)
        for i in 0..<bufferLen:
          buffers[s][i] = ss.readFloat32()
      ss.close()
    except:
      discard

method drawExtraData(self: ParamRecorder, x,y,w,h: int) =
  var yv = y + 2
  for s in 0..<nSlots:
    if self.buffers[s].len > 0:
      setColor(7)
    else:
      setColor(5)
    print("slot " & $s, x + 2, yv)
    yv += 16

proc newParamRecorder(): Machine =
  var m = new(ParamRecorder)
  m.init()
  return m

registerMachine("paramrec", newParamRecorder, "util")

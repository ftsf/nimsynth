import common
import nico
import nico/vec
import util

type ParamRecorder = ref object of Machine
  buffer: seq[float]
  recording: bool
  playing: bool
  writeHead: int
  readHead: int
  loop: bool

{.this:self.}

method init(self: ParamRecorder) =
  procCall init(Machine(self))

  nBindings = 1
  nInputs = 0
  nOutputs = 0
  bindings.setLen(1)
  name = "prec"
  buffer = newSeq[float]()

  self.globalParams.add([
    Parameter(name: "length", kind: Float, min: 0.0, max: 60.0, default: 10.0, onchange: proc(newValue: float, voice: int) =
      self.buffer.setLen((newValue * sampleRate).int)
      self.readHead = self.readHead mod self.buffer.len
      self.writeHead = self.writeHead mod self.buffer.len
    ),
    Parameter(name: "record", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.recording = newValue.bool
      if self.recording:
        self.writeHead = 0
    ),
    Parameter(name: "trigger", kind: Trigger, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.playing = newValue.bool
      if self.playing:
        self.recording = false
    ),
    Parameter(name: "loop", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.loop = newValue.bool
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

    setColor(if recording: 8 else: 0)
    circfill(x - 11, y + 5, 2)

    setColor(if playing: 11 else: 0)
    circfill(x + 11, y + 5, 2)

    setColor(0)
    rectfill(x - 5, y + 1, x + 5, y + 7)

    block:
      setColor(if playing: 11 else: 3)
      let x = x - 5 + ((readHead.float / buffer.len.float) * 10.0).float
      line(x, y + 1, x, y + 7)

    if recording:
      setColor(if recording: 8 else: 4)
      let x = x - 5 + ((writeHead.float / buffer.len.float) * 10.0).float
      line(x, y + 1, x, y + 7)


method handleClick(self: ParamRecorder, mouse: Vec2f): bool =
  if pointInAABB(mouse, getRecordAABB()):
    var (voice,param) = getParameter(1)
    param.value = (not param.value.bool).float
    param.onchange(param.value, voice)
  elif pointInAABB(mouse, getPlayAABB()):
    var (voice,param) = getParameter(2)
    param.value = (not param.value.bool).float
    param.onchange(param.value, voice)
  return false


method process(self: ParamRecorder) =
  if bindings[0].machine != nil:
    var (voice,param) = bindings[0].machine.getParameter(bindings[0].param)
    if recording:
      buffer[writeHead mod buffer.len] = param.value
      writeHead += 1
      if writeHead > buffer.high:
        writeHead = 0
        recording = false
    if playing:
      param.value = buffer[readHead mod buffer.len]
      param.onchange(param.value, voice)
      readHead += 1
      if readHead > buffer.high:
        readHead = 0
        if not loop:
          playing = false

proc newParamRecorder(): Machine =
  var m = new(ParamRecorder)
  m.init()
  return m

registerMachine("paramrec", newParamRecorder, "util")

import core/fft
import common
import core/basemachine
import nico
import util
import core/ringbuffer
import strutils
import math

type
  SpectrogramMachine = ref object of Machine
    buffer: Ringbuffer[float32]
    data: seq[float32]
    resolution: int
    responseGraph: seq[float32]
    logView: bool

{.this:self.}

proc graphResponse(self: SpectrogramMachine) =
  for i in 0..<resolution:
    if i == buffer.size:
      break
    data[i] = buffer[i]

  var response = graphResponse(data, resolution)
  for i in 0..<resolution:
    responseGraph[i] = response[i]

method init(self: SpectrogramMachine) =
  procCall init(Machine(self))
  name = "spec"
  nInputs = 1
  nOutputs = 1
  stereo = false

  self.globalParams.add([
    Parameter(name: "size", kind: Int, min: 1.0, max: 8.0, default: 1.0, onchange: proc(newValue: float, voice: int) =
      resolution = clamp(newValue.int, 1, 8) * 1024
      buffer = newRingBuffer[float32](resolution)
      data = newSeq[float32](resolution)
      responseGraph = newSeq[float32](resolution)
    ),
    Parameter(name: "log", kind: Bool, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      logView = newValue.bool
    ),
  ])

  setDefaults()

method process(self: SpectrogramMachine) =
  # pass through but store in ringbuffer
  let s = getInput()
  buffer.add([s])
  outputSamples[0] = s

method getAABB*(self: SpectrogramMachine): AABB =
  result.min.x = pos.x - 32
  result.min.y = pos.y - 32
  result.max.x = pos.x + 32
  result.max.y = pos.y + 32


method drawBox(self: SpectrogramMachine) =
  setColor(0)
  rectfill(getAABB())
  setColor(5)
  rect(getAABB())


  graphResponse()

  var highestPeakValue: float32
  var highestPeak: int

  for i in 4..<responseGraph.len div 2:
    if responseGraph[i] > highestPeakValue:
      highestPeak = i
      highestPeakValue = responseGraph[i]

  setColor(1)
  vline(pos.x - 32 + (highestPeak.float / (resolution div 2).float) * 64.0, pos.y - 31, pos.y + 31)

  let hz = sampleRateFractionToHz(highestPeak.float / resolution.float)

  printr("$1 hZ".format(hz.int), pos.x + 30, pos.y - 30)
  printr("$1".format(hzToNoteName(hz)), pos.x + 30, pos.y - 20)

  var sample0: float32
  var sample1: float32

  for i in 1..<64:
    setColor(3)

    if logView:
      sample0 = (i-1).float32
      sample1 = i.float32
    else:
      sample0 = (i-1).float32
      sample1 = i.float32

    let scale = if logView: responseGraph.len.float32 / 10.0'f else: responseGraph.len.float32 / 2.0'f

    let v0 = abs(responseGraph.getSubsample((sample0 / 64.0'f) * scale))
    let v1 = abs(responseGraph.getSubsample((sample1 / 64.0'f) * scale))
    line(
      pos.x + i - 1 - 32,
      pos.y + 31 - clamp(v0 * 2.0, 0, 62.0),
      pos.x + i - 32,
      pos.y + 31 - clamp(v1 * 2.0, 0, 62.0)
    )


proc newMachine(): Machine =
  var m = new(SpectrogramMachine)
  m.init()
  return m

registerMachine("spectrogram", newMachine, "util")

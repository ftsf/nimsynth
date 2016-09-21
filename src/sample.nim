import sndfile
import common
import math
import util

# Common Sampler code, load samples etc

type Sample* = object of RootObj
  data*: seq[float32]
  freq*: float
  loop*: bool
  name*: string

{.this:self.}

proc loadSample*(filename: string): Sample =
  # TODO: add sample rate conversion
  var info: Tinfo
  var fp = sndfile.open(filename.cstring, READ, addr(info))
  if fp == nil:
    result.name = "error"
    result.data = newSeq[float32](1)
    echo "error loading sample: ", filename
    return

  echo "frames: ", info.frames

  result.data = newSeq[float32](info.frames)
  result.name = filename

  let count = fp.read_float(addr(result.data[0]), info.frames)
  if count != info.frames:
    echo "only read ", count, " not ", info.frames

type SampleOsc* = object of RootObj
  sample*: ptr Sample
  samplePos*: float
  freq*: float

proc finished*(self: var SampleOsc): bool =
  if samplePos > sample.data.len.float:
    return true
  return false

proc reset*(self: var SampleOsc) =
  samplePos = 0.0

proc process*(self: var SampleOsc): float32 =
  samplePos += freq * invSampleRate
  let x = samplePos.floor.int
  if x > sample.data.high:
    if sample.loop:
      samplePos -= sample.data.len.float
    else:
      return 0.0

  let alpha = samplePos mod 1.0
  let y0 = sample.data[x]
  let y1 = if sample.loop or x < sample.data.high: sample.data[(x + 1) mod sample.data.len] else: 0.0
  result = lerp(y0, y1, alpha)

# TODO: need reusable sample loading interface code
#
# TODO: need a way to save/load sample data in patches

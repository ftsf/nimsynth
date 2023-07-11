import os
import math

import ../common
import ../util
import nico/vec

import sndfile
import ../ui/menu
import nico


# Common Sampler code, load samples etc

type Sample* = ref object
  data*: seq[float32]
  length*: int # length in samples (for one channel)
  freq*: float32
  rate*: float32
  rootPitch*: float32
  loop*: bool
  loopStart*: int
  loopEnd*: int
  name*: string
  filename*: string
  channels*: int

{.this:self.}

var samplePreview*: Sample
var samplePreviewIndex*: int

proc startSamplePreview(sample: Sample) =
  samplePreview = sample
  samplePreviewIndex = 0

type
  SF_INSTRUMENT_LOOP = object
    mode: int
    start: uint
    `end`: uint
    count: uint
  SF_INSTRUMENT = object
    gain: int
    basenote, detune: char
    velocity_lo, velocity_hi: char
    key_lo, key_hi: char
    loop_count: int
    loops: array[16,SF_INSTRUMENT_LOOP]


proc subSample*(source: Sample, start: int, size: int, windowSize: int = 0): Sample =
  # generate a new sample from a section of a Sample
  result = new(Sample)
  result.data = newSeq[float32](size)
  for i in 0..<size:
    let s = start + i
    if s < 0 or s >= source.data.len:
      result.data[i] = 0'f
    else:
      result.data[i] = source.data[s]
      if i < windowSize:
        let distFromEdge = i
        result.data[i] *= lerp(0'f, 1'f, distFromEdge.float32 / windowSize.float32)
      if i > size - 1 - windowSize:
        let distFromEdge = (size - 1) - i
        result.data[i] *= lerp(0'f, 1'f, distFromEdge.float32 / windowSize.float32)

  result.length = size
  result.freq = source.freq
  result.rate = source.rate
  result.rootPitch = source.rootPitch
  result.loop = true
  result.loopStart = 0
  result.loopEnd = size - 1
  result.name = ""
  result.filename = ""
  result.channels = source.channels

proc toMono*(self: Sample): Sample =
  if self.channels == 1:
    return self

  result = new(Sample)
  result.data = newSeq[float32](self.length)
  result.channels = 1
  result.length = self.length
  result.freq = self.freq
  result.rate = self.rate
  result.rootPitch = self.rootPitch
  result.loop = self.loop
  result.loopStart = self.loopStart
  result.loopEnd = self.loopEnd
  result.name = self.name
  result.filename = self.filename

  for i in 0..<self.length:
    result.data[i] = self.data[i*self.channels]

proc loadSample*(filename: string, name: string): Sample =
  result = new(Sample)
  # TODO: add sample rate conversion
  var info: Tinfo
  var fp = sndfile.open(filename.cstring, READ, addr(info))
  if fp == nil:
    result.name = "error"
    result.data = newSeq[float32](1)
    echo "error loading sample: ", filename
    return

  #echo "frames: ", info.frames
  #echo "samplerate: ", info.samplerate
  #echo "channels: ", info.channels

  result.data = newSeq[float32](info.frames)
  result.name = name
  result.filename = filename
  result.rate = info.samplerate.float
  result.rootPitch = middleC
  result.channels = info.channels
  result.length = info.frames.int div info.channels

  var instrument: SF_INSTRUMENT
  if fp.command(SFC_GET_INSTRUMENT, instrument.addr, sizeof(SF_INSTRUMENT).cint).TBOOL == SF_TRUE:
    echo instrument
    result.rootPitch = noteToHz(instrument.baseNote.float)

  let count = fp.read_float(addr(result.data[0]), info.frames)
  if count != info.frames:
    echo "only read ", count, " not ", info.frames, " channels: ", info.channels, " errcode: ", fp.strerror()

type SampleOsc* = object
  sample*: Sample
  samplePos*: float32
  speed*: float32
  loop*: bool
  offset*: float32 # 0..1
  stereo*: bool

proc setSpeedByLength*(self: var SampleOsc, length: float32) =
  # calculates the playback speed based on the desired length
  if sample != nil:
    let realLength = sample.length.float32 / sample.rate
    speed = realLength / length

proc finished*(self: var SampleOsc): bool =
  if self.sample == nil:
    return true
  if not loop and samplePos.int >= sample.length:
    return true
  return false

proc reset*(self: var SampleOsc) =
  samplePos = 0.0

proc getInterpolatedSample*(s: Sample, pos: float32, channel: int): float32 =
  let alpha = pos mod 1.0
  let frame = pos.int
  if frame < 0:
    return 0.0
  if frame >= s.length - 1:
    return 0.0
  let channel = min(channel, s.channels - 1)
  return lerp(s.data[frame * s.channels + channel], s.data[(frame+1) * s.channels + channel], alpha)

proc zeroBeyond(x: int, length: int): int =
  if x >= length-1 or x < 0:
    return 0
  return x

proc getCubicInterpolatedSample*(s: Sample, pos: float32, channel: int): float32 =
  let alpha = pos mod 1.0
  let frame = pos.int
  let length = s.length
  return cubic(
    s.data[zeroBeyond(frame-1, length) * s.channels + channel],
    s.data[zeroBeyond(frame,   length) * s.channels + channel],
    s.data[zeroBeyond(frame+1, length) * s.channels + channel],
    s.data[zeroBeyond(frame+2, length) * s.channels + channel],
    alpha)

proc getInterpolatedSampleLoop*(s: Sample, pos: float32, channel: int): float32 =
  let pos = pos mod s.length.float32
  let alpha = pos mod 1.0
  return lerp(
    s.data[pos.int * s.channels + channel],
    s.data[(pos.int+1) * s.channels + channel],
    alpha)

proc getCubicInterpolatedSampleLoop*(s: Sample, pos: float32, channel: int): float32 =
  let pos = pos mod s.length.float32
  let alpha = pos mod 1.0'f
  let length = s.length
  let frame = pos.int
  let channel = min(channel, s.channels - 1)
  return cubic(
    s.data[modSign(frame-1, length) * s.channels + channel],
    s.data[modSign(frame,   length) * s.channels + channel],
    s.data[modSign(frame+1, length) * s.channels + channel],
    s.data[modSign(frame+2, length) * s.channels + channel],
    alpha)

proc process*(self: var SampleOsc): float32 =
  if self.sample == nil:
    return 0'f
  let channel = sampleId mod 2
  if channel == 0 or stereo:
    let offset = offset * sample.length.float32
    if loop:
      result = sample.getCubicInterpolatedSampleLoop(samplePos + offset, channel)
    else:
      result = sample.getCubicInterpolatedSample(samplePos + offset, channel)

  if channel == 0:
    samplePos += speed * (sample.rate / sampleRate)

# TODO: need reusable sample loading interface code
#
# TODO: need a way to save/load sample data in patches

proc newSampleMenu*(mv: Vec2f, prefix = "samples/", action: proc(sample: Sample) = nil): Menu =
  var menu = newMenu(mv, "load sample")
  var count = 0
  for file in walkPattern(prefix & "*"):
    count += 1
    (proc() =
      let file = file
      if existsDir(file):
        let dirname = file[prefix.len..file.high]
        menu.items.add(newMenuItem(dirname & "/") do():
          let (mx,my) = mouse()
          let mv = vec2f(mx,my)
          pushMenu(newSampleMenu(mv, file & "/", action))
        )
      else:
        let sampleName = file[(prefix.len)..file.high-4]
        let item = newMenuItem(sampleName) do():
          let sample = loadSample(file, sampleName)
          action(sample)
          if not shift():
            while hasMenu():
              popMenu()
        item.status = Primary
        item.altAction = proc() =
          # alt click to preview sample
          let sample = loadSample(file, sampleName)
          samplePreview = sample
          samplePreviewIndex = 0
        menu.items.add(item)
    )()
  if count == 0:
    menu.items.add(newMenuItem("no samples"))
  return menu

proc drawSample*(self: Sample, x,y,w,h: int, startOffset = 0'f, endOffset = 1'f) =
  var left0,left1: int
  var right0,right1: int
  setColor(1)
  rect(x,y,x+w-1,y+h-1)
  let startSample = (self.length.float32 * startOffset).int
  let endSample = (self.length.float32 * endOffset).int
  let length = endSample - startSample
  for i in 0..<w:
    let sample = startSample.float32 + ((i.float32 / w.float32) * length.float32).float32
    let left1s = self.getInterpolatedSample(sample, 0)
    let right1s = if self.channels == 2: self.getInterpolatedSample(sample, 1) else: 0'f
    left1 = lerp((y+h-1).float32, y.float32, left1s * 0.5'f + 0.5'f).int
    right1 = lerp((y+h-1).float32, y.float32, right1s * 0.5'f + 0.5'f).int
    if i > 0:
      setColor(3)
      line(x+i-1, left0, x+i, left1)
      if self.channels == 2:
        setColor(4)
        line(x+i-1, right0, x+i, right1)
    left0 = left1
    right0 = right1

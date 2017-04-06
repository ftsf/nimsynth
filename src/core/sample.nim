import os
import math
import basic2d

import common
import util

import sndfile
import ui.menu


# Common Sampler code, load samples etc

type Sample* = ref object of RootObj
  data*: seq[float32]
  length*: int # length in samples
  freq*: float
  rate*: float
  rootPitch*: float
  loop*: bool
  loopStart*: int
  loopEnd*: int
  name*: string
  filename*: string
  channels*: int

{.this:self.}

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

  echo "frames: ", info.frames
  echo "samplerate: ", info.samplerate
  echo "channels: ", info.channels

  result.data = newSeq[float32](info.frames)
  result.name = name
  result.filename = filename
  result.rate = info.samplerate.float
  result.rootPitch = middleC
  result.channels = info.channels
  result.length = info.frames.int div info.channels

  var instrument: SF_INSTRUMENT
  if fp.command(SFC_GET_INSTRUMENT, instrument.addr, sizeof(SF_INSTRUMENT)) == SF_TRUE:
    echo instrument
    result.rootPitch = noteToHz(instrument.baseNote.float)

  let count = fp.read_float(addr(result.data[0]), info.frames)
  if count != info.frames:
    echo "only read ", count, " not ", info.frames

type SampleOsc* = object of RootObj
  sample*: Sample
  samplePos*: float
  speed*: float
  loop*: bool
  offset*: float # 0..1
  stereo*: bool

proc setSpeedByLength*(self: var SampleOsc, length: float) =
  # calculates the playback speed based on the desired length
  if sample != nil:
    let realLength = sample.length.float / sample.rate
    speed = realLength / length

proc finished*(self: var SampleOsc): bool =
  if not loop and samplePos.int >= sample.length:
    return true
  return false

proc reset*(self: var SampleOsc) =
  samplePos = 0.0

proc getInterpolatedSample*(s: Sample, pos: float, channel: int): float32 =
  let alpha = pos mod 1.0
  let frame = pos.int
  if frame < 0:
    return 0.0
  if frame >= s.length - 1:
    return 0.0
  let channel = min(channel, s.channels - 1)
  return lerp(s.data[frame * s.channels + channel], s.data[(frame+1) * s.channels + channel], alpha)

proc getCubicInterpolatedSample*(s: Sample, pos: float, channel: int): float32 =
  let alpha = pos mod 1.0
  let frame = pos.int
  let length = s.length
  return cubic(
    s.data[zeroBeyond(frame-1, length) * s.channels + channel],
    s.data[zeroBeyond(frame,   length) * s.channels + channel],
    s.data[zeroBeyond(frame+1, length) * s.channels + channel],
    s.data[zeroBeyond(frame+2, length) * s.channels + channel],
    alpha)

proc getInterpolatedSampleLoop*(s: Sample, pos: float, channel: int): float32 =
  let pos = pos mod s.length.float
  let alpha = pos mod 1.0
  return lerp(
    s.data[pos.int * s.channels + channel],
    s.data[(pos.int+1) * s.channels + channel],
    alpha)

proc getCubicInterpolatedSampleLoop*(s: Sample, pos: float, channel: int): float32 =
  let pos = pos mod s.length.float
  let alpha = pos mod 1.0
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
  let channel = sampleId mod 2
  if channel == 0 or stereo:
    let offset = offset * sample.length.float
    if loop:
      result = sample.getCubicInterpolatedSampleLoop(samplePos + offset, channel)
    else:
      result = sample.getCubicInterpolatedSample(samplePos + offset, channel)

  if channel == 0:
    samplePos += speed * (sample.rate / sampleRate)

# TODO: need reusable sample loading interface code
#
# TODO: need a way to save/load sample data in patches

proc newSampleMenu*(mv: Point2d, prefix = "samples/", action: proc(sample: Sample) = nil): Menu =
  var menu = newMenu(mv, "load sample")
  for file in walkFiles(prefix & "*.*"):
    (proc() =
      let file = file
      let sampleName = file[(prefix.len)..file.high-4]
      menu.items.add(newMenuItem(sampleName) do():
        var sample = loadSample(file, sampleName)
        action(sample)
        popMenu()
      )
    )()
  return menu

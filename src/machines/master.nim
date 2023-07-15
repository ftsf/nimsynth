import common
import math

{.this:self.}

const nChannels = 8

type
  Master* = ref object of Machine
    beatsPerMinute*: float32
    gain: float32
    channel: array[nChannels, float32]
    channelGain: array[nChannels, float32]
    channelPan: array[nChannels, float32]
    channelPeaksL: array[nChannels, float32]
    channelPeaksR: array[nChannels, float32]
    totalPeakL: float32
    totalPeakR: float32

method init*(self: Master) =
  procCall init(Machine(self))
  name = "master"
  className = "master"
  nInputs = nChannels
  nOutputs = 1
  gain = 1.0f
  for i in 0..<nChannels:
    channelGain[i] = 1.0f
  stereo = true
  beatsPerMinute = 128.0f
  globalParams.add([
    Parameter(kind: Float, name: "volume", min: 0.0f, max: 10.0f, default: 1.0f, value: 1.0f, onchange: proc(newValue: float32, voice: int) =
      self.gain = clamp(newValue, 0.0f, 10.0f)
    ),
    Parameter(kind: Int, name: "bpm", min: 1.0f, max: 300.0f, default: 128.0f, value: 128.0f, onchange: proc(newValue: float32, voice: int) =
      self.beatsPerMinute = clamp(newValue, 1.0f, 300.0f)
      for machine in mitems(machines):
        machine.onBPMChange(self.beatsPerMinute.int)
    ),
  ])

  for i in 0..<nChannels:
    closureScope:
      var j = i
      globalParams.add([
        Parameter(kind: Float, name: $(j+1) & ": gain", min: 0.0, max: 5.0, default: 1.0, separator: true, onchange: proc(newValue: float32, voice: int) =
          self.channelGain[j] = newValue
        ),
        Parameter(kind: Float, name: $(j+1) & ": pan", min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float32, voice: int) =
          self.channelPan[j] = newValue
        )
      ])

  setDefaults()

  # Master needs a sample output despite having no outputs
  outputSamples = newSeq[float32](1)

method getInputName(self: Master, inputId: int = 0): string =
  return "channel " & $(inputId + 1)

method process*(self: Master) =
  outputSamples[0] = 0.0
  for i in 0..<nChannels:
    channel[i] = 0.0

  for input in inputs:
    self.channel[input.inputId] += input.getSample()

  for i in 0..<nChannels:
    var c = channel[i] * channelGain[i]
    if sampleId mod 2 == 0:
      c *= sin(channelPan[i] * PI * 0.5)
      let absc = abs(c)
      if absc > channelPeaksL[i]:
        channelPeaksL[i] = absc
    else:
      c *= cos(channelPan[i] * PI * 0.5)
      let absc = abs(c)
      if absc > channelPeaksR[i]:
        channelPeaksR[i] = absc
    outputSamples[0] += c

  outputSamples[0] *= gain

proc newMaster(): Machine =
  result = new(Master)
  result.init()
  masterMachine = result

proc beatsPerMinute*(): float32 =
  var m = Master(masterMachine)
  return m.beatsPerMinute

proc beatsPerSecond*(): float32 =
  var m = Master(masterMachine)
  return m.beatsPerMinute / 60.0

import nico

method drawExtraData(self: Master, x,y,w,h: int) =
  # draw our input volumes
  var y = y
  var totalL = 0.0
  var totalR = 0.0
  for i in 0..<nChannels:
    setColor(7)
    print($(i+1), x + 1, y)
    var ampL = channelPeaksL[i]
    var ampR = channelPeaksR[i]

    totalL += ampL
    totalR += ampR

    channelPeaksL[i] *= 0.9
    channelPeaksR[i] *= 0.9

    if ampL > 0.9:
      setColor(7)
    elif ampL > 0.75:
      setColor(4)
    else:
      setColor(3)
    rectfill(x + 1, y + 8, x + 1 + ((w - 2).float32 * (clamp(ampL, 0.0, 2.0) * 0.5)).int, y + 8 + 4)
    if ampR > 0.9:
      setColor(7)
    elif ampR > 0.75:
      setColor(4)
    else:
      setColor(3)
    rectfill(x + 1, y + 8 + 4 + 2, x + 1 + ((w - 2).float32 * (clamp(ampR, 0.0, 2.0) * 0.5)).int, y + 8 + 4 + 2 + 4)

    setColor(7)
    vline(x + 1 + (w - 2) div 2, y + 10, y + 24)
    setColor(8)
    vline(x + 1 + (((w - 2) div 2).float32 * channelGain[i]).int, y + 8, y + 26)

    y += 25

  if totalL > totalPeakL:
    totalPeakL = totalL
  if totalR > totalPeakR:
    totalPeakR = totalR

  block:
    let ampL = totalL
    let ampR = totalR

    if ampL > 0.9f:
      setColor(7)
    elif ampL > 0.75f:
      setColor(4)
    else:
      setColor(3)
    rectfill(x + 1, y + 8, x + 1 + ((w - 2).float32 * (clamp(ampL, 0.0, 2.0) * 0.5)).int, y + 8 + 4)
    if ampR > 0.9:
      setColor(7)
    elif ampR > 0.75f:
      setColor(4)
    else:
      setColor(3)
    rectfill(x + 1, y + 8 + 4 + 2, x + 1 + ((w - 2).float32 * (clamp(ampR, 0.0, 2.0) * 0.5)).int, y + 8 + 4 + 2 + 4)

    setColor(7)
    vline(x + 1 + (w - 2) div 2, y + 10, y + 24)
    setColor(8)
    vline(x + 1 + (((w - 2) div 2).float32 * gain).int, y + 8, y + 26)

  totalPeakL *= 0.9f
  totalPeakR *= 0.9f

registerMachine("master", newMaster)

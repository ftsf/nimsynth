import common
import filter
import math
import util
import pico

{.this:self.}

const nFilters = 3
const bufferSize = 512

type
  EQ = ref object of Machine
    filtersL: array[nFilters,BiquadFilter]
    filtersR: array[nFilters,BiquadFilter]
    filtersOn: array[nFilters,bool]
    inputBuffer: array[bufferSize, float32]
    outputBuffer: array[bufferSize, float32]
    writeHead: int

method init(self: EQ) =
  procCall init(Machine(self))
  name = "eq"
  nInputs = 1
  nOutputs = 1
  stereo = true

  for i in 0..<nFilters:
    (proc() =
      var i = i
      if i == 0:
        self.filtersL[i].kind = Highpass
        self.filtersR[i].kind = Highpass
      elif i == nFilters-1:
        self.filtersL[i].kind = LowPass
        self.filtersR[i].kind = LowPass
      else:
        self.filtersL[i].kind = Peak
        self.filtersR[i].kind = Peak

      self.globalParams.add([
        Parameter(name: $i & ": enabled", kind: Int, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.filtersOn[i] = newValue.bool
        , getValueString: proc(value: float, voice: int): string =
          return (if value.bool: "on" else: "off")
        ),
        Parameter(name: $i & ": type", kind: Int, min: Peak.float, max: FilterKind.high.float, default: Peak.float, onchange: proc(newValue: float, voice: int) =
          self.filtersL[i].kind = newValue.FilterKind
          self.filtersR[i].kind = newValue.FilterKind
          self.filtersL[i].calc()
          self.filtersR[i].calc()
        , getValueString: proc(value: float, voice: int): string =
          return $value.FilterKind
        ),
        Parameter(name: $i & ": cutoff", kind: Float, min: 0.0, max: 1.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
          self.filtersL[i].cutoff = exp(lerp(-8.0, -0.8, newValue))
          self.filtersR[i].cutoff = exp(lerp(-8.0, -0.8, newValue))
          self.filtersL[i].calc()
          self.filtersR[i].calc()
        , getValueString: proc(value: float, voice: int): string =
          return $(exp(lerp(-8.0, -0.8, value)) * sampleRate).int & " hZ"
        ),
        Parameter(name: $i & ": q", kind: Float, min: 0.0001, max: 5.0, default: 0.5, onchange: proc(newValue: float, voice: int) =
          self.filtersL[i].resonance = newValue
          self.filtersR[i].resonance = newValue
          self.filtersL[i].calc()
          self.filtersR[i].calc()
        ),
        Parameter(name: $i & ": gain", kind: Float, min: -24.0, max: 24.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
          self.filtersL[i].peakGain = newValue
          self.filtersR[i].peakGain = newValue
          self.filtersL[i].calc()
          self.filtersR[i].calc()
        ),
      ])
    )()

  setDefaults()


method process(self: EQ) {.inline.} =
  outputSamples[0] = getInput()
  if outputSampleId mod 2 == 0:
    inputBuffer[writeHead] = outputSamples[0]

  for i in 0..<nFilters:
    if filtersOn[i]:
      if outputSampleId mod 2 == 0:
        outputSamples[0] = self.filtersL[i].process(outputSamples[0])
        outputBuffer[writeHead] = outputSamples[0]
      else:
        outputSamples[0] = self.filtersR[i].process(outputSamples[0])

  if outputSampleId mod 2 == 0:
    outputBuffer[writeHead] = outputSamples[0]
    writeHead += 1
    writeHead = writeHead mod bufferSize

proc newEQ(): Machine =
  var eq = new(EQ)
  eq.init()
  return eq

method drawExtraData(self: EQ, x,y,w,h: int) =
  # draw frequency response
  const resolution = 1024

  var impulse = generateImpulse(resolution)
  for i in 0..<nFilters:
    if filtersOn[i]:
      var filter = filtersL[i]
      filter.reset()
      filter.kind = filtersL[i].kind
      filter.cutoff = filtersL[i].cutoff
      filter.resonance = filtersL[i].resonance
      filter.peakGain = filtersL[i].peakGain
      filter.calc()

      for i in 0..<resolution:
        impulse[i] = filter.process(impulse[i])


  block:
    var response = graphResponse(impulse, resolution)
    setColor(6)
    for i in 1..<resolution:
      let y0 = response[(i-1)] * 10.0
      let y1 = response[i] * 10.0
      line(x + (i-1), h - y0, x + i, h - y1)

  when false:
    block:
      var input: array[bufferSize, float32]
      for i in 0..<bufferSize:
        input[i] = inputBuffer[(writeHead+i) mod bufferSize]
      var response = graphResponse(input, resolution)
      setColor(8)
      for i in 1..<w:
        let y0 = response.getSubsample((i-1).float * (resolution.float / w.float))
        let y1 = response.getSubsample(i.float * (resolution.float / w.float))
        line(x + (i-1), h - y0, x + i, h - y1)
    block:
      var output: array[bufferSize, float32]
      for i in 0..<bufferSize:
        output[i] = outputBuffer[(writeHead+i) mod bufferSize]
      var response = graphResponse(output, resolution)
      setColor(9)
      for i in 1..<w:
        let y0 = response.getSubsample((i-1).float * (resolution.float / w.float))
        let y1 = response.getSubsample(i.float * (resolution.float / w.float))
        line(x + (i-1), h - y0, x + i, h - y1)

registerMachine("eq", newEQ, "fx")

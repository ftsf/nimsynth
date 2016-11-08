import common

{.this:self.}

type
  Master* = ref object of Machine
    beatsPerMinute*: float
    gain: float

method init*(self: Master) =
  procCall init(Machine(self))
  name = "master"
  className = "master"
  nInputs = 1
  nOutputs = 1
  gain = 1.0
  stereo = true
  beatsPerMinute = 128.0
  globalParams.add([
    Parameter(kind: Float, name: "volume", min: 0.0, max: 10.0, default: 1.0, value: 1.0, onchange: proc(newValue: float, voice: int) =
      self.gain = clamp(newValue, 0.0, 10.0)
    ),
    Parameter(kind: Int, name: "bpm", min: 1.0, max: 300.0, default: 128.0, value: 128.0, onchange: proc(newValue: float, voice: int) =
      self.beatsPerMinute = clamp(newValue, 1.0, 300.0)
      for machine in mitems(machines):
        machine.onBPMChange(self.beatsPerMinute.int)
    ),
  ])

  setDefaults()

  # Master needs a sample output despite having no outputs
  outputSamples = newSeq[float32](1)

method process*(self: Master) =
  outputSamples[0] = 0.0
  for input in inputs:
    outputSamples[0] += input.getSample()
  outputSamples[0] *= gain

proc newMaster*(): Master =
  result = new(Master)
  result.init()

proc beatsPerMinute*(): float =
  var m = Master(masterMachine)
  return m.beatsPerMinute

proc beatsPerSecond*(): float =
  var m = Master(masterMachine)
  return m.beatsPerMinute / 60.0

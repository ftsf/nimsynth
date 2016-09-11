import filter
import ringbuffer

{.this:self.}

type
  Delay* = object of RootObj
    buffer: RingBuffer[float32]
    wet*,dry*: float
    feedback*: float
    cutoff*: float
    filter: OnePoleFilter

proc setLen*(self: var Delay, newLength: int) =
  self.buffer = newRingBuffer[float32](newLength)

proc update*(self: var Delay, sample: float32): float32 =
  var fromDelay = self.buffer[0]
  filter.setCutoff(cutoff)
  fromDelay = filter.process(fromDelay)
  self.buffer.add([(sample + fromDelay * feedback).float32])
  return fromDelay * wet + sample * dry

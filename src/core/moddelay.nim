import common
import math
import util
import nico

const maxSamples = 48000

type
  ModDelay* = object of RootObj
    tape*: array[maxSamples, float32]
    readHead*: int
    writeHead*: int
    delayTime*: float32 # in seconds
    feedback*: float32

{.this:self.}

proc process*(self: var ModDelay, input: float32): float32 =
  let delayTime = clamp(delayTime, 0.0, 1.0)
  writeHead += 1
  if writeHead > tape.high:
    writeHead = 0
  # readHead should be exactly delayTime behind writeHead
  readHead = (writeHead - floor(delayTime * sampleRate).int) %%/ tape.len
  let readHead1 = if readHead - 1 < 0: tape.high else: readHead - 1
  var alpha = (delayTime * sampleRate) mod 1.0
  result = lerp(tape[readHead], tape[readHead1], alpha)

  if readHead > tape.high:
    writeHead = 0

  tape[writeHead] = input + feedback * result

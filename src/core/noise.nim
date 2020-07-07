import bitops
import math

type Noise* = object
  value: uint32

func extractBit[T: SomeInteger](v: T, bit: BitsRange[T]): T =
  v and (1.T shl bit)

proc next*(self: var Noise): float32 =
  if self.value == 0:
    self.value = 0xdeadbeef'u32

  let b0  = extractBit(self.value, 0)
  let b1  = extractBit(self.value, 1)
  let b27 = extractBit(self.value, 27)
  let b28 = extractBit(self.value, 28)

  var b31 = b0 xor b1 xor b27 xor b28

  if b31 == 1'u32:
    b31 = 0x1000_0000'u32

  self.value = self.value shr 1'u32

  self.value = self.value or b31

  return self.value.float32

import unittest

suite "noise":
  test "noise":
    var n = Noise(value: 0xdeadbeef'u32)
    echo n.next()
    echo n.next()
    echo n.next()
    echo n.next()
    echo n.next()

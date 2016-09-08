const sampleRate* = 48000.0
const invSampleRate* = 1.0/sampleRate

import sdl2

type
  View* = ref object of RootObj
    discard

method update*(self: View, dt: float) {.base.} =
  discard

method draw*(self: View) {.base.} =
  discard

method key*(self: View, key: KeyboardEventPtr, down: bool): bool {.base.} =
  return false

import pico
import sdl2

import common
import menu
import machineview
import layoutview

import master
import sequencer
import synth
import tb303
import gbsynth
import organ
import fmsynth
import basicfm
import kit
import noise
import lfo
import knob
import button
import flanger
import compressor
import dc
import paramrecorder
import gate
import arp
import eq
import probgate
import probpick
import paramlp
import transposer
import keyboard
import dummy


proc audioCallback(userdata: pointer, stream: ptr uint8, len: cint) {.cdecl.} =
  setupForeignThreadGc()
  var samples = cast[ptr array[int.high,float32]](stream)
  var nSamples = len div sizeof(float32)
  for i in 0..<nSamples:
    sampleId += 1
    # update all machines
    for machine in mitems(machines):
      if machine.stereo or sampleId mod 2 == 0:
        machine.process()
    samples[i] = masterMachine.outputSamples[0]
    if i mod 2 == 0 and i < 2048:
      sampleBuffer[i div 2] = samples[i]

proc eventFunc(event: Event): bool =
  let ctrl = ctrl()
  case event.kind:
  of KeyDown, KeyUp:
    let down = event.kind == KeyDown
    # handle global keys
    let scancode = event.key.keysym.scancode
    if down:
      case scancode:
      of SDL_SCANCODE_F1:
        currentView = vLayoutView
        return true
      of SDL_SCANCODE_1:
        if ctrl:
          currentView = vLayoutView
          return true
      of SDL_SCANCODE_SLASH:
        baseOctave -= 1
        return true
      of SDL_SCANCODE_APOSTROPHE:
        baseOctave += 1
        return true
      of SDL_SCANCODE_Q:
        if ctrl:
          # TODO: ask if ok to exit
          shutdown()
          return true
      else:
        discard

    if recordMachine != nil:
      let note = keyToNote(event.key)
      if note > -1:
        if down and not event.key.repeat:
          recordMachine.trigger(note)
        elif not down:
          recordMachine.release(note)

  else:
    discard

  if hasMenu():
    var menu = getMenu()
    if menu.event(event):
      return true

  if currentView.event(event):
    return true

  return false


proc init() =
  loadSpriteSheet("spritesheet.png")
  setAudioCallback(2, audioCallback)
  setEventFunc(eventFunc)

  machines = newSeq[Machine]()
  menuStack = newSeq[Menu]()

  masterMachine = newMaster()
  machines.add(masterMachine)

  vLayoutView = newLayoutView()
  currentView = vLayoutView
  recordMachine = nil

proc update(dt: float) =
  if currentView != nil:
    currentView.update(dt)

proc draw() =
  if currentView != nil:
    currentView.draw()

  setCamera()

  if hasMenu():
    var menu = getMenu()
    menu.draw()

  let mv = mouse()
  spr(20, mv.x, mv.y)

pico.init(false)
pico.run(init, update, draw)

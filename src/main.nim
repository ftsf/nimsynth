import os
import strutils

import nico
import nico/vec
import util

import common
import core/ringbuffer

import machines/master

import machines/converters/a2e
import machines/converters/e2a
import machines/converters/n2f

import machines/fx/svf
import machines/fx/compressor
import machines/fx/delay
import machines/fx/distortion
import machines/fx/eq
import machines/fx/mod_filter
import machines/fx/flanger
import machines/fx/gate
import machines/fx/sandh
import machines/fx/bitcrush
import machines/fx/mod_amp
import machines/fx/stereo

import machines/generators/clock
import machines/generators/adsr
import machines/generators/eadsr
import machines/generators/basicfm
import machines/generators/fmsynth
import machines/generators/gbsynth
import machines/generators/kit
import machines/generators/noise
import machines/generators/organ
import machines/generators/osc
import machines/generators/synth
import machines/generators/tb303
import machines/generators/mod_lfsr
#import machines/generators/ym2612
import machines/generators/kayoubi
import machines/generators/sampler
import machines/generators/looper
import machines/generators/granular

import machines/io/filerec
import machines/io/keyboard

import machines/math/operators
import machines/math/accumulator

import machines/ui/button
import machines/ui/knob
import machines/ui/value
import machines/ui/xy

import machines/util/arp
import machines/util/chord
import machines/util/chordprog
import machines/util/dc
import machines/util/karp
import machines/util/lfo
import machines/util/paramlp
import machines/util/paramrecorder
import machines/util/probgate
import machines/util/probpath
import machines/util/probpick
import machines/util/sequencer
import machines/util/split
import machines/util/transposer
import machines/util/spectrogram
import machines/util/scale

import ui/machineview
import ui/layoutview
import ui/menu

import core/sample

var glitch = 0.0
var panic: bool

when defined(jack):
  import jack.types
  import jack.jack
  import jack.midiport

import machines.io.audioin

when defined(jack):
  var J: ptr JackClient
  var outputPort1: ptr JackPort
  var outputPort2: ptr JackPort
  var inputPort1: ptr JackPort
  var inputPort2: ptr JackPort
  var midiInputPort: ptr JackPort
  #var midiOutputPort: ptr JackPort

  proc audioCallbackJack(nframes: jack_nframes, arg: pointer): cint =
    setupForeignThreadGc()
    glitch = 0.0

    var samplesL = cast[ptr array[int.high, float32]](jack_port_get_buffer(outputPort1, nframes))
    var samplesR = cast[ptr array[int.high, float32]](jack_port_get_buffer(outputPort2, nframes))

    var inputL = cast[ptr array[int.high, float32]](jack_port_get_buffer(inputPort1, nframes))
    var inputR = cast[ptr array[int.high, float32]](jack_port_get_buffer(inputPort2, nframes))

    if panic:
      zeroMem(samplesL, nframes.int * sizeof(float32))
      zeroMem(samplesR, nframes.int * sizeof(float32))
      return

    var midiEvents = jack_port_get_buffer(midiInputPort, nframes)

    var nMidiEvents = jack_midi_get_event_count(midiEvents)
    var eventIndex = 0

    var rawMidiEvent: JackMidiEvent
    var midiEvent: MidiEvent
    if nMidiEvents > 0:
      discard jack_midi_event_get(rawMidiEvent.addr, midiEvents, 0'u32)
      midiEvent = newMidiEvent(rawMidiEvent)

    for i in 0..<nframes * 2:
      let time = i div 2
      sampleId += 1

      if midiEvent.time == time.int and eventIndex < nMidiEvents:
        for machine in mitems(machines):
          if machine.useMidi and machine.midiChannel == midiEvent.channel:
            machine.midiEvent(midiEvent)

        eventIndex += 1
        if eventIndex < nMidiEvents:
          discard jack_midi_event_get(rawMidiEvent.addr, midiEvents, eventIndex.uint32)
          midiEvent = newMidiEvent(rawMidiEvent)

      if i mod 2 == 0:
        inputSample = inputL[time]
      else:
        inputSample = inputR[time]

      # update all machines
      for machine in mitems(machines):
        if not machine.disabled and not machine.bypass:
          if machine.stereo or sampleId mod 2 == 0:
            machine.process()
            for input in mitems(machine.inputs):
              let s = abs(input.getSample())
              if s > input.peak:
                input.peak = s

      if i mod 2 == 0:
        samplesL[time] = masterMachine.outputSamples[0]
        if samplesL[time] > 1.0 or samplesL[time] < -1.0:
          glitch += abs(samplesL[time]) - 1.0
        if sampleMachine != nil:
          oscilliscopeBuffer.add([sampleMachine.outputSamples[0]])
      else:
        samplesR[time] = masterMachine.outputSamples[0]
        if samplesR[time] > 1.0 or samplesR[time] < -1.0:
          glitch += abs(samplesR[time]) - 1.0

  proc setSampleRate(nframes: jack_nframes, arg: pointer): cint =
    echo "sampleRate: ", nframes
    sampleRate = nframes.float
    invSampleRate = 1.0 / sampleRate
    nyquist = sampleRate / 2.0

else:

  proc audioCallback(input: float32): float32 =
    glitch = 0.0

    if panic:
      return 0.0

    sampleId += 1

    inputSample = audioInSample

    # update all machines
    for machine in mitems(machines):
      if machine.disabled or machine.bypass:
        continue
      if machine.stereo or sampleId mod 2 == 0:
        machine.process()
        for input in mitems(machine.inputs):
          let s = abs(input.getSample())
          if s > input.peak:
            input.peak = s

    var output = masterMachine.outputSamples[0]
    if abs(output) > 1.0:
      glitch += abs(output) - 1.0

    if not oscilliscopeFreeze and sampleId mod 2 == 0 and sampleMachine != nil:
      oscilliscopeBuffer.add([sampleMachine.outputSamples[0]])

    if samplePreview != nil:
      output += samplePreview.data[samplePreviewIndex]
      if samplePreview.channels == 2 or sampleId mod 2 == 0:
        samplePreviewIndex += 1
        if samplePreviewIndex >= samplePreview.length:
          samplePreview = nil

    return output

import core/basemachine

proc setShortcut(shortcut: range[0..9], machine: Machine) =
  if shortcut == 0:
    return
  shortcuts[shortcut] = machine

proc switchToShortcut(shortcut: range[0..9]) =
  if shortcut == 0:
    currentView = vLayoutView
    return
  if shortcuts[shortcut] != nil:
    currentView = shortcuts[shortcut].getMachineView()
  elif currentView of MachineView:
    setShortcut(shortcut, MachineView(currentView).machine)

proc handleShortcutKey(shortcut: range[0..9]): bool =
  let shift = shift()
  if shift:
    if currentView of MachineView:
      setShortcut(shortcut, MachineView(currentView).machine)
      return true
    elif currentView of LayoutView:
      let lv = LayoutView(currentView)
      if lv.currentMachine != nil:
        setShortcut(shortcut, lv.currentMachine)
        return true
  else:
    switchToShortcut(shortcut)
    return true

proc handleShortcutKeys(event: Event): bool =
  let down = event.kind == ekKeyDown
  let ctrl = ctrl()
  let scancode = event.scancode
  if down and ctrl:
    case scancode:
    of SCANCODE_1:
      return handleShortcutKey(0)
    of SCANCODE_2:
      return handleShortcutKey(1)
    of SCANCODE_3:
      return handleShortcutKey(2)
    of SCANCODE_4:
      return handleShortcutKey(3)
    of SCANCODE_5:
      return handleShortcutKey(4)
    of SCANCODE_6:
      return handleShortcutKey(5)
    of SCANCODE_7:
      return handleShortcutKey(6)
    of SCANCODE_8:
      return handleShortcutKey(7)
    of SCANCODE_9:
      return handleShortcutKey(8)
    of SCANCODE_0:
      return handleShortcutKey(9)
    of SCANCODE_M:
      panic = not panic
    else:
      return false
  elif down:
    case scancode:
    of SCANCODE_F1:
      return handleShortcutKey(0)
    of SCANCODE_F2:
      return handleShortcutKey(1)
    of SCANCODE_F3:
      return handleShortcutKey(2)
    of SCANCODE_F4:
      return handleShortcutKey(3)
    of SCANCODE_F5:
      return handleShortcutKey(4)
    of SCANCODE_F6:
      return handleShortcutKey(5)
    of SCANCODE_F7:
      return handleShortcutKey(6)
    of SCANCODE_F8:
      return handleShortcutKey(7)
    of SCANCODE_F9:
      return handleShortcutKey(8)
    of SCANCODE_F10:
      return handleShortcutKey(9)
    else:
      return false
  return false


proc eventFunc(event: Event): bool =
  let ctrl = ctrl()
  let shift = shift()
  case event.kind:
  of ekKeyDown, ekKeyUp:
    let down = event.kind == ekKeyDown
    # handle global keys
    let scancode = event.scancode
    if handleShortcutKeys(event):
      return true
    if down:
      case scancode:
        of SCANCODE_SLASH:
          baseOctave -= 1
          if baseOctave < 0:
            baseOctave = 0
          return true
        of SCANCODE_APOSTROPHE:
          baseOctave += 1
          if baseOctave > 8:
            baseOctave = 8
          return true
        of SCANCODE_N:
          if ctrl:
            var menu = newMenu(mouseVec(), "new project?")
            menu.items.add(newMenuItem("no") do():
              popMenu()
            )
            menu.items[menu.items.high].status = Primary
            menu.items.add(newMenuItem("yes") do():
              newLayout()
              popMenu()
            )
            menu.items[menu.items.high].status = Danger
            pushMenu(menu)
            return true
        of SCANCODE_Q:
          if ctrl:
            var menu = newMenu(mouseVec(), "quit?")
            menu.items.add(newMenuItem("no") do():
              popMenu()
            )
            menu.items[menu.items.high].status = Primary
            menu.items.add(newMenuItem("yes") do():
              shutdown()
            )
            menu.items[menu.items.high].status = Danger
            pushMenu(menu)
            return true
        else:
          discard

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
  setAudioBufferSize(4096)

  invSampleRate = 1.0 / sampleRate

  loadSpriteSheet(0, "spritesheet.png")
  setSpritesheet(0)

  loadFont(0, "font.png")
  setFont(0)

  when defined(jack):
    var status: JackStatus
    J = jack_client_open("nimsynth", JackNullOption, status.addr)
    if J == nil:
      echo "error connecting to jack"
      shutdown()

    echo "starting client: ", jack_get_client_name(J)

    proc signalHandler() {.noconv.} =
      echo "signal recved exiting"
      discard jack_client_close(J)
      shutdown()
    setControlCHook(signalHandler)

    discard jack_set_process_callback(J, audioCallbackJack, nil)
    discard jack_set_sample_rate_callback(J, setSampleRate, nil)
    outputPort1 = jack_port_register(J, "out_1".cstring, JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput.culong, 0.culong)
    outputPort2 = jack_port_register(J, "out_2".cstring, JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput.culong, 0.culong)
    inputPort1 = jack_port_register(J, "in_1".cstring, JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput.culong, 0.culong)
    inputPort2 = jack_port_register(J, "in_2".cstring, JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput.culong, 0.culong)
    midiInputPort = jack_port_register(J, "midi_in".cstring, JACK_DEFAULT_MIDI_TYPE, JackPortIsInput.culong, 0.culong)
    discard jack_activate(J)

    # attempt to connect to system/playback_1,2
    discard jack_connect(J, "nimsynth:out_1", "system:playback_1")
    discard jack_connect(J, "nimsynth:out_2", "system:playback_2")

    # attempt to connect system input to our input
    discard jack_connect(J, "system:capture_1", "nimsynth:in_1")
    discard jack_connect(J, "system:capture_2", "nimsynth:in_2")

    # attempt to make all midi outputs connect to us
    var ports = cast[ptr array[int.high, cstring]](jack_get_ports(J, nil, JACK_DEFAULT_MIDI_TYPE, JackPortIsOutput.culong))
    if ports != nil:
      var i = 0
      while ports[i] != nil:
        discard jack_connect(J, ports[i], "nimsynth:midi_in")
        i += 1
      jack_free(ports)
    echo "connected to jack"
  else:
    echo "using SDL audio"
    setAudioCallback(0, audioCallback, true)

    proc signalHandler() {.noconv.} =
      echo "signal recved exiting"
      shutdown()
    setControlCHook(signalHandler)

  addEventListener(eventFunc)

  machines = newSeq[Machine]()
  menuStack = newSeq[Menu]()

  masterMachine = createMachine("master")
  machines.add(masterMachine)

  oscilliscopeBuffer = newRingBuffer[float32](1024)
  sampleMachine = masterMachine

  vLayoutView = newLayoutView()
  currentView = vLayoutView

  let arguments = commandLineParams()
  if arguments.len > 0:
    loadLayout(arguments[0])

proc update(dt: float32) =
  if currentView != nil:
    currentView.update(dt)

  for m in machines:
    m.update(dt)
    for input in mitems(m.inputs):
      input.peak *= 0.9

proc draw() =
  frame += 1
  var shortcut_w = (screenWidth - 64) / shortcuts.len;
  if currentView != nil:
    currentView.draw()

  # draw shortcut bar
  for i, v in shortcuts:
    if i == 0 or v != nil:
      setColor(1)
    else:
      setColor(0)
    rectfill(i * shortcut_w, screenHeight - 10, i * shortcut_w + (shortcut_w - 2), screenHeight - 1)

    if (i == 0 and currentView == vLayoutView) or (currentView of MachineView and v == MachineView(currentView).machine):
      setColor(7)
    elif i == 0 or v != nil:
      setColor(13)
    else:
      setColor(1)

    if i == 0 or v != nil:
      if i == 0:
        print($(i+1) & ":layout", i * shortcut_w + 2, screenHeight - 8)
      else:
        print($(i+1) & ":" & v.name, i * shortcut_w + 2, screenHeight - 8)

    rect(i * shortcut_w, screenHeight - 10, i * shortcut_w + (shortcut_w - 2), screenHeight - 1)

  let lastUpdated = getStatusUpdateTime() div 1000
  let now = time() div 1000
  setColor(if lastUpdated > now - 1: 7 elif lastUpdated > now - 5: 6 else: 1)
  printr(getStatus(), screenWidth - 1, screenHeight - 8)

  setCamera()

  if hasMenu():
    var menu = getMenu()
    menu.draw()

  let mv = mouseVec()
  spr(20, mv.x, mv.y)

  if glitch > 0.0:
    glitch = clamp(glitch,0.0,100.0)
    for i in 0..glitch.int:
      glitch(0,0,screenWidth,screenHeight)

nico.init("impbox","nimsynth")
nico.createWindow("nimsynth",1920 div 4,1200 div 4,3,false)

hideMouse()

nico.run(init, update, draw)

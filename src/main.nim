import pico
import sdl2

import strutils

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
import karp
import eq
import probgate
import probpick
import paramlp
import transposer
import keyboard
import dummy
import filerec

import locks

when defined(jack):
  import jack.types
  import jack.jack
  import jack.midiport

  import audioin

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
    var samplesL = cast[ptr array[int.high, float32]](jack_port_get_buffer(outputPort1, nframes))
    var samplesR = cast[ptr array[int.high, float32]](jack_port_get_buffer(outputPort2, nframes))

    var inputL = cast[ptr array[int.high, float32]](jack_port_get_buffer(inputPort1, nframes))
    var inputR = cast[ptr array[int.high, float32]](jack_port_get_buffer(inputPort2, nframes))

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
        withLock machineLock:
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
      withLock machineLock:
        for machine in mitems(machines):
          if machine.stereo or sampleId mod 2 == 0:
            machine.process()

      if i mod 2 == 0:
        samplesL[time] = masterMachine.outputSamples[0]
        if i < 2048:
          sampleBuffer[time] = samplesL[time]
      else:
        samplesR[time] = masterMachine.outputSamples[0]

  proc setSampleRate(nframes: jack_nframes, arg: pointer): cint =
    echo "sampleRate: ", nframes
    sampleRate = nframes.float
    invSampleRate = 1.0 / sampleRate
    nyquist = sampleRate / 2.0

else:

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
          var menu = newMenu(mouse(), "quit?")
          menu.items.add(newMenuItem("no") do():
            popMenu()
          )
          menu.items.add(newMenuItem("yes") do():
            shutdown()
          )
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
  loadSpriteSheet("spritesheet.png")

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
  else:
    setAudioCallback(2, audioCallback)

    proc signalHandler() {.noconv.} =
      echo "signal recved exiting"
      shutdown()
    setControlCHook(signalHandler)

  setEventFunc(eventFunc)

  machines = newSeq[Machine]()
  menuStack = newSeq[Menu]()

  masterMachine = newMaster()
  machines.add(masterMachine)

  vLayoutView = newLayoutView()
  currentView = vLayoutView

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

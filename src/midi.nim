import winim
import winim/extra
import tables

type MidiCommand* = enum
  mcNoteOff = 0x8
  mcNoteOn = 0x9
  mcNotePressure = 0xA
  mcControlChange = 0xB
  mcProgramChange = 0xC
  mcChannelPressure = 0xD
  mcPitchBend = 0xE

type MidiMessage* = object
  case command: MidiCommand
  of mcNoteOn,mcNoteOff,mcNotePressure:
    note: uint8
  of mcNoteOn,mcNoteOf:
    velocity: uint8
  of mcNotePressure:
    pressure: uint8
  of mcControlChange:
    control: uint8
    value: uint8
  of mcProgramChange:
    program: uint8
  of mcPitchBend:
    bend: uint16
  channel: uint8

type MidiInDevice = int
type MidiInCallback = proc(msg: MidiMessage)

type MIDIException = object of Exception

var midiDeviceToCallback = initTable[MidiInDevice, MidiInCallback]()

proc midiInGetDevices(): seq[string] =
  let nDevs = midiInGetNumDevs()
  var caps: MIDIINCAPS
  for i in 0..<nDevs:
    midiInGetDevCaps(i.uint32, caps.addr, sizeof(MIDIINCAPS).UINT)
    result.add($(-$caps.szPname))

proc midiInCallback(hMidiIn: HMIDIIN, wMsg: UINT, dwInstance: DWORD, dwMidiMessage: DWORD, timestamp: DWORD) =
  setupForeignThreadGC()

  case wMsg:
  of MIM_OPEN:
    echo "MIM_OPEN"
  of MIM_CLOSE:
    echo "MIM_CLOSE"
  of MIM_DATA:
    if dwMidiMessage == 248:
      # clock
      return
    let lowWord = (dwMidiMessage.uint32 and 0b0000_0000_0000_0000_1111_1111_1111_1111'u32).uint16
    let highWord = ((dwMidiMessage.uint32 and 0b1111_1111_1111_1111_0000_0000_0000_0000'u32) shr 16'u32).uint16
    let status = (lowWord and 0b1111_1111'u16).uint8
    let channel = status and 0b1111'u8
    let command = (status and 0b1111_0000'u8) shr 4'u8
    let data1 = ((lowWord and 0b1111_1111_0000_0000'u16) shr 8'u16).uint8
    let data2 = (highWord and 0b1111_1111'u16).uint8

    var msg = MidiMessage(command: command.MidiCommand)
    msg.channel = channel
    case msg.command:
    of mcNoteOn, mcNoteOff:
      msg.note = data1
      msg.velocity = data2
    of mcControlChange:
      msg.control = data1
      msg.value = data2
    of mcPitchBend:
      msg.bend = (data1 or (data2 shl 7))
    of mcProgramChange:
      msg.patch = data1

    let callback = midiDeviceToCallback[hMidiIn]
    callback(msg)

    #echo "wMsg=MIM_DATA, dwInstance={dwInstance}, dwMidiMessage={dwMidiMessage}, timestamp={timestamp}".fmt()
    #case command:
    #  of 0x9:
    #    echo "NOTE ON  ", data1, " vel: ", data2
    #  of 0x8:
    #    echo "NOTE OFF ", data1
    #  of 0xB:
    #    echo "CC ", data1, " = ", data2, " "
    #  of 0xC:
    #    echo "PATCH ", data1
    #  of 0xE:
    #    echo "PB ", (data1 or (data2 shl 7)), " "
    #  else:
    #    echo command, " ", data1, " ", channel
  of MIM_LONGDATA:
    echo "MIM_LONGDATA"
  of MIM_ERROR:
    echo "MIM_ERROR"
  of MIM_LONGERROR:
    echo "MIM_LONGERROR"
  of MIM_MOREDATA:
    echo "MIM_MOREDATA"
  else:
    echo "MIM_UNKNOWN ", wMsg

proc midiInOpen(port: int, callback: MidiInCallback): MidiInDevice =
  var hMidiDevice: HMIDIIN = 0

  var rv = midiInOpen(&hMidiDevice, port.UINT, cast[DWORD_PTR](midiInCallback), 0, CALLBACK_FUNCTION)
  midiDeviceToCallback[hMidiDevice] = callback
  if rv != MMSYSERR_NOERROR:
    raise newException(MIDIException, "error opening midi port " & $port)
  midiInStart(hMidiDevice)

  return hMidiDevice

proc midiInClose(dev: MidiInDevice) =
  midiInStop(dev)
  winim.extra.midiInClose(dev)

proc run() =
  for i, devName in midiInGetDevices():
    echo i, ": ", devName
    let dev = midiInOpen(i, proc(msg: MidiMessage) =
      if msg.command == mcNoteOn:
        echo "noteOn ", msg.note, " vel: ", msg.velocity
      echo msg.command
    )

  while true:
    discard

run()

{.link: "librtmidi.dll"}

type
  RtMidiWrapper* = object
    `ptr`: pointer
    data: pointer
    ok: bool
    msg: cstring
  RtMidiPtr* = ptr RtMidiWrapper
  RtMidiInPtr* = ptr RtMidiWrapper
  RtMidiOutPtr* = ptr RtMidiWrapper

  RtMidiApi* {.pure.} = enum
    Unspecified,
    Core,
    Alsa,
    Jack,
    MM,
    Dummy,
    Num

  RtMidiErrorType* {.pure.} = enum
    Warning,
    DebugWarning,
    Unspecified,
    NoDevicesFound,
    InvalidDevice,
    MemoryError,
    InvalidParameter,
    InvalidUse,
    DriverError,
    SystemError,
    ThreadError

  RtMidiCCallback* = proc(timestamp: cdouble, message: ptr cuchar, messageSize: csize, userData: pointer) {.cdecl.}

proc rtmidiGetCompiledAPI*(apis: ptr RtMidiApi, apis_size: int): int {.importc:"rtmidi_get_compiled_api".}
proc rtmidiApiName*(api: RtMidiApi): cstring {.importc:"rtmidi_api_name".}
proc rtmidiDisplayApiName*(api: RtMidiApi): cstring {.importc:"rtmidi_api_display_name".}
proc rtmidiOpenPort*(device: RtMidiPtr, portNumber: cuint, portName: cstring) {.importc:"rtmidi_open_port".}
proc rtmidiOpenVirtualPort*(device: RtMidiPtr, portName: cstring) {.importc:"rtmidi_open_virtual_port".}
proc rtmidiClosePort*(device: RtMidiPtr) {.importc:"rtmidi_close_port".}
proc rtmidiGetPortCount*(device: RtMidiPtr): cuint {.importc:"rtmidi_get_port_count".}
proc rtmidiGetPortName*(device: RtMidiPtr, portNumber: cuint): cstring {.importc:"rtmidi_get_port_name".}
proc rtmidiInCreateDefault*(): RtMidiPtr {.importc:"rtmidi_in_create_default".}
proc rtmidiInCreate*(api: RtMidiApi, clientName: cstring, queueSizeLimit: cuint): RtMidiPtr {.importc:"rtmidi_in_create".}
proc rtmidiInSetCallback*(device: RtMidiPtr, callback: RtMidiCCallback, userData: pointer) {.importc:"rtmidi_in_set_callback".}

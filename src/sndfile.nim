when defined(windows):
    const soname = "libsndfile.dll"
elif defined(macosx):
    const soname = "libsndfile.dylib"
else:
    const soname = "libsndfile.so(|.1)"

{.pragma: libsnd, cdecl, dynlib: soname.}

type
  TSNDFILE* = cint

  TFILE_MODE* = enum
      READ    = cint(0x10),
      WRITE   = cint(0x20),
      RDWR    = cint(0x30)

  TCOUNT* = int64

  TINFO* {.pure final.} = object
      frames*: TCOUNT
      samplerate*: cint
      channels*: cint
      format*: cint
      sections*: cint
      seekable*: cint

  TBOOL* = enum
      SF_FALSE    = 0
      SF_TRUE     = 1

  TWHENCE* = enum
      SEEK_SET    = 0 # The offset is set to the start of the audio data plus offset (multichannel) frames.
      SEEK_CUR    = 1 # The offset is set to its current location plus offset (multichannel) frames.
      SEEK_END    = 2  # The offset is set to the end of the data plus offset (multichannel) frames.
  
  TCOMMAND* = enum
        SFC_GET_LIB_VERSION             = 0x1000
        SFC_GET_LOG_INFO                = 0x1001
        SFC_GET_CURRENT_SF_INFO         = 0x1002
        SFC_GET_NORM_DOUBLE             = 0x1010
        SFC_GET_NORM_FLOAT              = 0x1011
        SFC_SET_NORM_DOUBLE             = 0x1012
        SFC_SET_NORM_FLOAT              = 0x1013
        SFC_SET_SCALE_FLOAT_INT_READ    = 0x1014
        SFC_SET_SCALE_INT_FLOAT_WRITE   = 0x1015
        SFC_GET_SIMPLE_FORMAT_COUNT     = 0x1020
        SFC_GET_SIMPLE_FORMAT           = 0x1021
        SFC_GET_FORMAT_INFO             = 0x1028
        SFC_GET_FORMAT_MAJOR_COUNT      = 0x1030
        SFC_GET_FORMAT_MAJOR            = 0x1031
        SFC_GET_FORMAT_SUBTYPE_COUNT    = 0x1032
        SFC_GET_FORMAT_SUBTYPE          = 0x1033
        SFC_CALC_SIGNAL_MAX             = 0x1040
        SFC_CALC_NORM_SIGNAL_MAX        = 0x1041
        SFC_CALC_MAX_ALL_CHANNELS       = 0x1042
        SFC_CALC_NORM_MAX_ALL_CHANNELS  = 0x1043
        SFC_GET_SIGNAL_MAX              = 0x1044
        SFC_GET_MAX_ALL_CHANNELS        = 0x1045
        SFC_SET_ADD_PEAK_CHUNK          = 0x1050
        SFC_SET_ADD_HEADER_PAD_CHUNK    = 0x1051
        SFC_UPDATE_HEADER_NOW           = 0x1060
        SFC_SET_UPDATE_HEADER_AUTO      = 0x1061
        SFC_FILE_TRUNCATE               = 0x1080
        SFC_SET_RAW_START_OFFSET        = 0x1090
        SFC_SET_DITHER_ON_WRITE         = 0x10A0
        SFC_SET_DITHER_ON_READ          = 0x10A1
        SFC_GET_DITHER_INFO_COUNT       = 0x10A2
        SFC_GET_DITHER_INFO             = 0x10A3
        SFC_GET_EMBED_FILE_INFO         = 0x10B0
        SFC_SET_CLIPPING                = 0x10C0
        SFC_GET_CLIPPING                = 0x10C1
        SFC_GET_INSTRUMENT              = 0x10D0
        SFC_SET_INSTRUMENT              = 0x10D1
        SFC_GET_LOOP_INFO               = 0x10E0
        SFC_GET_BROADCAST_INFO          = 0x10F0
        SFC_SET_BROADCAST_INFO          = 0x10F1
        SFC_GET_CHANNEL_MAP_INFO        = 0x1100
        SFC_SET_CHANNEL_MAP_INFO        = 0x1101
        SFC_RAW_DATA_NEEDS_ENDSWAP      = 0x1110
        SFC_WAVEX_SET_AMBISONIC         = 0x1200
        SFC_WAVEX_GET_AMBISONIC         = 0x1201
        SFC_SET_VBR_ENCODING_QUALITY    = 0x1300

const SF_FORMAT_WAV*    = 0x010000
const SF_FORMAT_PCM_8*  = 0x0001
const SF_FORMAT_PCM_16* = 0x0002
const SF_FORMAT_FLOAT*  = 0x0006

proc open*(path: cstring, mode: TFILE_MODE, sfinfo: ptr TINFO): ptr TSNDFILE  {.libsnd, importc: "sf_open".}
proc close*(sndfile: ptr TSNDFILE): cint {.libsnd, importc: "sf_close".}

proc format_check*(info: ptr TINFO): TBOOL {.libsnd, importc: "sf_format_check".}

proc seek*(sndfile: ptr TSNDFILE, frames: TCOUNT, whence: TWHENCE): TCOUNT {.libsnd, importc: "sf_seek".}

proc command*(sndfile: ptr TSNDFILE, cmd: TCOMMAND, data: pointer, datasize: cint): cint {.libsnd, importc: "sf_command".}

proc error*(sndfile: ptr TSNDFILE): cint {.libsnd, importc: "sf_error".}

proc strerror*(sndfile: ptr TSNDFILE): cstring {.libsnd, importc: "sf_strerror".}

proc read_short*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cshort, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_read_short".}
proc read_int*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cint, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_read_int".}
proc read_float*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cfloat, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_read_float".}
proc read_double*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cdouble, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_read_double".}

proc readf_short*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cshort, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_readf_short".}
proc readf_int*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cint, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_readf_int".}
proc readf_float*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cfloat, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_readf_float".}
proc readf_double*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cdouble, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_readf_double".}

proc write_short*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cshort, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_write_short".}
proc write_int*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cint, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_write_int".}
proc write_float*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cfloat, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_write_float".}
proc write_double*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cdouble, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_write_double".}

proc writef_short*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cshort, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_writef_short".}
proc writef_int*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cint, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_writef_int".}
proc writef_float*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cfloat, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_writef_float".}
proc writef_double*(sndfile: ptr TSNDFILE, buffer_ptr: ptr cdouble, items: TCOUNT): TCOUNT {.libsnd, importc: "sf_writef_double".}

proc write_sync*(sndfile: ptr TSNDFILE) {.libsnd, importc: "sf_write_sync".}

when isMainModule:
    var info: TINFO
    var sndfile: ptr TSNDFILE
    info.format = 0

    snd_file = open("test.wav", READ, cast[ptr TINFO](info.addr))
    
    echo info
    # expect info to match snd file header
    echo format_check(cast[ptr TINFO](info.addr))
    
    # expect 5
    echo seek(snd_file, 5, SEEK_SET)
    discard seek(snd_File, 0, SEEK_SET)
    
    let num_items = cast[cint](info.channels * info.frames)
    echo num_items
    var buffer = newSeq[cint](num_items)
    let items_read = read_int(snd_file, buffer[0].addr, num_items)
    echo items_read


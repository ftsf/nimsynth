import common
import pico
import util
import basemachine

import sndfile

{.this:self.}

type FileRec = ref object of Machine
  filename: string
  recording: bool
  file: ptr TSNDFILE
  lastSample: cfloat


method init(self: FileRec) =
  procCall init(Machine(self))

  nInputs = 1
  nOutputs = 0
  stereo = true

  name = "filerec"

  self.filename = "out.wav"

  self.globalParams.add([
    Parameter(name: "record", kind: Trigger, min: 0.0, max: 1.0, default: 0.0, onchange: proc(newValue: float, voice: int) =
      self.recording = newValue.bool
      if self.recording:
        # open file
        var sfinfo: TINFO
        sfinfo.samplerate = samplerate
        sfinfo.channels = 2
        sfinfo.format = (SF_FORMAT_WAV or SF_FORMAT_FLOAT)
        self.file = open(self.filename.cstring, WRITE, sfinfo.addr)
        if self.file != nil:
          echo "file opened for writing: ", self.filename
        else:
          echo "error opening file for writing: ", self.filename
          echo strerror(nil)
          self.recording = false
      else:
        # close file if it was open
        if self.file != nil:
          self.file = nil
          self.recording = false
    ),
  ])

  setDefaults()

method process(self: FileRec) {.inline.} =
  let sample = getInput()
  if sampleId mod 2 == 1 and self.file != nil:
      var data: array[2, cfloat] = [lastSample, sample]
      let ret = self.file.writef_float(data[0].addr, 1)
      if ret != 1:
        echo "error writing data"
        self.file = nil
        self.recording = false
  lastSample = sample

method drawBox(self: FileRec) =
  setColor(if recording: 8 else: 2)
  rectfill(getAABB())
  setColor(6)
  rect(getAABB())
  printc(name, pos.x, pos.y - 2)

proc newFileRec(): Machine =
  var m = new(FileRec)
  m.init()
  return m

registerMachine("filerec", newFileRec, "util")

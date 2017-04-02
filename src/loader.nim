import dynlib
import common

type MachineFactory = proc(): Machine {.cdecl.}

type ProcessSampleFunc = proc(machine: Machine): void {.cdecl.}

var lib = loadLib("./libosc.so")
if lib != nil:
  echo "loaded lib"

  let createMachinePtr = lib.symAddr("createMachine")
  let createMachine = cast[MachineFactory](createMachinePtr)
  let processSamplePtr = lib.symAddr("processSample")
  let processSample = cast[ProcessSampleFunc](processSamplePtr)

  assert(createMachine != nil)
  assert(processSample != nil)

  if createMachine != nil:
    echo "got address of createMachine: ", cast[int](createMachine)
    var m = createMachine()
    echo "called createMachine"
    echo m.name
    for i in 0..1000:
      processSample(m)
      echo m.outputSamples[0]
  else:
    echo "no createMachine defined"
else:
  echo "error loading lib"

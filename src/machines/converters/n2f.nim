import common

# converts note int to float32

{.this:self.}

type
  NoteMachine = ref object of Machine

method init(self: NoteMachine) =
  procCall init(Machine(self))
  name = "n2f"
  nInputs = 0
  nOutputs = 0
  stereo = false

  nBindings = 1

  bindings = newSeq[Binding](1)

  globalParams.add([
    Parameter(kind: Note, name: "note", min: 0, max: 127, onchange: proc(newValue: float32, voice: int) =
      if newValue != OffNote:
        if bindings[0].isBound():
          var (voice, param) = bindings[0].getParameter()
          param.value = newValue.noteToHz()
          param.onchange(param.value, voice)
    , getValueString: proc(value: float32, voice: int): string =
      return noteToNoteName(value.int)
    ),
  ])

  setDefaults()

proc newNoteMachine(): Machine =
 var m = new(NoteMachine)
 m.init()
 return m

registerMachine("n2f", newNoteMachine, "convert")

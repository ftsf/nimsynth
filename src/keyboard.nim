import common

type Keyboard = ref object of Machine
  baseOctave: int
  noteBuffer: seq[int]

{.this:self.}

method init*(self: Keyboard) =
  procCall init(Machine(self))

  name = "keyboard"
  nOutputs = 0
  nInputs = 0
  nBindings = 1
  bindings.setLen(1)

  globalParams.add([
    Parameter(kind: Int, name: "oct", min: 0.0, max: 12.0, default: 4.0, onchange: proc(newValue: float, voice: int) =
      self.baseOctave = newValue.int
    )
  ])

  setDefaults()

proc newKeyboard(): Machine =
  var k = new(Keyboard)
  k.init()
  return k

method trigger(self: Keyboard, note: int) =
  if bindings[0].machine != nil:
    var targetMachine = bindings[0].machine
    var (voice,param) = bindings[0].getParameter()
    param.value = note.float
    param.onchange(param.value, voice)

method release(self: Keyboard, note: int) =
  if bindings[0].machine != nil:
    var targetMachine = bindings[0].machine
    var (voice,param) = bindings[0].getParameter()
    param.value = OffNote.float
    param.onchange(param.value, voice)

registerMachine("keyboard", newKeyboard)

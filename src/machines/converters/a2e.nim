import common

{.this:self.}

type
  A2EMachine = ref object of Machine

# takes audio input and outputs an event

method init(self: A2EMachine) =
  procCall init(Machine(self))
  name = "a2e"
  nInputs = 1
  nOutputs = 0
  stereo = false

  nBindings = 1
  bindings = newSeq[Binding](1)

  setDefaults()

method process(self: A2EMachine) =
  if bindings[0].isBound():
    let value = getInput()
    var (voice, param) = bindings[0].getParameter()
    param.value = value
    param.onchange(value, voice)

proc newA2E(): Machine =
  var m = new(A2EMachine)
  m.init()
  return m

registerMachine("a2e", newA2E, "convert")

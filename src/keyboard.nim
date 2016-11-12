import common

const polyphony = 16

type Keyboard = ref object of Machine
  baseOctave: int
  noteBuffer: array[polyphony, tuple[note: int, age: int]]

{.this:self.}

method init*(self: Keyboard) =
  procCall init(Machine(self))

  name = "keyboard"
  nOutputs = 0
  nInputs = 0
  nBindings = polyphony * 2
  bindings.setLen(nBindings)
  useMidi = true
  midiChannel = 0

  for i in 0..<polyphony:
    noteBuffer[i].note = OffNote

  setDefaults()

method process*(self: Keyboard) =
  discard

method midiEvent*(self: Keyboard, event: MidiEvent) =
  if event.command == 1:
    var done = false
    for i in 0..<polyphony:
      if noteBuffer[i].note != OffNote:
        noteBuffer[i].age += 1

    for i in 0..<polyphony:
      if noteBuffer[i].note == OffNote:
        noteBuffer[i].note = event.data1.int
        noteBuffer[i].age = 0

        if bindings[i*2].isBound:
          var (voice,param) = bindings[i*2].getParameter()
          param.value = event.data1.float
          param.onchange(param.value, voice)

        if bindings[i*2+1].isBound:
          var (voice,param) = bindings[i*2+1].getParameter()
          param.value = event.data2.float / 127.0
          param.onchange(param.value, voice)

        done = true
        break
    if not done:
      # find oldest note and replace it
      var oldestAge = 0
      var oldestVoice = 0
      for i in 0..<polyphony:
        if noteBuffer[i].age > oldestAge:
          oldestAge = noteBuffer[i].age
          oldestVoice = i

      noteBuffer[oldestVoice].note = event.data1.int
      noteBuffer[oldestVoice].age = 0
      if bindings[oldestVoice*2].isBound:
        var (voice,param) = bindings[oldestVoice*2].getParameter()
        param.value = event.data1.float
        param.onchange(param.value, voice)

      if bindings[oldestVoice*2+1].isBound:
        var (voice,param) = bindings[oldestVoice*2+1].getParameter()
        param.value = event.data2.float / 127.0
        param.onchange(param.value, voice)

  elif event.command == 0:
    for i in 0..<polyphony:
      if noteBuffer[i].note == event.data1.int:
        noteBuffer[i].note = OffNote
        if bindings[i*2].isBound:
          var (voice,param) = bindings[i*2].getParameter()
          param.value = OffNote
          param.onchange(param.value, voice)

proc newKeyboard(): Machine =
  var k = new(Keyboard)
  k.init()
  return k

registerMachine("keyboard", newKeyboard, "util")

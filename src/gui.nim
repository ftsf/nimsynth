{.this:self.}

type
  GuiObject* = object of RootObj
    discard
  Knob* = object of GuiObject
    min*,max*: float
    value*: float
    default*: float
    step*: float
    onchange*: proc(newValue: float) {.locks: 0.}
    getValueString*: proc(value: float): string {.locks: 0.}
    label*: string
  GuiGroup* = object of GuiObject
    label*: string
    vertical*: bool
    items*: seq[GuiObject]

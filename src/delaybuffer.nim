{.this:self.}

type
  DelayBuffer*[T] = object of RootObj
    buffer: seq[T]
    writeHead: int

proc setLen*[T](self: var DelayBuffer[T], length: int) =
  if self.buffer == nil:
    self.buffer = newSeq[T](max(length,1))
  else:
    self.buffer.setLen(max(length,1))
  self.writeHead = self.writeHead mod self.buffer.len

proc len*[T](self: DelayBuffer[T]): int =
  return self.buffer.len

proc write*[T](self: var DelayBuffer[T], value: T) =
  self.buffer[self.writeHead] = value
  self.writeHead += 1
  self.writeHead = self.writeHead mod self.buffer.len

proc read*[T](self: var DelayBuffer[T]): T =
  let readHead = (self.writeHead + 1) mod self.buffer.len
  result = self.buffer[readHead]

proc poke*[T](self: var DelayBuffer[T], value: T) =
  # write but don't advance head
  self.buffer[self.writeHead] = value

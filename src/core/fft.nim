import complex
import math

proc toComplex(x: float): TComplex = result.re = x

proc fft[T](x: openarray[T]): seq[TComplex] =
  let n = x.len
  result = newSeq[TComplex]()
  if n <= 1:
    for v in x: result.add toComplex(v)
    return
  var evens,odds = newSeq[T]()
  for i,v in x:
    if i mod 2 == 0: evens.add(v)
    else: odds.add(v)
  var (even, odd) = (fft(evens), fft(odds))

  for k in 0..<n div 2:
    result.add(even[k] + exp((0.0, -2.0*PI*float(k)/float(n))) * odd[k])

  for k in 0..<n div 2:
    result.add(even[k] - exp((0.0, -2.0*PI*float(k)/float(n))) * odd[k])

proc generateImpulse*(points: int): seq[float32] =
  result = newSeq[float32](points)
  for i in 0..<points:
    result[i] = if i == 0: 1.0 else: 0.0

proc graphResponse*(timeDomain: openarray[float32], points: int): seq[float] =
  var res = fft(timeDomain)
  result = newSeq[float](points)
  for i in 0..<points:
    result[i] = res[i].re

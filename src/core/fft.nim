import complex
import math

proc toComplex[T](x: T): Complex[T] =
  result.re = x

proc fft[T](x: openarray[T]): seq[Complex[T]] =
  let n = x.len
  result = newSeq[Complex[T]]()
  if n <= 1:
    for v in x: result.add toComplex(v)
    return
  var evens,odds = newSeq[T]()
  for i,v in x:
    if i mod 2 == 0: evens.add(v)
    else: odds.add(v)
  var (even, odd) = (fft(evens), fft(odds))

  for k in 0..<n div 2:
    result.add(even[k] + exp(complex(T(0.0), T(-2.0)*T(PI)*T(k)/T(n))) * odd[k])

  for k in 0..<n div 2:
    result.add(even[k] - exp(complex(T(0.0), T(-2.0)*T(PI)*T(k)/T(n))) * odd[k])

proc generateImpulse*(points: int): seq[float32] =
  result = newSeq[float32](points)
  for i in 0..<points:
    result[i] = if i == 0: 1.0 else: 0.0

proc graphResponse*(timeDomain: openarray[float32], points: int): seq[float32] =
  var res = fft(timeDomain)
  result = newSeq[float32](points)
  for i in 0..<points:
    result[i] = res[i].re

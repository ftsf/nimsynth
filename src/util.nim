import basic2d
import pico
import math
import strutils

const metresPerPixel* = 1.0/8.0

type
  Polygon* = seq[Point2d]
  Triangle* = array[3, Point2d]
  Quad* = array[4, Point2d]
  Line* = array[2, Point2d]
  Rect* = tuple[x,y,w,h: int]

proc `*`*(v: Point2d, s: float): Point2d =
  return point2d(v.x*s,v.y*s)

proc `/`*(a: Point2d,s: float): Point2d =
  return point2d(a.x/s,a.y/s)

proc `+`*(a,b: Point2d): Point2d =
  return point2d(a.x+b.x,a.y+b.y)

proc `-`*(v: Point2d): Point2d =
  return point2d(-v.x, -v.y)

proc isZero*(v: Vector2d): bool =
  return v.x == 0 and v.y == 0

proc rndVec*(mag: float): Vector2d =
  let hm = mag/2
  vector2d(
    rnd(mag)-hm,
    rnd(mag)-hm
  )

proc line*(line: Line) =
  let a = line[0]
  let b = line[1]
  line(a.x.int,a.y.int,b.x.int,b.y.int)

proc toVector2d*(p: Point2d): Vector2d =
  result.x = p.x
  result.y = p.y

proc toPoint2d*(p: Vector2d): Point2d =
  result.x = p.x
  result.y = p.y

proc poly*(verts: Polygon | Triangle | Quad) =
  if verts.len == 1:
    pset(verts[0])
  elif verts.len == 2:
    line(verts[0],verts[1])
  else:
    for i in 0..verts.high:
      line(verts[i],verts[(i+1) mod verts.len])

proc normalized*(v: Vector2d): Vector2d =
  let m = v.len()
  if m == 0:
    return v
  return vector2d(v.x/m, v.y/m)

proc perpendicular*(v: Vector2d): Vector2d =
  return vector2d(-v.y, v.x)

proc rotated*(v: Vector2d, angle: float): Vector2d =
  var v = v
  v.rotate(angle)
  return v

proc lerp*[T](a, b: T, t: float): T {.inline.} =
  return a + (b - a) * t

proc invLerp*[T](a, b: T, t: T): float {.inline.} =
  return (t - a) / (b - a)

proc trifill*(tri: Triangle | Polygon) =
  trifill(tri[0],tri[1],tri[2])

proc circfill*(p: Point2d, r: float) =
  circfill(p.x,p.y,r)

proc rotatePoint*(p: Point2d, angle: float, o = point2d(0,0)): Point2d =
  point2d(
    cos(angle) * (p.x - o.x) - sin(angle) * (p.y - o.y) + o.x,
    sin(angle) * (p.x - o.x) + cos(angle) * (p.y - o.y) + o.y
  )

proc rotatedPoly*(offset: Point2d, verts: openArray[Point2d], angle: float, origin = point2d(0,0)): Polygon =
  var p = newSeq[Point2d](verts.len())
  for i in 0..verts.high:
    let v = offset + rotatePoint(verts[i],angle,origin)
    p[i] = v
  return p

proc pointInPoly*(p: Point2d, poly: Polygon | Triangle | Quad): bool =
  let px = p.x
  let py = p.y
  let nvert = poly.len()

  var c = false
  var j = nvert-1
  for i in 0..nvert-1:
    j = (i+1) %% nvert
    if (poly[i].y > py) != (poly[j].y > py) and px < (poly[j].x - poly[i].x) * (py - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x:
      c = not c
  return c

type AABB* = tuple[min: Point2d, max: Point2d]

proc rectfill*(aabb: AABB) =
  rectfill(aabb.min.x.int, aabb.min.y.int, aabb.max.x.int, aabb.max.y.int)

proc rect*(aabb: AABB) =
  rect(aabb.min.x.int, aabb.min.y.int, aabb.max.x.int, aabb.max.y.int)

proc getAABB*(p: Point2d, expand: float): AABB =
  result.min.x = p.x - expand
  result.min.y = p.y - expand
  result.max.x = p.x + expand
  result.max.y = p.y + expand

proc getAABB*(poly: Triangle | Polygon): AABB =
  var aabb: AABB
  aabb.min.x = Inf
  aabb.min.y = Inf
  aabb.max.x = NegInf
  aabb.max.y = NegInf
  for v in poly:
    aabb.min.x = min(aabb.min.x, v.x)
    aabb.min.y = min(aabb.min.y, v.y)
    aabb.max.x = max(aabb.max.x, v.x)
    aabb.max.y = max(aabb.max.y, v.y)
  return aabb

proc getAABB*(a, b: Point2d): AABB =
  result.min.x = min(a.x,b.x)
  result.min.y = min(a.y,b.y)
  result.max.x = max(a.x,b.x)
  result.max.y = max(a.y,b.y)

proc getAABB*(l: Line): AABB =
  return getAABB(l[0], l[1])

proc expandAABB*(aabb: AABB, vel: Vector2d): AABB =
  result.min.x = aabb.min.x - abs(vel.x)
  result.max.x = aabb.max.x + abs(vel.x)
  result.min.y = aabb.min.y - abs(vel.y)
  result.max.y = aabb.max.y + abs(vel.y)

proc expandAABB*(aabb: AABB, expand: float): AABB =
  result.min.x = aabb.min.x - expand
  result.max.x = aabb.max.x + expand
  result.min.y = aabb.min.y - expand
  result.max.y = aabb.max.y + expand


proc shuffle*[T](x: var seq[T]) =
  for i in countdown(x.high, 0):
    let j = rnd(i+1)
    swap(x[i], x[j])

proc rnd*[T](x: seq[T]): T =
  let r = rnd(x.len)
  return x[r]

proc intersects*(a, b: AABB): bool =
  return not ( a.min.x > b.max.x or a.min.y > b.max.y or a.max.x < b.min.x or a.max.y < b.min.y )

proc sideOfLine*(v1, v2, p: Point2d): float =
  let px = p.x
  let py = p.y
  return (px - v1.x) * (v2.y - v1.y) - (py - v1.y) * (v2.x - v1.x)

type
  ABC = tuple[a,b,c: float]

proc lineToABC(line: Line): ABC =
  let x1 = line[0].x
  let x2 = line[1].x
  let y1 = line[0].y
  let y2 = line[1].y

  let A = y2 - y1
  let B = x1 - x2
  let C = A*x1 + B*y1

  return (A, B, C)

proc lineLineIntersection*(l1, l2: Line): (bool, Point2d) =
  let L1 = lineToABC(l1)
  let L2 = lineToABC(l2)

  let det = L1.a*L2.b - L2.a*L1.b
  if det == 0:
    # parallel
    return (false,point2d(0,0))
  else:
    let x = (L2.b*L1.c - L1.b*L2.c)/det
    let y = (L1.a*L2.c - L2.a*L1.c)/det
    # check if x,y is on line
    return (true,point2d(x,y))

proc lineSegmentIntersection*(l1, l2: Line): (bool,Point2d) =
  let ret = lineLineIntersection(l1,l2)
  let p = ret[1]
  let collide = min(l1[0].x,l1[1].x) <= p.x and p.x <= max(l1[0].x,l1[1].x) and
    min(l1[0].y,l1[1].y) <= p.y and p.y <= max(l1[0].y,l1[1].y) and
    min(l2[0].x,l2[1].x) <= p.x and p.x <= max(l2[0].x,l2[1].x) and
    min(l2[0].y,l2[1].y) <= p.y and p.y <= max(l2[0].y,l2[1].y)
  if collide:
    return (collide, p)
  else:
    return (collide, point2d(0,0))

proc normal*(v: var Vector2d) =
  v.normalize()
  v.rotate90()

proc normal*(v: Vector2d): Vector2d =
  var v = v
  v.normalize()
  v.rotate90()
  return v

proc printShadowC*(text: string, x, y: int, scale: int = 1) =
  let oldColor = getColor()
  setColor(0)
  printc(text, x-scale, y, scale)
  printc(text, x+scale, y, scale)
  printc(text, x, y-scale, scale)
  printc(text, x, y+scale, scale)
  printc(text, x+scale, y+scale, scale)
  printc(text, x-scale, y-scale, scale)
  printc(text, x+scale, y-scale, scale)
  printc(text, x-scale, y+scale, scale)
  setColor(oldColor)
  printc(text, x, y, scale)

proc printShadowR*(text: string, x, y: int, scale: int = 1) =
  let oldColor = getColor()
  setColor(0)
  printr(text, x-scale, y, scale)
  printr(text, x+scale, y, scale)
  printr(text, x, y-scale, scale)
  printr(text, x, y+scale, scale)
  printr(text, x+scale, y+scale, scale)
  printr(text, x-scale, y-scale, scale)
  printr(text, x+scale, y-scale, scale)
  printr(text, x-scale, y+scale, scale)
  setColor(oldColor)
  printr(text, x, y, scale)

proc printShadow*(text: string, x, y: int, scale: int = 1) =
  let oldColor = getColor()
  setColor(0)
  print(text, x-scale, y, scale)
  print(text, x+scale, y, scale)
  print(text, x, y-scale, scale)
  print(text, x, y+scale, scale)
  print(text, x+scale, y+scale, scale)
  print(text, x-scale, y-scale, scale)
  print(text, x+scale, y-scale, scale)
  print(text, x-scale, y+scale, scale)
  setColor(oldColor)
  print(text, x, y, scale)

proc pointInAABB*(p: Point2d, a: AABB): bool =
  return  p.x > a.min.x and p.x < a.max.x and
          p.y > a.min.y and p.y < a.max.y

proc `in`*(p: Point2d, a: AABB): bool =
  return pointInAABB(p, a)

proc pointInRect*(p: Point2d, r: Rect): bool =
  return  p.x > r.x and p.x < r.x + r.w - 1 and
          p.y > r.y and p.y < r.y + r.h - 1

proc pointInTile*(p: Point2d, x, y: int): bool =
  return pointInAABB(p, (point2d(x.float*8.0,y.float*8.0),point2d(x.float*8+7,y.float*8+7)))

proc floatToTimeStr*(time: float): string =
  let sign = if time < 0: "-" else: ""
  let time = abs(time)
  let minutes = int(time/60)
  let seconds = int(time - float(minutes*60))
  let ms = int(time mod 1.0 * 1000)
  return "$1$2:$3.$4".format(sign,($minutes).align(2,'0'),($seconds).align(2,'0'),($ms).align(3,'0'))

proc bezierQuadratic*(s, e, cp: Point2d, mu: float): Point2d =
  let mu2 = mu * mu
  let mum1 = 1 - mu
  let mum12 = mum1 * mum1

  return point2d(
    s.x * mum12 + 2 * cp.x * mum1 * mu + e.x * mu2,
    s.y * mum12 + 2 * cp.y * mum1 * mu + e.y * mu2
  )

proc bezierQuadraticLength*(s, e, cp: Point2d, steps: int): float =
  var l = 0.0
  var v = s
  var next: Point2d
  for i in 0..steps-1:
    next = bezierQuadratic(s,e,cp,float(i)/float(steps))
    if i > 0:
      l += (next - v).len()
      v = next
  return l

proc bezierCubic*(p1, p2, p3, p4: Point2d, mu: float): Point2d =
  let mum1 = 1 - mu
  let mum13 = mum1 * mum1 * mum1
  let mu3 = mu * mu * mu

  return point2d(
    p1.x * mum13 + 3*mu*mum1*mum1*p2.x + 3*mu*mu*mum1*p3.x + mu3*p4.x,
    p1.y * mum13 + 3*mu*mum1*mum1*p2.y + 3*mu*mu*mum1*p3.y + mu3*p4.y,
  )

proc bezierCubicLength*(s, e, cp1, cp2: Point2d, steps: int): float =
  var l = 0.0
  var v = s
  var next: Point2d
  for i in 0..steps-1:
    next = bezierCubic(s,e,cp1,cp2,float(i)/float(steps))
    if i > 0:
      l += (next - v).len()
      v = next
  return l

proc closestPointOnLine*(line: Line, p: Point2d): Point2d =
  let l2 = (line[0] - line[1]).sqrLen()
  if l2 == 0.0:
    return line[0]
  let t = max(0.0, min(1.0, dot(p-line[0], line[1] - line[0]) / l2))
  return line[0] + t * (line[1] - line[0])

proc lineSegDistanceSqr*(line: Line, p: Point2d): float =
  let proj = closestPointOnLine(line, p)
  return (p - proj).sqrLen()

proc lineSegDistance*(line: Line, p: Point2d): float =
  return sqrt(lineSegDistanceSqr(line, p))

template alias*(a,b: expr): expr =
  template a: expr = b

proc `%%/`*[T](x,m: T): T =
  return (x mod m + m) mod m

proc modDiff*[T](a,b,m: T): T  =
  let a = a %%/ m
  let b = b %%/ m
  return min(abs(a-b), m - abs(a-b))

proc modSign[T](a,n: T): T =
  return (a mod n + n) mod n

proc angleDiff*(a,b: float): float =
  let a = modSign(a,TAU)
  let b = modSign(b,TAU)
  return modSign((a - b) + PI, TAU) - PI

proc ordinal*(x: int): string =
  if x == 10:
    return "11TH"
  elif x == 11:
    return "12TH"
  elif x == 12:
    return "13TH"
  elif x mod 10 == 0:
    return $(x+1) & "ST"
  elif x mod 10 == 1:
    return $(x+1) & "ND"
  elif x mod 10 == 2:
    return $(x+1) & "RD"
  else:
    return $(x+1) & "TH"

proc wrap*[T](x,min,max: T): T =
  if x < min:
    return max
  if x > max:
    return min
  return x

proc roundTo*(x,y: int): int =
  return (x div y) * y

proc wrapAngle*(angle: float): float =
  var angle = angle
  while angle > PI:
    angle -= TAU
  while angle < -PI:
    angle += TAU
  return angle

proc wrapAngleTAU*(angle: float): float =
  var angle = angle
  while angle > TAU:
    angle -= TAU
  while angle < 0.0:
    angle += TAU
  return angle

proc getSubsample*[T](a: openarray[T], s: float): T =
  let alpha = s mod 1.0
  return lerp(a[s.int], if s < a.high: a[s.int+1] else: 0.0, alpha)

import unittest

suite "util":
  test "invLerp":
    check(invLerp(-1.0,  1.0, 0.0) == 0.5)
    check(invLerp( 1.0, -1.0, 0.0) == 0.5)
  test "angleDiff":
    check(angleDiff(0,0) == 0)
    check(angleDiff(TAU,0) == 0)
    check(angleDiff(PI,-PI) == 0)
    check(angleDiff(-PI,PI) == 0)
    check(angleDiff(-PI/2,PI/2) == -PI)
    check(angleDiff(PI/2,-PI/2) == -PI)
    check(angleDiff(PI/4,-PI/4).round(10) == (PI/2).round(10))
    check(angleDiff(10*TAU,0) == 0)
  test "roundTo":
    check(roundTo(7,8) == 0)
    check(roundTo(8,8) == 8)
    check(roundTo(9,8) == 8)
    check(roundTo(16,8) == 16)
  test "modDiff":
    check(modDiff(3,4,10) == 1)
    check(modDiff(9,0,10) == 1)
    check(modDiff(10,0,10) == 0)
    check(modDiff(30,0,10) == 0)
    check(modDiff(-30,0,10) == 0)
    check(modDiff(0,-30,10) == 0)
  test "%%/":
    check(-1 %%/ 10 == 9)
    check(1 %%/ 10 == 1)
    check(10 %%/ 10 == 0)
    check(11 %%/ 10 == 1)
    check(20 %%/ 10 == 0)
    check(30 %%/ 10 == 0)
    check(-10 %%/ 10 == 0)
  test "floatToTimeStr":
    check(floatToTimeStr(1.0) == "00:01.000")
    check(floatToTimeStr(60.0) == "01:00.000")
    check(floatToTimeStr(1.01) == "00:01.010")
    check(floatToTimeStr(-1.01) == "-00:01.010")
  test "normal":
    var v = vector2d(1,0)
    v.normal()
    check(v == vector2d(0,1))
  test "normal":
    var v = vector2d(0,1)
    v.normal()
    check(v == vector2d(-1,0))
  test "lineLineIntersection":
    var ray = [point2d(0,0),point2d(1,1)]
    var line = [point2d(0,1),point2d(1,0)]
    check(lineLineIntersection(ray,line) == (true,point2d(0.5,0.5)))
  test "lineSegmentIntersection":
    var ray = [point2d(0,0),point2d(1,1)]
    var line = [point2d(0,1),point2d(1,0)]
    check(lineSegmentIntersection(ray,line) == (true,point2d(0.5,0.5)))
    ray = [point2d(0,0),point2d(0,2)]
    line = [point2d(-1,1),point2d(1,1)]
    check(lineSegmentIntersection(ray,line) == (true,point2d(0,1)))
    ray = [point2d(2,0),point2d(2,2)]
    check(lineSegmentIntersection(ray,line) == (false,point2d(0,0)))
  test "lineSegDistance":
    var line = [point2d(0,0),point2d(0,10)]
    var p = point2d(-10,5)
    check(lineSegDistance(line,p) == 10)
    p = point2d(-5,2)
    check(lineSegDistance(line,p) == 5)
    p = point2d(5,0)
    check(lineSegDistance(line,p) == 5)
    p = point2d(5,-5)
    check(lineSegDistance(line,p) != 5)
    p = point2d(0,-5)
    check(lineSegDistance(line,p) == 5)
  test "ordinal":
    check(ordinal(0) == "1ST")
    check(ordinal(1) == "2ND")
    check(ordinal(2) == "3RD")
    check(ordinal(3) == "4TH")
    check(ordinal(9) == "10TH")
    check(ordinal(10) == "11TH")
    check(ordinal(11) == "12TH")
    check(ordinal(12) == "13TH")
    check(ordinal(20) == "21ST")
    check(ordinal(21) == "22ND")
    check(ordinal(22) == "23RD")
    check(ordinal(23) == "24TH")

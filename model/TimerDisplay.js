function advance(milliseconds, lastWall, nowWall) {
  var delta = Math.max(0, Math.min(2000, nowWall - lastWall))
  return { milliseconds: milliseconds + delta, lastWall: nowWall }
}

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "model", "TimerDisplay.js"), "utf8")
const context = vm.createContext({})
vm.runInContext(source, context)

function next(milliseconds, lastWall, nowWall) {
  const result = context.advance(milliseconds, lastWall, nowWall)
  return { milliseconds: result.milliseconds, lastWall: result.lastWall }
}

assert.deepEqual(next(120000, 1000, 2000), { milliseconds: 121000, lastWall: 2000 })
assert.deepEqual(next(120000, 1000, 3601000), { milliseconds: 122000, lastWall: 3601000 })
assert.deepEqual(next(120000, 2000, 1000), { milliseconds: 120000, lastWall: 1000 })
console.log("TimerDisplay: 3 cases passed")

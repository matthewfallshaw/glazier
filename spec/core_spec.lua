local core = require 'core'

local CONFIG = {
  sizes = { 1/2, 2/3, 1/3, 1/4, 3/4 },
  fullScreenSizes = { 1, 3/4, 1/2, 'c' },
  moveStep = 100, resizeStep = 50, minSize = 100, edgeTolerance = 4,
}
local SCREEN = { w = 3840, h = 2129 }

local function ctx(frame, memory, screen)
  return { frame = frame, memory = memory, screen = screen or SCREEN, config = CONFIG }
end

-- Run a command repeatedly as if the window obeys, returning each resulting frame.
local function press(command, arg, frame, times, memory)
  local frames = {}
  for i = 1, times do
    frame, memory = command(ctx(frame, memory), arg)
    frames[i] = frame
  end
  return frames, memory
end

describe("go", function()
  local start = { x = 500, y = 300, w = 1000, h = 800 }

  it("sends a window that isn't at the edge there, at the first size", function()
    local frame = core.go(ctx(start), 'left')
    assert.same({ x = 0, y = 300, w = 1920, h = 800 }, frame)
  end)

  it("cycles through every size and wraps at the end", function()
    local frames = press(core.go, 'up', start, 6)
    local heights = {}
    for i, f in ipairs(frames) do heights[i] = f.h end
    assert.same({ 1065, 1419, 710, 532, 1597, 1065 }, heights)
  end)

  it("anchors to the far edge going down or right", function()
    local frame = core.go(ctx(start), 'down')
    assert.equal(SCREEN.h, frame.y + frame.h)
    frame = core.go(ctx(start), 'right')
    assert.equal(SCREEN.w, frame.x + frame.w)
  end)

  it("leaves the other axis alone, so corners work", function()
    local frame, memory = core.go(ctx(start), 'up')
    frame = core.go(ctx(frame, memory), 'right')
    assert.same({ x = 1920, y = 0, w = 1920, h = 1065 }, frame)
  end)

  it("keeps each axis's cycle going while the other axis changes", function()
    local frame, memory = core.go(ctx(start), 'up')
    frame, memory = core.go(ctx(frame, memory), 'right')
    frame = core.go(ctx(frame, memory), 'up')
    assert.equal(1419, frame.h)
  end)

  it("picks up the cycle from geometry when it has no memory of the window", function()
    local frame = core.go(ctx({ x = 0, y = 0, w = 1920, h = 2129 }), 'left')
    assert.equal(2560, frame.w)
  end)

  it("restarts the cycle when the opposite side is pressed", function()
    local frame, memory = core.go(ctx(start), 'up')
    frame, memory = core.go(ctx(frame, memory), 'up')
    frame = core.go(ctx(frame, memory), 'down')
    assert.equal(1064, frame.h)
    assert.equal(SCREEN.h, frame.y + frame.h)
  end)

  it("restarts the cycle when something else changed that axis", function()
    local frame, memory = core.go(ctx(start), 'up')
    frame, memory = core.go(ctx(frame, memory), 'up')  -- at 2/3
    frame.h = 1200
    frame = core.go(ctx(frame, memory), 'up')
    assert.equal(1065, frame.h)
  end)

  it("keeps the cycle on an axis when something else changed only the other axis", function()
    local frame, memory = core.go(ctx(start), 'up')  -- at 1/2
    frame.w = frame.w + 300
    frame = core.go(ctx(frame, memory), 'up')
    assert.equal(1419, frame.h)
  end)

  it("still advances when the window refused the size", function()
    -- A window with a 1500pt minimum height: every smaller request leaves it at 1500.
    local frame, memory = core.go(ctx(start), 'up')
    memory = core.settled(memory, { x = frame.x, y = 0, w = frame.w, h = 1500 })
    frame, memory = core.go(ctx(memory.expected, memory), 'up')
    assert.equal(1419, frame.h)
    memory = core.settled(memory, { x = frame.x, y = 0, w = frame.w, h = 1500 })
    frame = core.go(ctx(memory.expected, memory), 'up')
    assert.equal(710, frame.h)
  end)

  it("doesn't treat a window near but not at the edge as already there", function()
    -- 80pt from the top is half a cell on the old 12-row grid, which read this as "at the top".
    local frame = core.go(ctx({ x = 0, y = 80, w = 1000, h = 1065 }), 'up')
    assert.equal(0, frame.y)
    assert.equal(1065, frame.h)
  end)

  it("brings a window straddling the screen edge fully inside", function()
    local frame = core.go(ctx({ x = 3500, y = 300, w = 1000, h = 800 }), 'up')
    assert.equal(SCREEN.w, frame.x + frame.w)
  end)

  it("leaves no gap between windows sent to opposite sides of an odd-sized screen", function()
    local screen = { w = 2057, h = 1289 }
    local left = core.go(ctx({ x = 9, y = 9, w = 9, h = 9 }, nil, screen), 'left')
    local right = core.go(ctx({ x = 9, y = 9, w = 9, h = 9 }, nil, screen), 'right')
    assert.is_true(left.x + left.w >= right.x)
    assert.equal(screen.w, right.x + right.w)
  end)
end)

describe("growFully", function()
  it("fills one dimension and leaves the other alone", function()
    local frame = core.growFully(ctx({ x = 500, y = 300, w = 1000, h = 800 }), 'h')
    assert.same({ x = 500, y = 0, w = 1000, h = 2129 }, frame)
  end)

  it("restarts that axis's cycle", function()
    local frame, memory = core.go(ctx({ x = 500, y = 300, w = 1000, h = 800 }), 'up')
    frame, memory = core.growFully(ctx(frame, memory), 'h')
    frame = core.go(ctx(frame, memory), 'up')
    assert.equal(1065, frame.h)
  end)
end)

describe("move", function()
  it("moves by a fixed number of points regardless of screen size", function()
    local start = { x = 500, y = 300, w = 1000, h = 800 }
    assert.equal(400, core.move(ctx(start), 'left').x)
    assert.equal(600, core.move(ctx(start), 'right').x)
    assert.equal(200, core.move(ctx(start), 'up').y)
    assert.equal(400, core.move(ctx(start), 'down').y)
  end)

  it("stops at the edge when less than a step away", function()
    assert.equal(0, core.move(ctx({ x = 500, y = 80, w = 1000, h = 800 }), 'up').y)
  end)

  it("stays put at the edge", function()
    local start = { x = 500, y = 0, w = 1000, h = 800 }
    assert.same(start, core.move(ctx(start), 'up'))
  end)
end)

describe("resize", function()
  local middle = { x = 500, y = 300, w = 1000, h = 800 }

  it("changes size by a fixed step around the centre when touching no edge", function()
    assert.same({ x = 475, y = 300, w = 1050, h = 800 }, core.resize(ctx(middle), 'wider'))
    assert.same({ x = 525, y = 300, w = 950, h = 800 }, core.resize(ctx(middle), 'thinner'))
    assert.same({ x = 500, y = 275, w = 1000, h = 850 }, core.resize(ctx(middle), 'taller'))
    assert.same({ x = 500, y = 325, w = 1000, h = 750 }, core.resize(ctx(middle), 'shorter'))
  end)

  for _, case in ipairs({
    { 'thinner', 'left',  { x = 0, y = 300, w = 1000, h = 800 },    { x = 0, y = 300, w = 950, h = 800 } },
    { 'thinner', 'right', { x = 2840, y = 300, w = 1000, h = 800 }, { x = 2890, y = 300, w = 950, h = 800 } },
    { 'shorter', 'top',   { x = 500, y = 0, w = 1000, h = 800 },    { x = 500, y = 0, w = 1000, h = 750 } },
    { 'shorter', 'bottom', { x = 500, y = 1329, w = 1000, h = 800 }, { x = 500, y = 1379, w = 1000, h = 750 } },
    { 'wider',   'left',  { x = 0, y = 300, w = 1000, h = 800 },    { x = 0, y = 300, w = 1050, h = 800 } },
    { 'wider',   'right', { x = 2840, y = 300, w = 1000, h = 800 }, { x = 2790, y = 300, w = 1050, h = 800 } },
    { 'taller',  'top',   { x = 500, y = 0, w = 1000, h = 800 },    { x = 500, y = 0, w = 1000, h = 850 } },
    { 'taller',  'bottom', { x = 500, y = 1329, w = 1000, h = 800 }, { x = 500, y = 1279, w = 1000, h = 850 } },
  }) do
    it(case[1] .. " keeps the " .. case[2] .. " edge where it is", function()
      assert.same(case[4], core.resize(ctx(case[3]), case[1]))
    end)
  end

  it("keeps the top edge when shrinking a full-height window", function()
    local frame = core.resize(ctx({ x = 0, y = 0, w = 1000, h = 2129 }), 'shorter')
    assert.same({ x = 0, y = 0, w = 1000, h = 2079 }, frame)
  end)

  it("uses its whole step when centred growth would cross an edge", function()
    local frame = core.resize(ctx({ x = 10, y = 300, w = 1000, h = 800 }), 'wider')
    assert.same({ x = 0, y = 300, w = 1050, h = 800 }, frame)
  end)

  it("doesn't shrink below the minimum size", function()
    assert.equal(100, core.resize(ctx({ x = 500, y = 300, w = 120, h = 800 }), 'thinner').w)
  end)

  it("doesn't grow past the screen", function()
    assert.equal(SCREEN.w, core.resize(ctx({ x = 0, y = 0, w = 3820, h = 800 }), 'wider').w)
  end)
end)

describe("center", function()
  it("centres without changing size, on whole points", function()
    assert.same({ x = 1420, y = 665, w = 1000, h = 799 },
      core.center(ctx({ x = 0, y = 0, w = 1000, h = 799 })))
  end)
end)

describe("fullscreen", function()
  local start = { x = 500, y = 300, w = 1000, h = 800 }

  it("cycles through the sizes, then back to the original frame", function()
    local frames = press(core.fullscreen, nil, start, 4)
    assert.same({ x = 0, y = 0, w = 3840, h = 2129 }, frames[1])
    assert.equal(2880, frames[2].w)
    assert.equal(1920, frames[3].w)
    assert.same(start, frames[4])
  end)

  it("starts over after restoring, remembering the frame again", function()
    local frames = press(core.fullscreen, nil, start, 8)
    assert.same(frames[1], frames[5])
    assert.same(start, frames[8])
  end)

  it("skips the restore step when it entered the cycle at a listed size", function()
    local full = { x = 0, y = 0, w = 3840, h = 2129 }
    local frames = press(core.fullscreen, nil, full, 3)
    assert.equal(2880, frames[1].w)
    assert.equal(1920, frames[2].w)
    assert.equal(3840, frames[3].w)
  end)

  it("keeps the restore frame across other commands", function()
    local frame, memory = core.fullscreen(ctx(start))
    local _, afterGo = core.go(ctx(frame, memory), 'left')
    assert.same(start, afterGo.restore)
  end)

  it("doesn't resume its cycle after another command moved the window", function()
    local frame, memory = core.fullscreen(ctx(start))
    frame, memory = core.fullscreen(ctx(frame, memory))  -- at 3/4
    frame, memory = core.go(ctx(frame, memory), 'left')
    frame = core.fullscreen(ctx(frame, memory))
    assert.equal(3840, frame.w)
  end)

  it("fits a restore frame from a larger screen onto this one", function()
    local _, memory = core.fullscreen(ctx(start))
    memory.restore = { x = 3000, y = 300, w = 3000, h = 800 }
    memory.fullscreenIndex = 3
    memory.expected = { x = 0, y = 0, w = 1000, h = 500 }
    local small = { w = 2000, h = 1000 }
    local frame = core.fullscreen(ctx({ x = 0, y = 0, w = 1000, h = 500 }, memory, small))
    assert.same({ x = 0, y = 200, w = 2000, h = 800 }, frame)
  end)
end)

describe("placeConstrained", function()
  local tol = CONFIG.edgeTolerance

  it("keeps the far edge a window refused to shrink away from", function()
    local requested = { x = 2880, y = 0, w = 960, h = 800 }
    local actual = { x = 2880, y = 0, w = 1200, h = 800 }
    assert.same({ x = 2640, y = 0, w = 1200, h = 800 },
      core.placeConstrained(requested, actual, SCREEN, tol))
  end)

  it("keeps the near edge for a full-size request", function()
    local requested = { x = 0, y = 0, w = 3840, h = 2129 }
    local actual = { x = 0, y = 0, w = 3000, h = 2129 }
    assert.same(actual, core.placeConstrained(requested, actual, SCREEN, tol))
  end)
end)

describe("parseChord", function()
  it("splits two keys", function()
    assert.same({ 'h', 'l' }, { core.parseChord('h+l') })
    assert.same({ 'left', 'right' }, { core.parseChord('left+right') })
  end)

  it("rejects anything that isn't exactly two keys", function()
    for _, chord in ipairs({ 'h', 'h+', '+l', 'h+j+l' }) do
      assert.is_nil(core.parseChord(chord))
    end
  end)
end)

describe("pressKey", function()
  local height = { keys = { 'k', 'j' } }
  local width = { keys = { 'h', 'l' } }
  local chords = { height, width }

  it("completes no chord on a lone press", function()
    assert.is_nil(core.pressKey({}, 'k', chords))
  end)

  it("completes a chord whichever key comes first", function()
    local held = {}
    core.pressKey(held, 'k', chords)
    assert.equal(height, core.pressKey(held, 'j', chords))
    held = {}
    core.pressKey(held, 'j', chords)
    assert.equal(height, core.pressKey(held, 'k', chords))
  end)

  it("completes no chord from keys in different chords, so corners work", function()
    local held = {}
    core.pressKey(held, 'k', chords)
    assert.is_nil(core.pressKey(held, 'l', chords))
  end)

  it("doesn't count a key that completed a chord as held", function()
    local held = {}
    core.pressKey(held, 'j', chords)
    core.pressKey(held, 'k', chords)  -- completes the chord, and stays physically down
    held.j = nil                      -- j released
    assert.is_nil(core.pressKey(held, 'j', chords))
  end)
end)

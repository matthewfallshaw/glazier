-- Pure window-placement logic: no `hs` calls and no global coordinates.
--
-- Every frame here is a plain {x, y, w, h} relative to the top-left of the screen's usable area,
-- and `screen` is its {w, h}. Only controller.lua converts to and from global coordinates, so
-- nothing in here can send a window to another display.
--
-- Commands take a context and return the frame to request and the window's new memory:
--   ctx = { frame = <current frame>, screen = {w, h}, memory = <window memory or nil>, config = {
--     sizes, fullScreenSizes, moveStep, resizeStep, minSize, edgeTolerance } }
--
-- Window memory:
--   expected         the frame we last left the window in; a mismatch means something else moved it
--   cycle            {x = {side, index}, y = {side, index}}, the position in `sizes` for each axis
--   fullscreenIndex  the position in `fullScreenSizes`
--   restore          the frame to return to for the 'c' entry in `fullScreenSizes`

local M = {}

local SIDES = {
  up    = { axis = 'y', dim = 'h', high = false, sign = -1 },
  down  = { axis = 'y', dim = 'h', high = true,  sign = 1 },
  left  = { axis = 'x', dim = 'w', high = false, sign = -1 },
  right = { axis = 'x', dim = 'w', high = true,  sign = 1 },
}

local GROWTHS = {
  taller  = { axis = 'y', dim = 'h', sign = 1 },
  shorter = { axis = 'y', dim = 'h', sign = -1 },
  wider   = { axis = 'x', dim = 'w', sign = 1 },
  thinner = { axis = 'x', dim = 'w', sign = -1 },
}

local DIM_OF_AXIS = { x = 'w', y = 'h' }

local function close(a, b, tolerance)
  return math.abs(a - b) <= tolerance
end

local function copyFrame(f)
  return { x = f.x, y = f.y, w = f.w, h = f.h }
end

local function round(n)
  return math.floor(n + 0.5)
end

--- True when two frames match to within `tolerance` points.
function M.framesClose(a, b, tolerance)
  return close(a.x, b.x, tolerance) and close(a.y, b.y, tolerance)
    and close(a.w, b.w, tolerance) and close(a.h, b.h, tolerance)
end

--- True when `frame` touches `side` of the screen.
function M.isBound(frame, screen, side, tolerance)
  local s = SIDES[side]
  if s.high then
    return close(frame[s.axis] + frame[s.dim], screen[s.dim], tolerance)
  end
  return close(frame[s.axis], 0, tolerance)
end

-- Fit one axis inside the screen, and round its edges rather than its position and size, so
-- windows that share an edge don't end up a point apart.
local function fitAxis(frame, screen, axis)
  local dim = DIM_OF_AXIS[axis]
  local size = math.min(frame[dim], screen[dim])
  local exactLow = math.max(0, math.min(frame[axis], screen[dim] - size))
  local low, high = round(exactLow), round(exactLow + size)
  frame[axis], frame[dim] = low, high - low
end

--- `frame` moved, then if necessary shrunk, to lie inside the screen, on whole points.
function M.fit(frame, screen)
  local fitted = copyFrame(frame)
  fitAxis(fitted, screen, 'x')
  fitAxis(fitted, screen, 'y')
  return fitted
end

-- The memory that still applies to `frame`: whatever we recorded about an axis is void once
-- something else has changed that axis. `restore` deliberately survives.
local function currentMemory(ctx)
  local previous = ctx.memory or {}
  local tolerance = ctx.config.edgeTolerance
  local memory = { cycle = {}, restore = previous.restore }
  local expected = previous.expected
  if expected then
    for axis, dim in pairs(DIM_OF_AXIS) do
      if close(ctx.frame[axis], expected[axis], tolerance)
        and close(ctx.frame[dim], expected[dim], tolerance) then
        memory.cycle[axis] = previous.cycle and previous.cycle[axis]
      end
    end
    if M.framesClose(ctx.frame, expected, tolerance) then
      memory.fullscreenIndex = previous.fullscreenIndex
    end
  end
  return memory
end

local function finish(frame, memory, screen)
  local fitted = M.fit(frame, screen)
  memory.expected = copyFrame(fitted)
  return fitted, memory
end

-- Where `frame` is in the size cycle for `side`, with 0 meaning "not in the cycle". Memory wins
-- over geometry, so the cycle still advances when an app refuses a size.
local function cycleIndex(ctx, memory, side)
  local s = SIDES[side]
  local remembered = memory.cycle[s.axis]
  if remembered and remembered.side == side then return remembered.index end
  if not M.isBound(ctx.frame, ctx.screen, side, ctx.config.edgeTolerance) then return 0 end
  for i, size in ipairs(ctx.config.sizes) do
    if close(ctx.frame[s.dim], size * ctx.screen[s.dim], ctx.config.edgeTolerance) then return i end
  end
  return 0
end

--- Move to the screen edge at `side`, or to the next size if already there. Leaves the other axis alone.
function M.go(ctx, side)
  local s = SIDES[side]
  local memory = currentMemory(ctx)
  local sizes = ctx.config.sizes
  local index = cycleIndex(ctx, memory, side) % #sizes + 1
  local frame = copyFrame(ctx.frame)
  frame[s.dim] = sizes[index] * ctx.screen[s.dim]
  frame[s.axis] = s.high and ctx.screen[s.dim] - frame[s.dim] or 0
  memory.cycle[s.axis] = { side = side, index = index }
  memory.fullscreenIndex = nil
  return finish(frame, memory, ctx.screen)
end

--- Fill the screen along `dim` ('w' or 'h'). Leaves the other axis alone.
function M.growFully(ctx, dim)
  local axis = dim == 'w' and 'x' or 'y'
  local memory = currentMemory(ctx)
  local frame = copyFrame(ctx.frame)
  frame[axis], frame[dim] = 0, ctx.screen[dim]
  memory.cycle[axis] = nil
  memory.fullscreenIndex = nil
  return finish(frame, memory, ctx.screen)
end

--- Move `moveStep` points towards `side`, stopping at the screen edge.
function M.move(ctx, side)
  local s = SIDES[side]
  local memory = currentMemory(ctx)
  local frame = copyFrame(ctx.frame)
  frame[s.axis] = frame[s.axis] + s.sign * ctx.config.moveStep
  memory.cycle[s.axis] = nil
  memory.fullscreenIndex = nil
  return finish(frame, memory, ctx.screen)
end

--- Grow or shrink by `resizeStep` points. An edge touching the screen stays there (top or left
--- first, if both do); otherwise the window changes size around its centre.
function M.resize(ctx, growth)
  local g = GROWTHS[growth]
  local memory = currentMemory(ctx)
  local frame = copyFrame(ctx.frame)
  local tolerance = ctx.config.edgeTolerance
  local size = frame[g.dim] + g.sign * ctx.config.resizeStep
  size = math.max(ctx.config.minSize, math.min(ctx.screen[g.dim], size))
  local delta = size - frame[g.dim]
  local lowSide, highSide = 'up', 'down'
  if g.axis == 'x' then lowSide, highSide = 'left', 'right' end
  if M.isBound(frame, ctx.screen, lowSide, tolerance) then
    frame[g.axis] = math.min(frame[g.axis], 0)
  elseif M.isBound(frame, ctx.screen, highSide, tolerance) then
    frame[g.axis] = ctx.screen[g.dim] - size
  else
    frame[g.axis] = frame[g.axis] - delta / 2
  end
  frame[g.dim] = size
  memory.cycle[g.axis] = nil
  memory.fullscreenIndex = nil
  return finish(frame, memory, ctx.screen)
end

--- Centre on the screen without changing size.
function M.center(ctx)
  local memory = currentMemory(ctx)
  local frame = copyFrame(ctx.frame)
  frame.x = (ctx.screen.w - frame.w) / 2
  frame.y = (ctx.screen.h - frame.h) / 2
  memory.cycle = {}
  memory.fullscreenIndex = nil
  return finish(frame, memory, ctx.screen)
end

local function centredFrame(screen, size)
  return M.fit({
    x = screen.w * (1 - size) / 2,
    y = screen.h * (1 - size) / 2,
    w = screen.w * size,
    h = screen.h * size,
  }, screen)
end

local function fullscreenIndex(ctx, memory)
  if memory.fullscreenIndex then return memory.fullscreenIndex end
  for i, size in ipairs(ctx.config.fullScreenSizes) do
    if size ~= 'c' and
      M.framesClose(ctx.frame, centredFrame(ctx.screen, size), ctx.config.edgeTolerance) then
      return i
    end
  end
  return 0
end

--- Go to the next entry in `fullScreenSizes`. Entering the cycle remembers the window's frame for
--- the 'c' entry, which returns there once and is skipped when there is nothing to return to.
function M.fullscreen(ctx)
  local memory = currentMemory(ctx)
  local sizes = ctx.config.fullScreenSizes
  local index = fullscreenIndex(ctx, memory)
  if index == 0 then memory.restore = copyFrame(ctx.frame) end
  index = index % #sizes + 1
  if sizes[index] == 'c' and not memory.restore then index = index % #sizes + 1 end
  memory.cycle = {}
  local frame
  if sizes[index] == 'c' then
    frame = memory.restore or ctx.frame
    memory.restore = nil
    memory.fullscreenIndex = nil
  else
    frame = centredFrame(ctx.screen, sizes[index])
    memory.fullscreenIndex = index
  end
  return finish(frame, memory, ctx.screen)
end

--- Where to put a window that took size `actual` instead of the size in `requested`: keep its size,
--- keep any far edge the request touched, and stay on the screen.
function M.placeConstrained(requested, actual, screen, tolerance)
  local frame = { x = requested.x, y = requested.y, w = actual.w, h = actual.h }
  for axis, dim in pairs(DIM_OF_AXIS) do
    local touchesLow = close(requested[axis], 0, tolerance)
    local touchesHigh = close(requested[axis] + requested[dim], screen[dim], tolerance)
    if touchesHigh and not touchesLow then frame[axis] = screen[dim] - actual[dim] end
  end
  return M.fit(frame, screen)
end

--- Record the frame the window actually ended up with.
function M.settled(memory, actual)
  local updated = {}
  for k, v in pairs(memory) do updated[k] = v end
  updated.expected = copyFrame(actual)
  return updated
end

--- Forget the cycle positions, keeping `restore`: the window has changed screens.
function M.forgetPlacement(memory)
  return { cycle = {}, restore = memory.restore }
end

--- The two key names in a chord written as 'key1+key2', or nil if it isn't one.
function M.parseChord(chord)
  return chord:match('^([^+]+)%+([^+]+)$')
end

--- Record a key press in `held`, and return the chord it completes, if any. A chord is a table
--- whose `keys` are a pair of key names. Completing a chord marks both its keys as used, so
--- releasing them doesn't count as a tap.
function M.pressKey(held, key, chords)
  for _, chord in ipairs(chords) do
    local a, b = chord.keys[1], chord.keys[2]
    local partner = (key == a and b) or (key == b and a)
    if partner and held[partner] then
      held[a], held[b] = 'used', 'used'
      return chord
    end
  end
  held[key] = 'tapped'
  return nil
end

--- Record a key release in `held`, and return whether the press was a tap: a press that
--- completed no chord.
function M.releaseKey(held, key)
  local tapped = held[key] == 'tapped'
  held[key] = nil
  return tapped
end

return M

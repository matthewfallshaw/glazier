-- Copyright (c) 2018 Miro Mannino
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this
-- software and associated documentation files (the "Software"), to deal in the Software
-- without restriction, including without limitation the rights to use, copy, modify, merge,
-- publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
-- to whom the Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies
-- or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
-- INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
-- PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
-- FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
-- OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

--- === Glazier ===
---
--- Move windows to edges and corners of the screen and cycle through sizes, using your keyboard.
---
--- Tap a direction to go to that edge of the screen, and tap it again to cycle through sizes. Tap perpendicular directions to reach a corner. Any action can be bound to a hotkey, or to a chord of two keys.
---
--- Glazier began as a fork of [miro-windows-manager](https://github.com/miromannino/miro-windows-manager) by Miro Mannino, who designed this way of arranging windows with just the arrow keys and wrote the original Spoon. Glazier reimplements it under a new name, so bugs here are Glazier's rather than Miro's.
---
--- Placement logic is in `core.lua`, and applying it to windows is in `controller.lua`. This file holds the Spoon's settings, its Hammerspoon bindings and its key bindings.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Glazier"
obj.version = "2.0"
obj.author = "Miro Mannino <miro.mannino@gmail.com>, Matt Fallshaw"
obj.homepage = "https://github.com/matthewfallshaw/miro-windows-manager"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- Glazier.logger
--- Variable
--- Logger for this Spoon. Windows that don't take the requested frame are logged as warnings; every placement is logged at debug level.
obj.logger = hs.logger.new(obj.name)

--- Glazier.sizes
--- Variable
--- The sizes a window cycles through at a screen edge, as fractions of the screen.
obj.sizes = { 1/2, 1/3, 2/3 }

--- Glazier.fullScreenSizes
--- Variable
--- The sizes the fullscreen action cycles through, as fractions of the screen. Use 'c' for the window's frame from before it started cycling.
obj.fullScreenSizes = { 1, 1/2, 'c' }

--- Glazier.moveStep
--- Variable
--- How far each press in Move mode moves the window, in points.
obj.moveStep = 100

--- Glazier.resizeStep
--- Variable
--- How much each press in Resize mode changes the window's width or height, in points.
obj.resizeStep = 50

--- Glazier.minSize
--- Variable
--- The smallest width or height Resize mode will ask for, in points.
obj.minSize = 100

--- Glazier.edgeTolerance
--- Variable
--- How close to a screen edge, or to an expected size or position, counts as being there, in points.
obj.edgeTolerance = 4

local SETTINGS_KEY = obj.name .. ".windows"

local core = dofile(hs.spoons.resourcePath("core.lua"))
local controllerModule = dofile(hs.spoons.resourcePath("controller.lua"))

local function plainFrame(f)
  return { x = f.x, y = f.y, w = f.w, h = f.h }
end

-- The window interface controller.lua expects.
local function windowInterface(win)
  return {
    id = function() return win:id() end,
    app = function()
      local app = win:application()
      return app and app:name() or 'unknown app'
    end,
    screenId = function() return win:screen():id() end,
    screenFrame = function() return plainFrame(win:screen():frame()) end,
    frame = function()
      if not win:id() then return nil end
      return plainFrame(win:frame())
    end,
    setFrame = function(frame, duration)
      win:setFrame(hs.geometry.rect(frame.x, frame.y, frame.w, frame.h), duration)
    end,
  }
end

local controller = controllerModule.new({
  core = core,
  config = obj,
  animationDuration = function() return hs.window.animationDuration end,
  schedule = function(delay, fn)
    local timer = hs.timer.doAfter(delay, fn)
    return function() timer:stop() end
  end,
  log = { d = obj.logger.d, w = obj.logger.w },
  store = {
    load = function() return hs.settings.get(SETTINGS_KEY) end,
    save = function(windows) hs.settings.set(SETTINGS_KEY, windows) end,
  },
})

local function run(win, command, arg)
  win = win or hs.window.frontmostWindow()
  if not win then
    obj.logger.d('No window to act on')
    return
  end
  controller.run(windowInterface(win), command, arg)
end

--- Glazier:go(side[, win])
--- Method
--- Move a window to a screen edge, or to the next of `sizes` if already there.
---
--- Parameters:
---  * side - 'up', 'down', 'left', or 'right'
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The Glazier object
function obj:go(side, win)
  run(win, core.go, side)
  return self
end

--- Glazier:growFully(dimension[, win])
--- Method
--- Make a window fill the screen's height or width.
---
--- Parameters:
---  * dimension - 'h' or 'w'
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The Glazier object
function obj:growFully(dimension, win)
  run(win, core.growFully, dimension)
  return self
end

--- Glazier:move(side[, win])
--- Method
--- Move a window `moveStep` points, stopping at the screen edge.
---
--- Parameters:
---  * side - 'up', 'down', 'left', or 'right'
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The Glazier object
function obj:move(side, win)
  run(win, core.move, side)
  return self
end

--- Glazier:resize(growth[, win])
--- Method
--- Change a window's size by `resizeStep` points. Edges touching the screen edge stay there.
---
--- Parameters:
---  * growth - 'taller', 'shorter', 'wider', or 'thinner'
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The Glazier object
function obj:resize(growth, win)
  run(win, core.resize, growth)
  return self
end

--- Glazier:fullscreen([win])
--- Method
--- Go to the next of `fullScreenSizes`, centred on the screen.
---
--- Parameters:
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The Glazier object
function obj:fullscreen(win)
  run(win, core.fullscreen)
  return self
end

--- Glazier:center([win])
--- Method
--- Centre a window on its screen without changing its size.
---
--- Parameters:
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The Glazier object
function obj:center(win)
  run(win, core.center)
  return self
end

local DIRECTIONS = { 'up', 'down', 'left', 'right' }
local GROWTH_FOR_DIRECTION = { up = 'taller', down = 'shorter', left = 'thinner', right = 'wider' }

-- Actions that run once.
local TAPS = {
  up = function(self) self:go('up') end,
  down = function(self) self:go('down') end,
  left = function(self) self:go('left') end,
  right = function(self) self:go('right') end,
  fullWidth = function(self) self:growFully('w') end,
  fullHeight = function(self) self:growFully('h') end,
  fullscreen = function(self) self:fullscreen() end,
  center = function(self) self:center() end,
}

-- Actions that are active while their keys are held, and step while a direction key is held.
local MODES = {
  move = function(self, direction) self:move(direction) end,
  resize = function(self, direction) self:resize(GROWTH_FOR_DIRECTION[direction]) end,
}

local modals = {}

-- What binding the action `name` does: `{ tap = fn }`, or `{ press = fn, release = fn }` for a mode.
local function behaviour(self, name, mods, directionKeys)
  if TAPS[name] then
    return { tap = function() TAPS[name](self) end }
  end
  local step = assert(MODES[name], "unknown action: " .. tostring(name))
  local modal = hs.hotkey.modal.new()
  table.insert(modals, modal)
  for direction, key in pairs(directionKeys) do
    local act = function() step(self, direction) end
    modal:bind(mods, key, act, nil, act)
  end
  return { press = function() modal:enter() end, release = function() modal:exit() end }
end

local function keyId(mods, key)
  local sorted = { table.unpack(mods) }
  table.sort(sorted)
  return table.concat(sorted, '+') .. '+' .. key
end

obj.hotkeys = {}

-- Replace every binding with those in `hotkeyMapping` and `chordMapping`.
local function rebind(self)
  for _, hotkey in ipairs(self.hotkeys) do hotkey:delete() end
  for _, modal in ipairs(modals) do modal:delete() end
  self.hotkeys, modals = {}, {}
  local hotkeyMapping, chordMapping = self.hotkeyMapping or {}, self.chordMapping or {}

  local directionKeys = {}
  for _, direction in ipairs(DIRECTIONS) do
    if hotkeyMapping[direction] then directionKeys[direction] = hotkeyMapping[direction][2] end
  end

  local keys = {}  -- key id -> { id, mods, key, and the behaviour bound to it alone }
  local function keyFor(mods, key)
    local id = keyId(mods, key)
    keys[id] = keys[id] or { id = id, mods = mods, key = key }
    return keys[id]
  end

  for name, spec in pairs(hotkeyMapping) do
    local key = keyFor(spec[1], spec[2])
    local b = behaviour(self, name, spec[1], directionKeys)
    key.tap, key.press, key.release = b.tap, b.press, b.release
  end

  local chords, inChord = {}, {}
  for name, spec in pairs(chordMapping) do
    assert(type(spec[2]) == 'string' and type(spec[3]) == 'string',
      name .. " must be a chord written as {mods, key1, key2}")
    local a, b = keyFor(spec[1], spec[2]), keyFor(spec[1], spec[3])
    inChord[a.id], inChord[b.id] = true, true
    local action = behaviour(self, name, spec[1], directionKeys)
    table.insert(chords, { keys = { a.id, b.id }, press = action.tap or action.press, release = action.release })
  end

  -- A key in a chord taps when released, and only if no chord completed while it was down.
  local held = {}
  for id, key in pairs(keys) do
    table.insert(self.hotkeys, hs.hotkey.bind(key.mods, key.key,
      function()
        local chord = core.pressKey(held, id, chords)
        if chord then
          chord.press()
        else
          if key.press then key.press() end
          if key.tap and not inChord[id] then key.tap() end
        end
      end,
      function()
        local tapped, chord = core.releaseKey(held, id)
        if chord and chord.release then chord.release() end
        if key.release then key.release() end
        if tapped and key.tap and inChord[id] then key.tap() end
      end))
  end
end

--- Glazier:bindHotkeys(mapping)
--- Method
--- Binds actions to hotkeys. Every action is optional, and any action can instead be bound to a chord with `bindChords`.
---
--- Parameters:
---  * mapping - A table of `{mods, key}` for any of:
---   * up, down, left, right - Go to that edge, or cycle sizes if already there
---   * fullWidth, fullHeight - Fill the screen's width or height
---   * fullscreen - Cycle through `fullScreenSizes`
---   * center - Centre the window
---   * move - Hold this and tap a direction key to move the window
---   * resize - Hold this and tap a direction key to resize the window: up is taller, down is shorter, left is thinner, right is wider
---
--- Returns:
---  * The Glazier object
---
--- Notes:
---  * Move and resize use the keys bound to the directions here, with the modifiers of their own binding.
function obj:bindHotkeys(mapping)
  self.hotkeyMapping = mapping
  rebind(self)
  return self
end

--- Glazier:bindChords(mapping)
--- Method
--- Binds actions to chords: two keys pressed together, with the same modifiers.
---
--- Parameters:
---  * mapping - A table of `{mods, key1, key2}` for any of the actions listed for `bindHotkeys`
---
--- Returns:
---  * The Glazier object
---
--- Notes:
---  * A chord's keys can also be hotkeys. Their actions then run when the key is released, and not at all if it was part of a chord.
---  * A mode bound to a chord is active until either of its keys is released.
function obj:bindChords(mapping)
  self.chordMapping = mapping
  rebind(self)
  return self
end

return obj

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

--- === MiroWindowsManager ===
---
--- Move windows to edges and corners of the screen and cycle through sizes, using your keyboard.
---
--- Tap a direction to go to that edge of the screen, and tap it again to cycle through sizes. Tap perpendicular directions to reach a corner. Optional chords fill the screen's height or width.
---
--- Forked from [miro-windows-manager](https://github.com/miromannino/miro-windows-manager) by Miro Mannino, who designed this way of arranging windows with just the arrow keys and wrote the original Spoon. This fork reimplements it, and its settings differ, so bugs here are the fork's rather than Miro's.
---
--- Placement logic is in `core.lua`, and applying it to windows is in `controller.lua`. This file holds the Spoon's settings, its Hammerspoon bindings and its hotkeys.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "MiroWindowsManager"
obj.version = "2.0"
obj.author = "Miro Mannino <miro.mannino@gmail.com>, Matt Fallshaw"
obj.homepage = "https://github.com/matthewfallshaw/miro-windows-manager"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- MiroWindowsManager.logger
--- Variable
--- Logger for this Spoon. Windows that don't take the requested frame are logged as warnings; every placement is logged at debug level.
obj.logger = hs.logger.new(obj.name)

--- MiroWindowsManager.sizes
--- Variable
--- The sizes a window cycles through at a screen edge, as fractions of the screen.
obj.sizes = { 1/2, 1/3, 2/3 }

--- MiroWindowsManager.fullScreenSizes
--- Variable
--- The sizes the fullscreen action cycles through, as fractions of the screen. Use 'c' for the window's frame from before it started cycling.
obj.fullScreenSizes = { 1, 1/2, 'c' }

--- MiroWindowsManager.moveStep
--- Variable
--- How far each press in Move mode moves the window, in points.
obj.moveStep = 100

--- MiroWindowsManager.resizeStep
--- Variable
--- How much each press in Resize mode changes the window's width or height, in points.
obj.resizeStep = 50

--- MiroWindowsManager.minSize
--- Variable
--- The smallest width or height Resize mode will ask for, in points.
obj.minSize = 100

--- MiroWindowsManager.edgeTolerance
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

--- MiroWindowsManager:go(side[, win])
--- Method
--- Move a window to a screen edge, or to the next of `sizes` if already there.
---
--- Parameters:
---  * side - 'up', 'down', 'left', or 'right'
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The MiroWindowsManager object
function obj:go(side, win)
  run(win, core.go, side)
  return self
end

--- MiroWindowsManager:growFully(dimension[, win])
--- Method
--- Make a window fill the screen's height or width.
---
--- Parameters:
---  * dimension - 'h' or 'w'
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The MiroWindowsManager object
function obj:growFully(dimension, win)
  run(win, core.growFully, dimension)
  return self
end

--- MiroWindowsManager:move(side[, win])
--- Method
--- Move a window `moveStep` points, stopping at the screen edge.
---
--- Parameters:
---  * side - 'up', 'down', 'left', or 'right'
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The MiroWindowsManager object
function obj:move(side, win)
  run(win, core.move, side)
  return self
end

--- MiroWindowsManager:resize(growth[, win])
--- Method
--- Change a window's size by `resizeStep` points. Edges touching the screen edge stay there.
---
--- Parameters:
---  * growth - 'taller', 'shorter', 'wider', or 'thinner'
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The MiroWindowsManager object
function obj:resize(growth, win)
  run(win, core.resize, growth)
  return self
end

--- MiroWindowsManager:fullscreen([win])
--- Method
--- Go to the next of `fullScreenSizes`, centred on the screen.
---
--- Parameters:
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The MiroWindowsManager object
function obj:fullscreen(win)
  run(win, core.fullscreen)
  return self
end

--- MiroWindowsManager:center([win])
--- Method
--- Centre a window on its screen without changing its size.
---
--- Parameters:
---  * win - Optional `hs.window`; defaults to the frontmost window
---
--- Returns:
---  * The MiroWindowsManager object
function obj:center(win)
  run(win, core.center)
  return self
end

local DIRECTIONS = { 'up', 'down', 'left', 'right' }
local GROWTH_FOR_DIRECTION = { up = 'taller', down = 'shorter', left = 'thinner', right = 'wider' }

-- A mode is active while its hotkey is held, and repeats `action` while a direction key is held.
local function bindMode(self, modeHotkey, directionKeys, action)
  local mods, modeKey = modeHotkey[1], modeHotkey[2]
  local modal = hs.hotkey.modal.new()
  for direction, directionKey in pairs(directionKeys) do
    local act = function() action(direction) end
    modal:bind(mods, directionKey, act, nil, act)
  end
  table.insert(self.hotkeys, hs.hotkey.bind(mods, modeKey,
    function() modal:enter() end,
    function() modal:exit() end))
end

obj.hotkeys = {}

local function keyId(mods, key)
  local sorted = { table.unpack(mods) }
  table.sort(sorted)
  return table.concat(sorted, '+') .. '+' .. key
end

--- MiroWindowsManager:bindHotkeys(mapping)
--- Method
--- Binds hotkeys. Every action is optional.
---
--- Parameters:
---  * mapping - A table of `{mods, key}` for any of:
---   * up, down, left, right - Go to that edge, or cycle sizes if already there
---   * fullscreen - Cycle through `fullScreenSizes`
---   * center - Centre the window
---   * move - Hold this and tap a direction key to move the window
---   * resize - Hold this and tap a direction key to resize the window: up is taller, down is shorter, left is thinner, right is wider
---  * and `{mods, 'key1+key2'}`, a chord of two keys pressed together, for any of:
---   * fullWidth, fullHeight - Fill the screen's width or height
---
--- Returns:
---  * The MiroWindowsManager object
---
--- Notes:
---  * Move and resize use the same keys as the directions, with the modifiers of their own hotkey.
---  * A chord's keys can also be hotkeys for other actions. Those actions run when the key is released, and not at all if it was part of a chord. Other actions run when their key is pressed.
function obj:bindHotkeys(mapping)
  local bindings = {}  -- key id -> { mods, key, action }
  local function bindingFor(mods, key)
    local id = keyId(mods, key)
    bindings[id] = bindings[id] or { id = id, mods = mods, key = key }
    return bindings[id]
  end

  local directionKeys = {}
  for _, direction in ipairs(DIRECTIONS) do
    if mapping[direction] then
      directionKeys[direction] = mapping[direction][2]
      bindingFor(mapping[direction][1], mapping[direction][2]).action =
        function() self:go(direction) end
    end
  end
  if mapping.fullscreen then
    bindingFor(mapping.fullscreen[1], mapping.fullscreen[2]).action = function() self:fullscreen() end
  end
  if mapping.center then
    bindingFor(mapping.center[1], mapping.center[2]).action = function() self:center() end
  end

  local chords = {}
  for name, dimension in pairs({ fullWidth = 'w', fullHeight = 'h' }) do
    local chord = mapping[name]
    if chord then
      local key1, key2 = core.parseChord(chord[2])
      assert(key1, name .. " must be a chord written as 'key1+key2'")
      local first = bindingFor(chord[1], key1)
      local second = bindingFor(chord[1], key2)
      table.insert(chords, {
        keys = { first.id, second.id },
        action = function() self:growFully(dimension) end,
      })
    end
  end

  -- A key in a chord acts when released, and only if it completed no chord while down.
  local inChord = {}
  for _, chord in ipairs(chords) do
    inChord[chord.keys[1]], inChord[chord.keys[2]] = true, true
  end
  local held = {}
  for id, binding in pairs(bindings) do
    local action = binding.action or function() end
    local deferred = inChord[id]
    table.insert(self.hotkeys, hs.hotkey.bind(binding.mods, binding.key,
      function()
        local chord = core.pressKey(held, id, chords)
        if chord then
          chord.action()
        elseif not deferred then
          action()
        end
      end,
      function()
        if core.releaseKey(held, id) and deferred then action() end
      end))
  end

  if mapping.move then
    bindMode(self, mapping.move, directionKeys, function(direction) self:move(direction) end)
  end
  if mapping.resize then
    bindMode(self, mapping.resize, directionKeys, function(direction)
      self:resize(GROWTH_FOR_DIRECTION[direction])
    end)
  end
  return self
end

return obj

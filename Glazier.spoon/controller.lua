-- Applies core.lua's commands to windows, and checks what the window actually did.
--
-- A window here is a table of functions, so this runs without Hammerspoon:
--   id() -> number, app() -> string, screenId() -> number, screenFrame() -> {x, y, w, h}
--   frame() -> {x, y, w, h} or nil if the window has gone
--   setFrame(frame [, duration])
--
-- env:
--   core, config     core.lua, and the config its commands read
--   animationDuration()  -> seconds a setFrame without a duration animates for
--   schedule(delay, fn)  -> a function that cancels it
--   log              {d = fn(text), w = fn(text)}
--   store            {load = fn() -> table or nil, save = fn(table)}, memory that outlives this
--                    controller; its table keys must be strings

local M = {}

-- Seconds after an animation should end before trusting the window's frame. Until the animation
-- has really finished, hs.window:frame() returns its target rather than where the window is, and
-- its timer can run late. Checking late is harmless: a press before the check just records the frame.
local SETTLE_DELAY = 0.25
local MAX_REMEMBERED_WINDOWS = 64

local function toLocal(f, screen)
  return { x = f.x - screen.x, y = f.y - screen.y, w = f.w, h = f.h }
end

local function toGlobal(f, screen)
  return { x = f.x + screen.x, y = f.y + screen.y, w = f.w, h = f.h }
end

local function describe(f)
  return string.format('%d,%d %dx%d', f.x, f.y, f.w, f.h)
end

function M.new(env)
  local core, config, log = env.core, env.config, env.log
  -- Window id (as a string) -> { memory, screenId, app, lastUsed, cancelSettle }. Everything but
  -- cancelSettle is persisted. MAX_REMEMBERED_WINDOWS bounds this table and what's stored, however
  -- many windows come and go; closed windows are just the first to be evicted.
  local entries = {}
  local uses = 0

  for id, saved in pairs(env.store.load() or {}) do
    entries[id] = saved
    uses = math.max(uses, saved.lastUsed)
  end

  local function persist()
    local saved = {}
    for id, entry in pairs(entries) do
      saved[id] = {
        memory = entry.memory,
        screenId = entry.screenId,
        app = entry.app,
        lastUsed = entry.lastUsed,
      }
    end
    env.store.save(saved)
  end

  local function evictOldest()
    local count, oldestId, oldestUse = 0, nil, math.huge
    for id, entry in pairs(entries) do
      count = count + 1
      if entry.lastUsed < oldestUse then oldestId, oldestUse = id, entry.lastUsed end
    end
    if count > MAX_REMEMBERED_WINDOWS then entries[oldestId] = nil end
  end

  local function entryFor(win)
    local id = tostring(win.id())
    local app = win.app()
    uses = uses + 1
    -- A different app means the system reused this id, so what we remember is about another window.
    if not entries[id] or entries[id].app ~= app then entries[id] = { app = app } end
    local entry = entries[id]
    entry.lastUsed = uses
    evictOldest()
    return entry
  end

  -- Check the window took the requested frame. If not, try again without animation, in case the
  -- app dropped a request; then accept what the window insists on, keeping it placed sensibly.
  local function settle(win, entry, requested, screen)
    entry.cancelSettle = nil
    local tolerance = config.edgeTolerance
    local function actualFrame()
      local f = win.frame()
      return f and toLocal(f, screen)
    end
    local actual = actualFrame()
    if not actual then return end
    if not core.framesClose(actual, requested, tolerance) then
      local screenSize = { w = screen.w, h = screen.h }
      win.setFrame(toGlobal(requested, screen), 0)
      actual = actualFrame()
      if not actual then return end
      if not core.framesClose(actual, requested, tolerance) then
        local placed = core.placeConstrained(requested, actual, screenSize, tolerance)
        if not core.framesClose(actual, placed, tolerance) then
          win.setFrame(toGlobal(placed, screen), 0)
          actual = actualFrame()
          if not actual then return end
        end
        log.w(string.format('%s window %d: requested %s, got %s', win.app(), win.id(),
          describe(requested), describe(actual)))
      end
    end
    entry.memory = core.settled(entry.memory, actual)
  end

  local controller = {}

  --- Run `command(ctx, arg)` from core.lua on `win`.
  function controller.run(win, command, arg)
    local current = win.frame()
    if not current then return end
    local entry = entryFor(win)
    local screen = win.screenFrame()

    if entry.cancelSettle then
      -- Pressed again before the check ran: whatever the frame is now is what we left it at.
      entry.cancelSettle()
      entry.cancelSettle = nil
      entry.memory = core.settled(entry.memory, toLocal(current, screen))
    end
    local screenId = win.screenId()
    if entry.memory and entry.screenId ~= screenId then
      entry.memory = core.forgetPlacement(entry.memory)
    end
    entry.screenId = screenId

    local requested, memory = command({
      frame = toLocal(current, screen),
      screen = { w = screen.w, h = screen.h },
      memory = entry.memory,
      config = config,
    }, arg)
    entry.memory = memory
    log.d(string.format('%s window %d: %s -> %s', win.app(), win.id(),
      describe(toLocal(current, screen)), describe(requested)))
    win.setFrame(toGlobal(requested, screen))
    entry.cancelSettle = env.schedule(env.animationDuration() + SETTLE_DELAY, function()
      settle(win, entry, requested, screen)
      persist()
    end)
  end

  return controller
end

return M

local core = require 'core'
local controller = require 'controller'

local DELL = { id = 2, x = 2056, y = -800, w = 3840, h = 2129 }
local LAPTOP = { id = 1, x = 0, y = 40, w = 2056, h = 1289 }

-- A simulated app window, in global coordinates. Options:
--   minH           refuses to be shorter than this
--   dropRequests   ignores this many setFrames
local function fakeWindow(frame, screen, options)
  options = options or {}
  local win = { current = frame, screen = screen, dropRequests = options.dropRequests or 0 }
  function win.id() return 1 end
  function win.app() return 'Fake' end
  function win.screenId() return win.screen.id end
  function win.screenFrame() return win.screen end
  function win.frame() return win.current and {
    x = win.current.x, y = win.current.y, w = win.current.w, h = win.current.h } end
  function win.setFrame(f)
    if win.dropRequests > 0 then
      win.dropRequests = win.dropRequests - 1
      return
    end
    win.current = { x = f.x, y = f.y, w = f.w, h = math.max(f.h, options.minH or 0) }
  end
  return win
end

local function fakeEnv()
  local env = {
    core = core,
    config = {
      sizes = { 1/2, 2/3, 1/3, 1/4, 3/4 },
      fullScreenSizes = { 1, 3/4, 1/2, 'c' },
      moveStep = 100, resizeStep = 50, minSize = 100, edgeTolerance = 4,
    },
    animationDuration = function() return 0.1 end,
    warnings = {},
  }
  -- Like hs.settings: holds a copy, and refuses keys a property list can't hold.
  local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for k, v in pairs(value) do
      assert(type(k) == 'string' or math.type(k) == 'integer', 'unstorable key')
      result[k] = copy(v)
    end
    return result
  end
  local function assertStringKeys(t)
    for k in pairs(t) do assert(type(k) == 'string', 'store keys must be strings') end
  end
  env.stored = nil
  env.store = {
    load = function() return copy(env.stored) end,
    save = function(t) assertStringKeys(t); env.stored = copy(t) end,
  }
  env.log = { d = function() end, w = function(text) table.insert(env.warnings, text) end }
  local pending = {}
  function env.schedule(_, fn)
    local job = { fn = fn }
    table.insert(pending, job)
    return function() job.cancelled = true end
  end
  function env.runScheduled()
    local jobs = pending
    pending = {}
    for _, job in ipairs(jobs) do
      if not job.cancelled then job.fn() end
    end
  end
  return env
end

-- Press a key and let the window settle.
local function press(env, ctl, win, command, arg)
  ctl.run(win, command, arg)
  env.runScheduled()
end

describe("controller", function()
  local env, ctl

  before_each(function()
    env = fakeEnv()
    ctl = controller.new(env)
  end)

  describe("on a screen away from the global origin", function()
    it("keeps a left-bound window on its screen when thinning it", function()
      local win = fakeWindow({ x = 2056, y = -800, w = 2000, h = 2129 }, DELL)
      press(env, ctl, win, core.resize, 'thinner')
      assert.same({ x = 2056, y = -800, w = 1950, h = 2129 }, win.current)
    end)

    it("keeps a top-bound window at the top of its screen when shortening it", function()
      local win = fakeWindow({ x = 2056, y = -800, w = 2000, h = 2129 }, DELL)
      press(env, ctl, win, core.resize, 'shorter')
      assert.same({ x = 2056, y = -800, w = 2000, h = 2079 }, win.current)
    end)

    it("places windows relative to their own screen", function()
      local win = fakeWindow({ x = 3000, y = 0, w = 1000, h = 800 }, DELL)
      press(env, ctl, win, core.go, 'left')
      press(env, ctl, win, core.go, 'down')
      assert.same({ x = 2056, y = 265, w = 1920, h = 1064 }, win.current)
    end)
  end)

  it("respects a menu bar at the top of the usable area", function()
    local win = fakeWindow({ x = 100, y = 500, w = 800, h = 500 }, LAPTOP)
    press(env, ctl, win, core.go, 'up')
    assert.equal(40, win.current.y)
  end)

  describe("when an app refuses a size", function()
    it("keeps cycling, not stuck at the size it refused", function()
      local win = fakeWindow({ x = 2056, y = -800, w = 1000, h = 1500 }, DELL, { minH = 1500 })
      press(env, ctl, win, core.go, 'up')  -- wants 1/2, stays 1500
      press(env, ctl, win, core.go, 'up')  -- wants 2/3, stays 1500
      press(env, ctl, win, core.go, 'up')  -- wants 1/3, stays 1500
      press(env, ctl, win, core.go, 'up')  -- wants 1/4, stays 1500
      press(env, ctl, win, core.go, 'up')  -- wants 3/4, which it can do
      assert.equal(1597, win.current.h)
    end)

    it("keeps a too-tall window on the screen when sent to the bottom", function()
      local win = fakeWindow({ x = 2056, y = -800, w = 1000, h = 1500 }, DELL, { minH = 1500 })
      press(env, ctl, win, core.go, 'down')
      assert.equal(DELL.y + DELL.h, win.current.y + win.current.h)
      assert.equal(1500, win.current.h)
    end)

    it("reports what it asked for and what it got", function()
      local win = fakeWindow({ x = 2056, y = -800, w = 1000, h = 1500 }, DELL, { minH = 1500 })
      press(env, ctl, win, core.go, 'up')
      assert.equal(1, #env.warnings)
      assert.matches('Fake window 1: requested 0,0 1000x1065, got 0,0 1000x1500', env.warnings[1], nil, true)
    end)
  end)

  describe("when an app ignores a request", function()
    it("applies it on the retry, without warning", function()
      local win = fakeWindow({ x = 2556, y = -500, w = 1000, h = 800 }, DELL, { dropRequests = 1 })
      press(env, ctl, win, core.go, 'up')
      assert.same({ x = 2556, y = -800, w = 1000, h = 1065 }, win.current)
      assert.same({}, env.warnings)
    end)

    it("warns if the retry is ignored too", function()
      local win = fakeWindow({ x = 2556, y = -500, w = 1000, h = 800 }, DELL, { dropRequests = 3 })
      press(env, ctl, win, core.go, 'up')
      assert.equal(1, #env.warnings)
    end)
  end)

  it("advances the cycle on a repeat press that beats the settle check", function()
    local win = fakeWindow({ x = 2556, y = -500, w = 1000, h = 800 }, DELL)
    ctl.run(win, core.go, 'up')
    ctl.run(win, core.go, 'up')
    env.runScheduled()
    assert.equal(1419, win.current.h)
  end)

  it("restarts the cycle when the window changed screens", function()
    local win = fakeWindow({ x = 2556, y = -500, w = 1000, h = 800 }, DELL)
    press(env, ctl, win, core.go, 'up')
    press(env, ctl, win, core.go, 'up')  -- at 2/3 on the Dell
    win.screen = LAPTOP
    win.current = { x = 100, y = 40, w = 1000, h = 500 }
    press(env, ctl, win, core.go, 'up')
    assert.equal(645, win.current.h)
  end)

  it("restarts the cycle when the window was dragged", function()
    local win = fakeWindow({ x = 2556, y = -500, w = 1000, h = 800 }, DELL)
    press(env, ctl, win, core.go, 'up')
    press(env, ctl, win, core.go, 'up')
    win.current = { x = 2556, y = -500, w = 1000, h = 700 }
    press(env, ctl, win, core.go, 'up')
    assert.equal(1065, win.current.h)
  end)

  it("remembers each window separately", function()
    local a = fakeWindow({ x = 2556, y = -500, w = 1000, h = 800 }, DELL)
    local b = fakeWindow({ x = 2556, y = -500, w = 1000, h = 800 }, DELL)
    function b.id() return 2 end
    press(env, ctl, a, core.go, 'up')
    press(env, ctl, a, core.go, 'up')
    press(env, ctl, b, core.go, 'up')
    assert.equal(1065, b.current.h)
    press(env, ctl, a, core.go, 'up')
    assert.equal(710, a.current.h)
  end)

  describe("across restarts", function()
    local function restart() ctl = controller.new(env) end
    local start = { x = 2556, y = -500, w = 1000, h = 800 }

    it("continues the cycle", function()
      local win = fakeWindow(start, DELL)
      press(env, ctl, win, core.go, 'up')
      restart()
      press(env, ctl, win, core.go, 'up')
      assert.equal(1419, win.current.h)
    end)

    it("still returns the window to where it was before fullscreen", function()
      local win = fakeWindow(start, DELL)
      press(env, ctl, win, core.fullscreen)
      restart()
      press(env, ctl, win, core.fullscreen)
      press(env, ctl, win, core.fullscreen)
      press(env, ctl, win, core.fullscreen)
      assert.same(start, win.current)
    end)

    it("doesn't mistake a different app's window with a reused id for the old one", function()
      local win = fakeWindow(start, DELL)
      press(env, ctl, win, core.fullscreen)
      restart()
      function win.app() return 'Other' end
      win.current = { x = 2056, y = -800, w = 3840, h = 2129 }
      press(env, ctl, win, core.fullscreen)  -- enters the cycle at full size: nothing to restore
      press(env, ctl, win, core.fullscreen)
      press(env, ctl, win, core.fullscreen)
      assert.equal(DELL.w, win.current.w)
    end)
  end)

  it("stores a bounded number of windows, dropping the least recently used", function()
    local function windowWithId(id)
      local win = fakeWindow({ x = 2556, y = -500, w = 1000, h = 800 }, DELL)
      function win.id() return id end
      return win
    end
    local first = windowWithId(1)
    press(env, ctl, first, core.go, 'up')
    for id = 2, 500 do press(env, ctl, windowWithId(id), core.go, 'up') end
    local count = 0
    for _ in pairs(env.stored) do count = count + 1 end
    assert.equal(64, count)
    assert.is_nil(env.stored['1'])
    assert.is_not_nil(env.stored['500'])
  end)

  it("survives a window that closed before the check", function()
    local win = fakeWindow({ x = 2556, y = -500, w = 1000, h = 800 }, DELL)
    ctl.run(win, core.go, 'up')
    win.current = nil
    assert.has_no.errors(env.runScheduled)
  end)
end)

# MiroWindowsManager

A [Hammerspoon](https://www.hammerspoon.org) Spoon for arranging macOS windows from the keyboard: send a window to an edge or corner of the screen with the arrow keys, and repeat the key to cycle through sizes.

This is a fork of [miro-windows-manager](https://github.com/miromannino/miro-windows-manager) by Miro Mannino, who designed this way of arranging windows and wrote the original Spoon. This fork reimplements it and has different settings, so it isn't a drop-in replacement, and problems here are the fork's rather than Miro's.

## How to install

Copy `MiroWindowsManager.spoon` to `~/.hammerspoon/Spoons`, then add this to your `init.lua`:

``` lua
hs.loadSpoon("MiroWindowsManager")
local hyper = {"ctrl", "alt", "cmd"}
spoon.MiroWindowsManager:bindHotkeys({
  up          = {hyper, "up"},
  down        = {hyper, "down"},
  left        = {hyper, "left"},
  right       = {hyper, "right"},
  fullWidth   = {hyper, "left+right"},
  fullHeight  = {hyper, "up+down"},
  fullscreen  = {hyper, "f"},
  center      = {hyper, "c"},
  move        = {hyper, "v"},
  resize      = {hyper, "d"},
})
hs.window.animationDuration = 0.3
```

## Shortcuts

With the snippet above, every shortcut starts with `hyper`: `ctrl` + `alt` + `cmd`.

### Edges and sizes

`hyper` + an arrow moves the window to that edge of the screen. Repeating it cycles through `sizes`.

### Corners

Press two perpendicular arrows, such as `hyper` + `up` + `right`. Each axis cycles through sizes on its own.

### Full width or height

 - `fullWidth`: `hyper` + `left` + `right`
 - `fullHeight`: `hyper` + `up` + `down`

So that a chord doesn't also trigger its keys' own actions, keys used in chords act when released rather than when pressed, and only if they weren't part of a chord.

### Fullscreen

`hyper` + `f` cycles through `fullScreenSizes`. The `'c'` entry returns the window to where it was before it started cycling.

### Center

`hyper` + `c` centres the window without resizing it.

### Move mode

Hold `hyper` + `v` and tap an arrow to move the window by `moveStep` points.

### Resize mode

Hold `hyper` + `d` and tap an arrow to resize the window by `resizeStep` points: `up` is taller, `down` is shorter, `left` is thinner and `right` is wider. An edge touching the side of the screen stays there.

## Settings

Set these on `spoon.MiroWindowsManager`:

 - `sizes`: fractions of the screen to cycle through at an edge, such as `{1/2, 1/3, 2/3}`
 - `fullScreenSizes`: fractions of the screen for the fullscreen cycle, such as `{1, 1/2, 'c'}`
 - `moveStep`, `resizeStep`, `minSize`, `edgeTolerance`: in points

Windows that don't take the requested frame are logged as warnings in the Hammerspoon console.

The Spoon remembers each window's cycle position and pre-fullscreen frame across Hammerspoon restarts, for up to 64 recently used windows, in `hs.settings`.

## Tests

Run `busted` from the repository root. Placement logic is in `core.lua` and tests without Hammerspoon. `controller.lua` tests against simulated windows.

## Animations

The snippet above configures the animation to last `0.3s` with `hs.window.animationDuration = 0.3`. To remove the animations completely change this value to `0`.

## License (MIT)

Copyright (c) 2018 Miro Mannino

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

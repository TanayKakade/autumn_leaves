# 🍂 AutumnLeaves

Autumn leaves drift down over your Mac desktop and pile up on your windows and the Dock. One Swift file, every leaf drawn in code.

## What it does

- Red, orange, amber, brown and gold leaves (maple, oval, birch and oak shapes), in three depth layers with a breeze and occasional gusts
- Leaves tumble as they fall
- Leaves pile up on top of every window and on the Dock (or the bottom of the screen)
- Drag a window and its leaves fly off; the faster you drag, the farther they go
- Swish the mouse quickly through a pile to scatter the leaves
- Close or minimize a window and its leaves fall
- Clicks pass straight through the overlay, so it never gets in your way

## Run it

```
cd AutumnLeaves
zsh build.sh
```

If `swiftc` is missing, run `xcode-select --install` first. Use the 🍂 icon in the menu bar to pause, choose light, medium or heavy leaf fall, turn mouse swish off, sweep up all the leaves, or quit.

## Make it yours

All the settings are in `enum Cfg` at the top of `AutumnLeaves.swift`: leaf count, fall speed, pile height, swish strength. The colors are in `palette`. Edit, then run `zsh build.sh` again.

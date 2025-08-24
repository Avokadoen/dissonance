# Dissonance

A scene editor for raylib+ecez+zig.

## Requirements

- zig 0.14.1

## How to run 

```bash
git clone https://github.com/Avokadoen/dissonance
cd dissonance
zig build run
```

## features

Currently early days for this, but there are some nice features already:

- Auto generated field editing widgets
- Allow overwriting field widgets by exposing a function on components called `sceneEditorOverrideWidget`
- Save/load scenes - you can also append scenes onto other scenes (currently changes does not propagate between them)
- ?
# Dissonance

A scene editor using [box2d](https://github.com/erincatto/box2d), [raylib](https://github.com/raysan5/raylib), [ecez](https://github.com/Avokadoen/ecez) and [zig](https://github.com/ziglang/zig/).

## Requirements

- zig 0.15.1

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
# Asterage 2P

Multiplayer space dogfighting

## Current Status

Counts frames.

## About RCade

This game is built for [RCade](https://rcade.recurse.com), a custom arcade
cabinet at The Recurse Center. Learn more about the project at
[github.com/fcjr/RCade](https://github.com/fcjr/RCade).

## Prerequisites

Zig 0.16.0

## Testing

Start the development server:

```
zig build serve
```

## Development Build

```
zig build
```

Builds with debug symbols and assertions enabled. Output goes to `zig-out/`.

## Production Build

```
zig build --release -p dist
```

Builds an optimized production bundle. Output goes to `dist/` and is ready for
deployment.

### Development Keyboard Controls

When developing locally, keyboard inputs are mapped to arcade controls:

**Classic Controls (`@rcade/plugin-input-classic`)**

| Player   | Action           | Key |
|----------|------------------|-----|
| Player 1 | UP               | W   |
| Player 1 | DOWN             | S   |
| Player 1 | LEFT             | A   |
| Player 1 | RIGHT            | D   |
| Player 1 | A Button         | F   |
| Player 1 | B Button         | G   |
| Player 2 | UP               | I   |
| Player 2 | DOWN             | K   |
| Player 2 | LEFT             | J   |
| Player 2 | RIGHT            | L   |
| Player 2 | A Button         | ;   |
| Player 2 | B Button         | '   |
| System   | One Player Start | 1   |
| System   | Two Player Start | 2   |

**Spinner Controls (`@rcade/plugin-input-spinners`)**

| Player   | Action        | Key |
|----------|---------------|-----|
| Player 1 | Spinner Left  | C   |
| Player 1 | Spinner Right | V   |
| Player 2 | Spinner Left  | .   |
| Player 2 | Spinner Right | /   |

Spinners repeat at ~60Hz while held.

---

Made with <3 at [The Recurse Center](https://recurse.com)

# Web Game Prototype

Browser version of the Space Invaders game core used for fast UI and gameplay
iteration before the FPGA implementation.

## Run

```powershell
node .\server.mjs
```

Open `http://127.0.0.1:4173`.

## Controls

- `A` / `D` or `Left` / `Right`: move
- `Space`: fire
- `P`: pause
- `R`: restart
- Touch controls are available on phones and tablets

## Gesture Integration

The game exposes a small command bridge for future browser gesture recognition:

```js
window.fpgaInvaders.setGestureCommand({
  left: true,
  right: false,
  fire: false,
});
```

Use `releaseGestureCommand()` to clear the current gesture input.

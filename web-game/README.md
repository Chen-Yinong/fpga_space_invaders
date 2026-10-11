# Web Game Prototype

Browser version of the Space Invaders game core used for fast UI and gameplay
iteration before the FPGA implementation.

## Run

**Windows 一键启动（推荐给队友）**：双击 `run-windows.bat`，会自动启动本地服务器并打开浏览器。

手动启动：

```powershell
node .\server.mjs
```

然后打开 `http://127.0.0.1:4173`。

> **重要**：不要直接双击 `index.html` 打开游戏。通过 `file://` 打开时，浏览器会禁止
> Phaser 用 XHR 读取 SVG 材质，画面会显示成一个个方块（默认缺失贴图）。
> 必须先运行本地服务器（HTTP），材质才能正常加载。

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

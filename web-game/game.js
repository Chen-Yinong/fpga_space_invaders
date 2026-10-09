(() => {
  "use strict";

  const GAME_WIDTH = 960;
  const GAME_HEIGHT = 640;
  const PLAYER_Y = GAME_HEIGHT - 52;
  const FORMATION_START_X = 225;
  const FORMATION_START_Y = 118;
  const FORMATION_COLUMNS = 10;
  const FORMATION_ROWS = 5;
  const FORMATION_X_GAP = 58;
  const FORMATION_Y_GAP = 48;
  const COLORS = {
    background: 0x02040d,
    ink: "#f5f7ff",
    muted: "#92a3c8",
    cyan: 0x5ee7ff,
    green: 0x7bf7c8,
    amber: 0xffca62,
    pink: 0xff648c,
    violet: 0xa88cff,
  };

  const dom = {
    startPanel: document.querySelector("#start-panel"),
    pausePanel: document.querySelector("#pause-panel"),
    gameOverPanel: document.querySelector("#game-over-panel"),
    gameOverTitle: document.querySelector("#game-over-title"),
    gameOverScore: document.querySelector("#game-over-score"),
    startButton: document.querySelector("#start-button span"),
    restartButton: document.querySelector("#restart-button span"),
    controlMode: document.querySelector("#control-mode"),
    moveLeft: document.querySelector("#move-left"),
    moveRight: document.querySelector("#move-right"),
    fire: document.querySelector("#fire-button"),
    pause: document.querySelector("#pause-button"),
    reset: document.querySelector("#reset-button"),
    resume: document.querySelector("#resume-button"),
  };

  function showPanel(panel) {
    [dom.startPanel, dom.pausePanel, dom.gameOverPanel].forEach((item) => {
      item.classList.toggle("is-visible", item === panel);
      item.setAttribute("aria-hidden", item === panel ? "false" : "true");
    });
  }

  function formatScore(value) {
    return String(value).padStart(6, "0");
  }

  class SpaceInvadersScene extends Phaser.Scene {
    constructor() {
      super("space-invaders");
      this.state = "ready";
      this.score = 0;
      this.lives = 3;
      this.wave = 1;
      this.direction = 1;
      this.fireCooldown = 0;
      this.enemyStepTimer = null;
      this.enemyFireTimer = null;
      this.ufoTimer = null;
      this.keyboard = {};
      this.touch = { left: false, right: false, fire: false };
      this.gesture = { left: false, right: false, fire: false };
      this.lastMode = "KEYBOARD";
      this.reducedEffects = false;
      this.performanceFrame = 0;
    }

    preload() {
      this.load.svg("space-background", "./assets/space-bg.svg", {
        width: GAME_WIDTH,
        height: GAME_HEIGHT,
      });
      this.load.svg("player", "./assets/player.svg", { width: 72, height: 54 });
      this.load.svg("player-thrust", "./assets/player-thrust.svg", { width: 28, height: 42 });
      this.load.svg("invader-a", "./assets/invader-a.svg", { width: 50, height: 43 });
      this.load.svg("invader-b", "./assets/invader-b.svg", { width: 50, height: 43 });
      this.load.svg("invader-c", "./assets/invader-c.svg", { width: 50, height: 43 });
      this.load.svg("ufo", "./assets/ufo.svg", { width: 82, height: 39 });
      this.load.svg("player-bullet", "./assets/player-bolt.svg", { width: 10, height: 32 });
      this.load.svg("enemy-bullet", "./assets/enemy-bolt.svg", { width: 10, height: 27 });
      this.load.svg("shield-cell", "./assets/shield-cell.svg", { width: 10, height: 10 });
    }

    create() {
      this.physics.world.setBounds(12, 0, GAME_WIDTH - 24, GAME_HEIGHT);
      this.createBackground();
      this.createGroups();
      this.createPlayer();
      this.createHud();
      this.createColliders();
      this.bindInput();
      document.addEventListener("visibilitychange", () => {
        if (document.hidden && this.state === "playing") {
          this.togglePause();
        }
      });
      this.resetFormation();
      this.resetShields();
      this.updateHud();
      this.physics.world.pause();
      showPanel(dom.startPanel);
      dom.startButton.parentElement.disabled = false;

      window.fpgaInvaders = {
        start: () => this.startRun(),
        pause: () => this.togglePause(),
        restart: () => this.startRun(),
        nextWave: () => this.handlePanelAction(),
        setGestureCommand: (command = {}) => this.setGestureCommand(command),
        releaseGestureCommand: () => this.setGestureCommand({}),
        getState: () => ({
          state: this.state,
          score: this.score,
          lives: this.lives,
          wave: this.wave,
          enemies: this.enemies?.countActive(true) || 0,
          playerX: this.player?.x || 0,
          playerBullets: this.playerBullets?.countActive(true) || 0,
          enemyBullets: this.enemyBullets?.countActive(true) || 0,
          ufoActive: Boolean(this.ufo?.active) || this.ufoGroup.countActive(true) > 0,
          fps: Math.round(this.game.loop.actualFps || 0),
          renderer: this.game.renderer.type === Phaser.WEBGL ? "WEBGL" : "CANVAS",
        }),
      };
    }

    createBackground() {
      this.add.image(0, 0, "space-background").setOrigin(0, 0);
    }

    createGroups() {
      this.playerBullets = this.physics.add.group({ allowGravity: false });
      this.enemyBullets = this.physics.add.group({ allowGravity: false });
      this.enemies = this.physics.add.group({ allowGravity: false });
      this.shieldBlocks = this.physics.add.staticGroup();
      this.ufoGroup = this.physics.add.group({ allowGravity: false });
    }

    createPlayer() {
      this.playerThrust = this.add.image(GAME_WIDTH / 2, PLAYER_Y + 24, "player-thrust");
      this.playerThrust.setDepth(9);
      this.player = this.physics.add.image(GAME_WIDTH / 2, PLAYER_Y, "player");
      this.player.setCollideWorldBounds(true);
      this.player.setDepth(10);
      this.player.setMaxVelocity(360, 0);
    }

    createHud() {
      this.add.rectangle(0, 0, GAME_WIDTH, 68, 0x050c1d, 0.62)
        .setOrigin(0, 0)
        .setDepth(19);
      this.add.rectangle(0, 68, GAME_WIDTH, 1, COLORS.cyan, 0.18)
        .setOrigin(0, 0)
        .setDepth(19);

      const style = {
        fontFamily: 'Bahnschrift, "Aptos Display", "Segoe UI", sans-serif',
        fontSize: "16px",
        color: COLORS.ink,
        letterSpacing: 1,
      };
      const labelStyle = {
        ...style,
        fontSize: "11px",
        color: COLORS.muted,
      };

      this.add.text(24, 18, "SCORE", labelStyle).setDepth(20);
      this.scoreText = this.add.text(24, 34, "000000", {
        ...style,
        fontSize: "21px",
        color: "#5ee7ff",
      }).setDepth(20);

      this.add.text(GAME_WIDTH / 2 - 42, 18, "WAVE", labelStyle).setOrigin(0, 0).setDepth(20);
      this.waveText = this.add.text(GAME_WIDTH / 2, 34, "01", {
        ...style,
        fontSize: "21px",
        color: "#a88cff",
      }).setOrigin(0.5, 0).setDepth(20);

      this.livesLabel = this.add.text(GAME_WIDTH - 24, 18, "LIVES", labelStyle)
        .setOrigin(1, 0)
        .setDepth(20);
      this.lifeIcons = Array.from({ length: 3 }, (_, index) => {
        return this.add.image(GAME_WIDTH - 38 - index * 22, 43, "player")
          .setScale(0.18)
          .setDepth(20);
      });
    }

    createColliders() {
      this.physics.add.overlap(
        this.playerBullets,
        this.enemies,
        this.handleBulletHitsEnemy,
        undefined,
        this,
      );
      this.physics.add.overlap(
        this.playerBullets,
        this.shieldBlocks,
        this.handleShieldHit,
        undefined,
        this,
      );
      this.physics.add.overlap(
        this.enemyBullets,
        this.shieldBlocks,
        this.handleShieldHit,
        undefined,
        this,
      );
      this.physics.add.overlap(
        this.enemyBullets,
        this.player,
        this.handlePlayerHit,
        undefined,
        this,
      );
      this.physics.add.overlap(
        this.player,
        this.enemies,
        this.handleInvasion,
        undefined,
        this,
      );

      this.physics.add.overlap(
        this.playerBullets,
        this.ufoGroup,
        this.handleUfoHit,
        undefined,
        this,
      );
    }

    bindInput() {
      this.keyboard = this.input.keyboard.addKeys({
        left: Phaser.Input.Keyboard.KeyCodes.LEFT,
        right: Phaser.Input.Keyboard.KeyCodes.RIGHT,
        a: Phaser.Input.Keyboard.KeyCodes.A,
        d: Phaser.Input.Keyboard.KeyCodes.D,
        space: Phaser.Input.Keyboard.KeyCodes.SPACE,
        p: Phaser.Input.Keyboard.KeyCodes.P,
        r: Phaser.Input.Keyboard.KeyCodes.R,
      });

      this.input.keyboard.addCapture([
        Phaser.Input.Keyboard.KeyCodes.LEFT,
        Phaser.Input.Keyboard.KeyCodes.RIGHT,
        Phaser.Input.Keyboard.KeyCodes.SPACE,
      ]);

      this.input.keyboard.on("keydown-P", () => this.togglePause());
      this.input.keyboard.on("keydown-R", () => this.startRun());
      this.input.keyboard.on("keydown-SPACE", () => this.tryFire());

      this.bindHoldButton(dom.moveLeft, "left", "TOUCH");
      this.bindHoldButton(dom.moveRight, "right", "TOUCH");
      this.bindHoldButton(dom.fire, "fire", "TOUCH");
      dom.pause.addEventListener("click", () => this.togglePause());
      dom.reset.addEventListener("click", () => this.startRun());
      dom.resume.addEventListener("click", () => this.resumeRun());
      dom.startButton.parentElement.addEventListener("click", () => this.startRun());
      dom.restartButton.parentElement.addEventListener("click", () => this.handlePanelAction());
    }

    bindHoldButton(element, command, mode) {
      const activate = (event) => {
        event.preventDefault();
        this.touch[command] = true;
        element.classList.add("is-active");
        element.setPointerCapture?.(event.pointerId);
        this.setMode(mode);
      };
      const release = (event) => {
        event.preventDefault();
        this.touch[command] = false;
        element.classList.remove("is-active");
      };

      element.addEventListener("pointerdown", activate);
      element.addEventListener("pointerup", release);
      element.addEventListener("pointercancel", release);
      element.addEventListener("lostpointercapture", release);
    }

    setMode(mode) {
      if (mode === "GESTURE" && !this.hasGestureCommand()) {
        mode = "KEYBOARD";
      }

      if (this.lastMode !== mode) {
        this.lastMode = mode;
        dom.controlMode.textContent = mode;
      }
    }

    setGestureCommand(command) {
      this.gesture.left = Boolean(command.left);
      this.gesture.right = Boolean(command.right);
      this.gesture.fire = Boolean(command.fire);
      this.setMode(this.hasGestureCommand() ? "GESTURE" : "KEYBOARD");
    }

    hasGestureCommand() {
      return this.gesture.left || this.gesture.right || this.gesture.fire;
    }

    startRun() {
      this.score = 0;
      this.lives = 3;
      this.wave = 1;
      this.beginPlay();
    }

    beginPlay() {
      this.state = "playing";
      this.direction = 1;
      this.fireCooldown = 0;
      this.gesture = { left: false, right: false, fire: false };
      showPanel(null);
      this.physics.world.resume();
      this.player.setPosition(GAME_WIDTH / 2, PLAYER_Y);
      this.player.setAlpha(1);
      this.player.setRotation(0);
      this.player.setVelocity(0, 0);
      this.playerThrust.setPosition(GAME_WIDTH / 2, PLAYER_Y + 24);
      this.playerThrust.setAlpha(0.55);
      this.clearProjectiles();
      this.resetFormation();
      this.resetShields();
      this.ufoGroup.clear(true, true);
      this.ufo = null;
      this.updateHud();
      this.scheduleEnemyEvents();
      this.setMode("KEYBOARD");
    }

    togglePause() {
      if (this.state === "playing") {
        this.state = "paused";
        this.player.setVelocityX(0);
        this.playerThrust.setAlpha(0.2);
        this.physics.world.pause();
        showPanel(dom.pausePanel);
      } else if (this.state === "paused") {
        this.resumeRun();
      }
    }

    resumeRun() {
      if (this.state !== "paused") {
        return;
      }

      this.state = "playing";
      this.physics.world.resume();
      this.playerThrust.setAlpha(0.55);
      showPanel(null);
    }

    handlePanelAction() {
      if (this.state === "victory") {
        this.nextWave();
        return;
      }

      this.startRun();
    }

    nextWave() {
      this.wave += 1;
      this.state = "playing";
      this.direction = 1;
      this.physics.world.resume();
      this.clearProjectiles();
      this.player.setPosition(GAME_WIDTH / 2, PLAYER_Y);
      this.player.setAlpha(1);
      this.player.setRotation(0);
      this.playerThrust.setPosition(GAME_WIDTH / 2, PLAYER_Y + 24);
      this.playerThrust.setAlpha(0.55);
      this.resetFormation();
      this.updateHud();
      showPanel(null);
      this.scheduleEnemyEvents();
    }

    scheduleEnemyEvents() {
      this.enemyStepTimer?.remove(false);
      this.enemyFireTimer?.remove(false);
      this.ufoTimer?.remove(false);

      this.enemyStepTimer = this.time.addEvent({
        delay: this.getEnemyStepDelay(),
        loop: true,
        callback: this.stepFormation,
        callbackScope: this,
      });
      this.enemyFireTimer = this.time.addEvent({
        delay: Math.max(360, 780 - this.wave * 45),
        loop: true,
        callback: this.fireEnemyBullet,
        callbackScope: this,
      });
      this.ufoTimer = this.time.addEvent({
        delay: 15000,
        loop: true,
        callback: this.spawnUfo,
        callbackScope: this,
        startAt: 9000,
      });
    }

    resetFormation() {
      this.enemies.clear(true, true);

      for (let row = 0; row < FORMATION_ROWS; row += 1) {
        for (let column = 0; column < FORMATION_COLUMNS; column += 1) {
          const texture = row === 0 ? "invader-c" : row < 3 ? "invader-b" : "invader-a";
          const points = row === 0 ? 30 : row < 3 ? 20 : 10;
          const enemy = this.enemies.create(
            FORMATION_START_X + column * FORMATION_X_GAP,
            FORMATION_START_Y + row * FORMATION_Y_GAP,
            texture,
          );

          enemy.setData("points", points);
          enemy.setDepth(8);
          enemy.body.setSize(38, 32);
          enemy.setData("baseScale", 1);
        }
      }
    }

    resetShields() {
      this.shieldBlocks.clear(true, true);
      const bunkerCenters = [206, 389, 571, 754];

      bunkerCenters.forEach((centerX) => {
        for (let row = 0; row < 7; row += 1) {
          for (let column = 0; column < 9; column += 1) {
            const topCut = row === 0 && (column < 2 || column > 6);
            const notchCut = row >= 4 && column >= 3 && column <= 5;
            const legCut = row === 6 && column !== 1 && column !== 7;

            if (topCut || notchCut || legCut) {
              continue;
            }

            const block = this.shieldBlocks.create(
              centerX + (column - 4) * 8,
              GAME_HEIGHT - 145 + row * 8,
              "shield-cell",
            );
            block.setDepth(7);
          }
        }
      });
    }

    clearProjectiles() {
      this.playerBullets.clear(true, true);
      this.enemyBullets.clear(true, true);
    }

    getEnemyStepDelay() {
      const alive = this.enemies.countActive(true);
      return Phaser.Math.Clamp(760 - (FORMATION_ROWS * FORMATION_COLUMNS - alive) * 8, 165, 760);
    }

    stepFormation() {
      if (this.state !== "playing") {
        return;
      }

      const enemies = this.enemies.getChildren().filter((enemy) => enemy.active);
      if (!enemies.length) {
        return;
      }

      const stepX = 8;
      const minX = Math.min(...enemies.map((enemy) => enemy.x - 18));
      const maxX = Math.max(...enemies.map((enemy) => enemy.x + 18));
      const hitsEdge =
        (this.direction > 0 && maxX + stepX >= GAME_WIDTH - 22) ||
        (this.direction < 0 && minX - stepX <= 22);
      const targetY = Math.max(...enemies.map((enemy) => enemy.y + (hitsEdge ? 16 : 0)));
      const targetXOffset = hitsEdge ? 0 : this.direction * stepX;
      const duration = Phaser.Math.Clamp(this.enemyStepTimer.delay * 0.45, 65, 95);

      enemies.forEach((enemy) => {
        this.tweens.killTweensOf(enemy);
        this.tweens.add({
          targets: enemy,
          x: enemy.x + targetXOffset,
          y: enemy.y + (hitsEdge ? 16 : 0),
          duration,
          ease: "Sine.easeInOut",
        });
      });

      if (hitsEdge) {
        this.direction *= -1;
      }

      const reachedBottom = targetY >= PLAYER_Y - 46;
      if (reachedBottom) {
        this.endRun(false);
        return;
      }

      this.enemyStepTimer.delay = this.getEnemyStepDelay();
    }

    fireEnemyBullet() {
      if (this.state !== "playing" || this.enemyBullets.countActive(true) >= 7) {
        return;
      }

      const candidates = this.enemies
        .getChildren()
        .filter((enemy) => enemy.active)
        .sort((a, b) => b.y - a.y)
        .slice(0, FORMATION_COLUMNS);

      if (!candidates.length) {
        return;
      }

      const shooter = Phaser.Utils.Array.GetRandom(candidates);
      const bullet = this.enemyBullets.create(shooter.x, shooter.y + 24, "enemy-bullet");
      bullet.setVelocityY(255 + this.wave * 18);
      bullet.setDepth(10);
    }

    spawnUfo() {
      if (this.state !== "playing" || this.ufoGroup.countActive(true) > 0) {
        return;
      }

      this.ufo = this.ufoGroup.create(-40, 82, "ufo");
      this.ufo.setDepth(9);
      this.ufo.setVelocityX(135);
    }

    handleBulletHitsEnemy(bullet, enemy) {
      if (!bullet.active || !enemy.active) {
        return;
      }

      const points = enemy.getData("points") || 10;
      bullet.destroy();
      enemy.destroy();
      this.addScore(points, enemy.x, enemy.y);
      this.createExplosion(enemy.x, enemy.y, COLORS.green);
      this.cameras.main.shake(45, 0.0018);
      this.enemyStepTimer.delay = this.getEnemyStepDelay();

      if (this.enemies.countActive(true) === 0) {
        this.victory();
      }
    }

    handleUfoHit(bullet, ufo) {
      if (!bullet.active || !ufo.active) {
        return;
      }

      bullet.destroy();
      const x = ufo.x;
      const y = ufo.y;
      ufo.destroy();
      this.ufo = null;
      this.addScore(100, x, y);
      this.createExplosion(x, y, COLORS.cyan);
    }

    handleShieldHit(bullet, block) {
      if (!bullet.active || !block.active) {
        return;
      }

      bullet.destroy();
      block.destroy();
    }

    handlePlayerHit(_player, bullet) {
      if (this.state !== "playing") {
        return;
      }

      bullet.destroy();
      this.lives -= 1;
      this.updateHud();
      this.enemyBullets.clear(true, true);
      this.createExplosion(this.player.x, this.player.y, COLORS.pink);
      this.cameras.main.shake(130, 0.007);

      if (this.lives <= 0) {
        this.endRun(false);
        return;
      }

      this.player.setPosition(GAME_WIDTH / 2, PLAYER_Y);
      this.tweens.add({
        targets: this.player,
        alpha: 0.2,
        yoyo: true,
        repeat: 3,
        duration: 90,
      });
    }

    handleInvasion() {
      if (this.state === "playing") {
        this.endRun(false);
      }
    }

    tryFire() {
      if (this.state !== "playing" || this.fireCooldown > this.time.now) {
        return;
      }

      if (this.playerBullets.countActive(true) >= 3) {
        return;
      }

      const bullet = this.playerBullets.create(this.player.x, this.player.y - 34, "player-bullet");
      bullet.setVelocityY(-680);
      bullet.setDepth(11);
      this.fireCooldown = this.time.now + 190;
    }

    addScore(points, x, y) {
      this.score += points;
      this.updateHud();

      const popup = this.add.text(x, y - 12, `+${points}`, {
        fontFamily: 'Bahnschrift, "Aptos Display", "Segoe UI", sans-serif',
        fontSize: "14px",
        color: "#a9f8ff",
      }).setOrigin(0.5).setDepth(30);

      this.tweens.add({
        targets: popup,
        y: popup.y - 24,
        alpha: 0,
        duration: 620,
        onComplete: () => popup.destroy(),
      });
    }

    updateHud() {
      if (!this.scoreText) {
        return;
      }

      this.scoreText.setText(formatScore(this.score));
      this.waveText.setText(String(this.wave).padStart(2, "0"));
      this.lifeIcons.forEach((icon, index) => {
        icon.setVisible(index < Math.max(0, this.lives));
      });
    }

    createExplosion(x, y, color) {
      const shardCount = this.reducedEffects ? 5 : 13;
      const ring = this.add.circle(x, y, 6, color, 0.08)
        .setStrokeStyle(2, color, 0.8)
        .setDepth(28);

      this.tweens.add({
        targets: ring,
        scale: 4.5,
        alpha: 0,
        duration: 420,
        ease: "Quad.easeOut",
        onComplete: () => ring.destroy(),
      });

      for (let index = 0; index < shardCount; index += 1) {
        const shard = this.add.circle(x, y, Phaser.Math.Between(1, 3), color)
          .setDepth(29)
          .setAlpha(0.9);
        const angle = Phaser.Math.FloatBetween(0, Math.PI * 2);
        const distance = Phaser.Math.Between(18, 52);

        this.tweens.add({
          targets: shard,
          x: x + Math.cos(angle) * distance,
          y: y + Math.sin(angle) * distance,
          alpha: 0,
          scale: 0.1,
          duration: Phaser.Math.Between(260, 520),
          ease: "Quad.easeOut",
          onComplete: () => shard.destroy(),
        });
      }
    }

    victory() {
      this.state = "victory";
      this.physics.world.pause();
      this.enemyStepTimer?.remove(false);
      this.enemyFireTimer?.remove(false);
      this.ufoTimer?.remove(false);
      this.player.setVelocity(0, 0);
      this.playerThrust.setAlpha(0.12);
      dom.gameOverTitle.textContent = "SECTOR CLEARED";
      dom.gameOverScore.textContent = `SCORE ${formatScore(this.score)}`;
      dom.restartButton.textContent = "NEXT WAVE";
      showPanel(dom.gameOverPanel);
    }

    endRun(won) {
      if (this.state === "gameover") {
        return;
      }

      this.state = "gameover";
      this.physics.world.pause();
      this.enemyStepTimer?.remove(false);
      this.enemyFireTimer?.remove(false);
      this.ufoTimer?.remove(false);
      this.player.setVelocity(0, 0);
      this.playerThrust.setAlpha(0.12);
      dom.gameOverTitle.textContent = won ? "SECTOR CLEARED" : "GAME OVER";
      dom.gameOverScore.textContent = `SCORE ${formatScore(this.score)}`;
      dom.restartButton.textContent = "RESTART";
      showPanel(dom.gameOverPanel);
    }

    updateControls(time) {
      const left = this.keyboard.left.isDown || this.keyboard.a.isDown || this.touch.left || this.gesture.left;
      const right =
        this.keyboard.right.isDown || this.keyboard.d.isDown || this.touch.right || this.gesture.right;
      const fire = this.keyboard.space.isDown || this.touch.fire || this.gesture.fire;

      if (this.state !== "playing") {
        return;
      }

      let velocity = 0;
      if (left !== right) {
        velocity = left ? -340 : 340;
      }
      this.player.setVelocityX(velocity);
      this.player.setRotation((velocity / 340) * 0.075);
      this.playerThrust.setPosition(this.player.x, this.player.y + 24);
      this.playerThrust.setAlpha(0.55 + Math.sin(time * 0.018) * 0.12);
      this.playerThrust.setScale(1, velocity === 0 ? 0.82 : 1.08);

      if (fire) {
        this.tryFire();
      }

      if (this.hasGestureCommand()) {
        this.setMode("GESTURE");
      } else if (this.touch.left || this.touch.right || this.touch.fire) {
        this.setMode("TOUCH");
      } else {
        this.setMode("KEYBOARD");
      }
    }

    cleanProjectiles() {
      this.playerBullets.getChildren().forEach((bullet) => {
        if (bullet.active && bullet.y < -24) {
          bullet.destroy();
        }
      });

      this.enemyBullets.getChildren().forEach((bullet) => {
        if (bullet.active && bullet.y > GAME_HEIGHT + 24) {
          bullet.destroy();
        }
      });
    }

    update(time) {
      if (this.state !== "playing") {
        return;
      }

      this.updateControls(time);
      this.cleanProjectiles();

      this.performanceFrame += 1;
      if (this.performanceFrame % 90 === 0) {
        this.reducedEffects = (this.game.loop.actualFps || 60) < 50;
      }

      if (this.ufo?.active && this.ufo.x > GAME_WIDTH + 70) {
        this.ufo.destroy();
        this.ufo = null;
      }
    }
  }

  const config = {
    type: Phaser.AUTO,
    parent: "game",
    width: GAME_WIDTH,
    height: GAME_HEIGHT,
    backgroundColor: COLORS.background,
    pixelArt: false,
    antialias: true,
    render: {
      powerPreference: "high-performance",
    },
    fps: {
      target: 120,
      min: 60,
      smoothStep: false,
    },
    physics: {
      default: "arcade",
      arcade: {
        gravity: { y: 0 },
        debug: false,
      },
    },
    scale: {
      mode: Phaser.Scale.FIT,
      autoCenter: Phaser.Scale.CENTER_BOTH,
    },
    scene: SpaceInvadersScene,
  };

  new Phaser.Game(config);
})();

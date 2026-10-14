# Manual hot-seat test (Climb and Slither, one window)

The unit tests cover rules, layout, animation plans and screen logic. This checklist is for what
only your eyes and hands can judge: how it looks, feels and reads. Hot-seat means everyone plays
in one window, taking turns at the same computer. The network controller comes after this.

## Launch

- **Editor:** open the project in Godot 4.7 and press F5 (the main scene is `main/main.tscn`).
- **Command line:** `"$GODOT_BIN" --path .` from the repo root (the same `GODOT_BIN` the tests use,
  but the normal binary also works; the console one prints errors to the terminal).
- Try the window at **1280x720** (the default) and at **1920x1080** (maximise it or run with
  `--resolution 1920x1080`). Also drag the window edges to resize it.

## Checklist

Tick each line; write what you saw next to anything that is off.

**Home screen**
- [ ] "Climb and Slither" is listed with its description. Clicking it opens the setup.
- [ ] Setup: player count 2, 3 or 4; each name box fills in "Player N" and can be edited; names
      keep what you typed when you change the count.
- [ ] Empty names and two equal names (even with different capitals) show a message and do not start.
- [ ] "Exact finish" and "Two dice" cannot both be on: turning one on greys out the other, and
      hovering the greyed one says why. A switched-on option can always be switched off.
- [ ] "Back" returns to the list.

**The board (look at both window sizes)**
- [ ] Ten even rows of ten squares, readable numbers, none hidden under a snake or ladder.
- [ ] Every snake's head and tail sit on their squares (compare against `docs/` rules or the data
      file `games/climb_and_slither/data/classic_board.json`).
- [ ] Every ladder's top and foot sit on their squares.
- [ ] Pawns draw above snakes and ladders, and several pawns on one square do not hide each other.
- [ ] Pawns waiting to start stand in the "Start" strip under square 1.
- [ ] Nothing is cut off at 1280x720; at 1920x1080 the board is bigger, not lost in empty space.

**Playing**
- [ ] The highlighted row and the button ("Roll for Ben") agree about whose turn it is.
- [ ] Rolling tumbles the die, lands on a face, then the pawn hops square by square.
- [ ] Landing on a ladder slides the pawn up, on a snake slides it down.
- [ ] While things animate the Roll button is greyed and "Skip animation" shows. Clicking skip, or
      pressing Space/Enter, jumps to the finished position. Space/Enter also rolls when it can.
- [ ] Speed 0.5x / 1x / 2x / Instant change how fast it plays; Instant has no waiting at all.
- [ ] The square numbers in the player list match where the pawns actually are.
- [ ] With "Roll again after a 6": a 6 shows "<name> rolls again" and the same player rolls again.
- [ ] With "Exact finish": overshooting near the end shows "<name> needs exactly N" and the pawn shakes.
- [ ] With "Two dice": two dice show; the pawn moves their total.

**Finishing**
- [ ] The "<name> wins!" panel appears only after the last animation is done (use 0.5x to check).
- [ ] "Play again" starts a fresh game with the same players and settings (everyone back at Start,
      no old dice). "Back to menu" returns to the list.
- [ ] Leaving mid-game via "Back to menu" asks first; leaving after the game is over does not.

**Feel**
- [ ] Anything that felt slow, fussy or confusing? Anything you could not tell without squinting?
- [ ] Fonts: names with accents or Hindi letters (try typing one) draw properly in the lists.

## Reporting back

Say which lines failed (or paste this file with notes). Screenshot helper if useful:
`"$GODOT_BIN" --path . --rendering-driver opengl3 --resolution 1280x720 -s games/climb_and_slither/tools/render_game_screen.gd -- <folder>`
saves the home screen, setup, a game in progress and the game-over panel.

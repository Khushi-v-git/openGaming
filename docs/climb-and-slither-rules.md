# Climb and Slither: rules module

Pure logic in `games/climb_and_slither/rules/` (no nodes, no UI, no networking, no timers).
Everything is plain data, so it saves, replays and fuzzes. Classes:

| class | what |
|---|---|
| `ClimbAndSlitherRules` | `new_game`, `apply`, `settle`, `view_for`, `validate_state` |
| `ClimbBoard` | load and validate board data (`data/classic_board.json`) |
| `ClimbSettings` | house rules and their defaults |
| `ClimbReplay` | record and re-run a game |
| `ClimbErrors` | error codes (generic ones come from core's `ErrorCodes`) |

## House rules (live in the state)

| setting | default | |
|---|---|---|
| `exact_finish` | false | must land exactly on the last square; an overshooting roll does not move |
| `extra_turn_on_six` | false | roll again after a 6 (either die with two dice); no cap |
| `dice_count` | 1 | 1 or 2. `exact_finish` needs 1 (with two dice the square before the last could never be finished) |

**For the host settings screen:** "exact finish" and "2 dice" exclude each other. The screen must
not decide that itself: call `ClimbSettings.option_states(current_settings)`, which returns
`{exact_finish: {enabled, tooltip}, two_dice: {enabled, tooltip}}`. Grey out whatever is not
`enabled` and show its `tooltip` (an option that is already chosen stays enabled so it can be
switched off). `ClimbSettings.normalize` still refuses the combination as a second line of defence.

## Board rules

Every start square is unique and is not square 1 or the last square; snakes go down, ladders go
up; no jump ends on another jump's start (so no chains and no loops: a landing triggers at most
one jump); shared end squares are fine. The last square must also be reachable under every allowed settings combination (one die with
exact finish, one die without it, two dice without it; `ClimbSettings.allowed_combinations()`): a
search from square 0 over that combination's rolls (1 to 6, or 2 to 12) plus the jumps has to get
there, modelled exactly (with exact finish an overshoot does not move, without it an overshoot
lands on the last square). Six snake heads in a row make a wall one die cannot cross, and a trap
near the start can lock everyone in. In practice the first combination decides (if one die with
exact finish can win, the other two can too; tests check that on hundreds of random boards), but
each is checked separately. The error names the combination and says how far anyone can get. `ClimbBoard.validate` enforces
all of it; `ClimbBoard.reachable_squares(board, dice_count, exact_finish)` returns the squares a player can stand on
(useful for a board editor).

## How the host drives it

```gdscript
var rules := ClimbAndSlitherRules.new()

# when the lobby starts the game (seat order = lobby seat order)
var created := rules.new_game(player_ids, ClimbBoard.load_file()["board"], settings, seed)
state = created["state"]          # HOST-ONLY: contains the dice generator (rng)

# a player's "game_action" arrives from LobbyHost
var result := rules.apply(state, player_id, action, lobby_host.active_players())
if result["ok"]:
    state = result["state"]
    # broadcast {events, view_for(state, id)} per player on this turn boundary: never `state`
else:
    # send result["error"] back to that player only; state is unchanged

# when the host chooses "continue without waiting", or someone leaves/returns
var settled := rules.settle(state, lobby_host.active_players())   # skips an absent current player

# LobbyHost.game_view_provider: a rejoining player gets their view
lobby_host.game_view_provider = func(id): return rules.view_for(state, id)

# saving: pass `state` as the game_state of LobbyHost.snapshot(); on loading run validate_state first
```

* The only action is `{"type": "roll"}`. The dice come from the generator in the state; any extra
  field is refused, so a client cannot pick its dice.
* `view_for` leaves out `rng`. Send views, never raw state (rule 9).
* `events` (not part of the state) are what a UI animates: `rolled`, `moved` (with every square
  walked), `overshoot`, `jumped`, `extra_turn`, `turn_changed`, `turn_skipped`, `won`. A UI that
  follows only the events always matches the true state (there is a test for exactly that).
* Errors: `NOT_YOUR_TURN`, `GAME_OVER`, `PLAYER_INACTIVE`, `UNKNOWN_PLAYER`, `UNKNOWN_ACTION`,
  `BAD_ACTION`, `INVALID_STATE`; the state you passed in is never modified.

## Dice are reproducible everywhere

Rolls come from core's `Prng` (xoshiro128**), not Godot's `RandomNumberGenerator`, so a seed
gives the same game on every Godot version and platform. Seed and state are stored as decimal
strings (JSON numbers cannot hold 64 bits). `tests/test_determinism.gd` pins whole games that
were played by an independent Python implementation of the written rules.

## Replays

`ClimbReplay.run({players, board, settings, seed, steps})` reproduces a game from its actions
(plus `settle` steps and per-step `active_players`). A refused step records its `expect_error`.
When the fuzz test (`tests/test_fuzz.gd`) finds a problem it prints the failing game's replay; paste
it into `ClimbReplay.from_text` in a new test to reproduce it.

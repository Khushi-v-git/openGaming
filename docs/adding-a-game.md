# Adding a game

How a new game goes from an idea to something friends can play online. Read `CLAUDE.md` first
(the architecture rules are not repeated here) and use Climb and Slither (`games/climb_and_slither/`)
as the worked example. Adding a game must not require editing `core/`; if it seems to, stop and ask.

## 1. Decide what to build

A game fits this app when:
- it is **turn-based** (or phase-based), for a small table (2 to 8 players);
- the **host can decide everything**: no real-time reflexes, no timers inside the rules;
- anything **hidden** (hands, secret choices) can be kept on the host and shown per player (`view_for`);
- it is **traditional/public domain or your own design**. Mechanics cannot be copied from a commercial game's
  rulebook, and names must be original or traditional (Ludo, Carrom, Chess ... are fine; no
  trademarked variants). See "Legal and naming" in `CLAUDE.md`.

Write one paragraph: players, goal, what a turn is, what is random, what is hidden.

## 2. Collect and write down the rules

1. Read the rules of 2 or 3 versions of the game (and of similar games). Note where they differ.
2. Choose the version you implement and list the differences you will offer as **house rules**
   (settings), each with a default. House rules are settings, never hard-coded.
3. Write `docs/<game>-rules.md` in your own words: setup, turn, every action, end, edge cases (what if
   a player is away, what if nobody can move), and the settings. Do not copy a rulebook's wording.
4. List the **invalid combinations** of settings now (Climb: exact finish needs one die).

## 3. Design

Settle these before writing code; they become the tests.
- **State** (plain data, JSON-safe, versioned: `state_version`). Host-only fields (the `Prng`
  seed/state, deck order, secrets) stay out of `view_for`.
- **Actions** a player sends (`{"type": "roll"}`, `{"type": "play_card", "card": 3}`): small, plain data.
- **Events** the rules return for the UI to animate (`rolled`, `moved`, `won` ...): ordered dicts with a `type`.
- **Views**: what each player may see (`view_for(state, player_id)`, whitelist of keys).
- **Who may act when** (see "Several people acting" below).
- **Randomness**: only through the seeded `Prng` (one documented draw order; changing it breaks saves).
- **Screens**: board/table, side panel, pause and game-over cards. Use the Claude Design project for the look
  (papercut style, palette in `CLAUDE.md`), and ask for 1280x720 and 1920x1080.

## 4. Build it on the existing network layer

Folder (same layout in every game):
```
games/<id>/
  manifest.json      id, display_name, description, icon, min/max_players, min_active_players,
                     rules_class, ui_scene, optional settings_scene   (see core/registry/game_manifest.gd)
  rules/             pure logic, extends GameRules, no nodes
  data/              boards, card lists ...
  ui/                game screen scene + scripts, optional settings panel
  assets/            game art (baked shadows already? then no in-engine shadow)
  tests/
```
Steps, each with its tests and a commit (rules first, screens later):
1. **Rules class** (`extends GameRules`): `new_game`, `apply`, `settle`, `view_for`, `validate_state`,
   `is_finished`, `current_player`, `winner`, plus `default_setup`, `validate_settings`, `describe_settings`.
   `apply` never changes its input and returns `{ok, state, events}` or an error; it takes
   `active_players` and must skip absent players (`TurnOrder`).
2. **Rules tests** (headless): legal moves, illegal actions rejected with state unchanged, turn rotation,
   absent players, game over locks actions, setting validation, data validation. Add a **fuzz** test
   (thousands of seeded games that all finish with valid state), a **replay** (seed + actions), and
   **golden games** from an independent implementation when the rules are subtle.
3. **Network proof, free of charge**: copy the pattern of `games/climb_and_slither/tests/climb_network_contract.gd`
   and its three thin files (loopback, fake relay, direct WebSocket): a whole game over the network, per-player views
   (the random state never on the wire), illegal actions refused, settle on absence, rejoin, rematch, settings.
   The generic suites in `tests/core/` (`game_network_contract.gd`, `controller_contract.gd`) already prove the layer
   itself; yours proves your rules work through it.
4. **UI scene** (`ui/<game>_screen.tscn`): root has `setup(controller, players)` and the signals
   `leave_requested` and `game_ended`. It talks only to a `GameController` (hot-seat, host and guest all look the same
   to it), shows each batch through an `EventTimeline`, and contains no rules (rule 12). Reuse `PresenceOverlay`,
   `ConfirmDialog`, `PaperCard`, `LeafBorder` from `core/ui/`. Board-like layouts are the one place math placement is allowed.
5. **Settings scene** (optional): root with `settings()` and a `changed(settings)` signal; grey out invalid combinations
   using the rules' own function (`ClimbSettings.option_states` is the model).
6. **Manifest**, then run the app: the home screen lists the game from the registry. Hot-seat first, then
   `scripts/run_network_manual_test.sh`, then a friend over the relay (`docs/manual-network-test.md`).
7. **Docs and credits**: the rules doc, a line in the README credits for art or traditions, licences for assets.

Before saying done: the full test suite (`scripts/run_tests.sh`) and, if you touched anything near transports,
`scripts/run_integration_tests.sh`.

## Several people acting (trading, auctions, simultaneous choices)

What the network already does: the host accepts a `game_action` from **any** player at **any** time and gives the rules the
acting `player_id`; the rules decide whether that player may act now. So an out-of-turn action (accept a trade, bid,
reveal a choice) is just another action, and the host sends every player a batch with their own view (a private offer can
be shown only to the two players involved).

What is not built, so decide it when the first such game is designed (ask before changing core):
- **`current_player` is a single id.** Screens use it to enable the main button, and the hot-seat controller uses it to
  pick who acts. A phase where several players may act needs a convention (for example `current_player` = the main
  player, plus a `waiting_for` list in the view that the screen reads).
- **No table talk.** There is no chat message. Players can talk by voice, or the game can offer fixed phrases or an
  `emote` action; free text would be a protocol change.
- **No timers.** Rules cannot use time, so "offer expires in 30 s" needs a host-side timer outside the rules that sends a
  normal action (`expire_offer`) back through `apply`.
- **Pause**: a trade with an absent player pauses the game like any other action (host decides: wait, continue, remove).
  The rules must say what happens to an open offer then.
- Keep messages small and per decision, never per frame (rule 11).

## Checklist

- [ ] Fits the model (section 1) and the legal check is done
- [ ] Rules written down (`docs/<game>-rules.md`), settings and invalid combinations listed
- [ ] Rules class + unit, fuzz, replay tests, all headless
- [ ] Network contract tests on all three transports
- [ ] UI scene (hot-seat and networked), settings scene, manifest
- [ ] Looks right at 1280x720 and 1920x1080
- [ ] Manual hot-seat and online tests; full suite green
- [ ] README credits, `CLAUDE.md` updated if a rule changed (ask first)

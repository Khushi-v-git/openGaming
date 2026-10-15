# Grow & Trade: state, actions, events, views

The contract between the rules modules in `games/grow_and_trade/rules/`. Rules text is in
`grow-and-trade-rules.md`. All data is plain and JSON-safe (ints stay ints, ids are strings).

## Modules

| File | Job |
|---|---|
| `gt_errors.gd` | error code constants |
| `gt_state.gd` | shared read helpers over a state (order, hands, pieces, ports, points, offers) |
| `gt_score.gd` | points, bonus refresh, win check |
| `gt_setup.gd` | settings normalize/describe, `new_game` state building, `validate_state` |
| `gt_view.gd` | `view_for` (whitelist) |
| `gt_founding.gd` | the two founding rounds |
| `gt_build.gd` | path / village / town, free paths |
| `gt_turn.gd` | roll, payout, 7 (discard, blocker), buy/play cards, end turn, settle |
| `gt_trade.gd` | bank trade, player offers |
| `grow_and_trade_rules.gd` | `GrowAndTradeRules extends GameRules`: dispatch and queries only |

Every action module is static: `GtX.method(state, board, player_id, action) -> Dictionary` returning
`{ok, state, events}` or `CoreResult.failure(code, message)`. Each works on a **copy** (`state.duplicate(true)`),
never the input. `board` is a `GtBoard` the dispatcher builds from `state.board` (cache it per call).
The `Prng` is restored from `state.rng` where needed and written back (`seed_text`/`state_text`).

## State

```
state_version: 1            game_id: "grow_and_trade"
phase: "founding" | "playing" | "finished"
settings: {target_points: 10, hand_limit: 7, bank_rate: 4, friendly_blocker: false, cancel_offers_on_absence: false}
config:   the validated costs config (GtBank.validate_config output), embedded
board:    the clean board data (GtBoard.validate output), embedded
layout:   {tiles: [{q,r,type,token}], harbors: [{q,r,side,edge,kind,ratio,corners}]}   (GtBoard.layout output)
blocker:  {q, r}            the tile the blocker stands on (starts on the first desert)
players:  [{player_id, color}]   seat order; colors red, blue, green, yellow, orange, purple
hands:    {pid: {timber,clay,fleece,wheat,stone: int}}     PRIVATE
supply:   {resource: int}   the bank
buildings:{corner_id: {owner: pid, kind: "village"|"town"}}
paths:    {edge_id: pid}
cards:    {pid: {held: [type], fresh: [type]}}             PRIVATE (types: guard two_paths harvest sweep point)
          fresh = bought this turn; moved to held when that player's turn ends
guards_played: {pid: int}
deck:     [type]            top at index 0                 HOST-ONLY
bonuses:  {longest_path: pid|"", largest_guard: pid|""}
founding: {order: [pid], index: int, expect: "village"|"path", last_village: corner_id|""}   {} once done
          order = seats then seats reversed (length 2n); index points at the current placer
turn:     {rolled: bool, dice: [int], card_played: bool, free_paths: int,
           pending: ""|"discard"|"move_blocker", owed: {pid: int}, source: ""|"seven"|"guard"}
offer:    {} | {from: pid, give: {res:int}, want: {res:int}, to: [pid] (empty = everyone),
                accepted: [pid], declined: [pid]}
current_player: pid         turn_number: int       winner: pid | ""
rng: {seed, state}          HOST-ONLY decimal strings
```

Derived (never stored): pieces left (config.pieces minus placed), a player's ports (from `layout.harbors` and
the player's buildings), points, hand counts.

## Phases and who may act

- **founding**: only `current_player` (= `founding.order[founding.index]`), only `place_village` when
  `expect == "village"`, then `place_path` (edge must touch `last_village`) when `expect == "path"`. After the
  second village (index >= n) it pays one resource per adjacent producing tile from the bank (shortage rule). After
  the last path: `phase = "playing"`, `current_player = seat 1`, `founding = {}`.
- **playing, pending == ""**: the turn owner acts. Not rolled yet: `roll`, `play_card` (guard only, see rules),
  nothing else. After rolling: build, trade, buy, play card, `end_turn`.
- **pending == "discard"**: only players in `turn.owed` with count > 0 may act, and only `discard`. When all owed
  are zero, `pending` becomes `"move_blocker"` (if source is seven) or the turn goes on.
- **pending == "move_blocker"**: only the turn owner, only `move_blocker`.
- **offer open**: any non-owner player listed (or anyone if `to` is empty) may `accept_trade` / `decline_trade`
  once; the owner may `choose_trade_partner` (an accepter), `withdraw_offer`, or just keep playing.
  `end_turn` cancels an open offer.
- **finished**: every action is refused with `GAME_OVER`.
- Absent players: `apply` refuses actions from players not in `active_players` (`PLAYER_INACTIVE`) unless
  `active_players` is empty. Turn rotation uses `TurnOrder.next_active`. `settle` hands the turn on if the owner is
  absent, auto-discards (random, from the state's rng) for absent owed players, and cancels the open offer if
  `cancel_offers_on_absence`.

## Actions

All have `type`; extra or missing fields are `BAD_ACTION`. Ids are strings, resource maps are `{res: positive int}`.

```
place_village {corner}              place_path {edge}                 (founding)
roll {}
build_path {edge}   build_village {corner}   build_town {corner}
buy_card {}         play_card {card: "guard"|"two_paths"|"harvest"|"sweep"|"point"?, ...}
    guard {} ; two_paths {} ; harvest {resources: [res, res]} ; sweep {resource: res}   (point cards are never played)
move_blocker {q, r, victim?: pid}   discard {resources: {res:int}}
bank_trade {give: res, get: res}
offer_trade {give: map, want: map, to?: [pid]}   accept_trade {}   decline_trade {}
choose_trade_partner {player: pid}   withdraw_offer {}
end_turn {}
```

## Events (ordered, plain dicts with `type`)

`founding_placed {player_id, kind: "village"|"path", at}` , `rolled {player_id, dice, total}`,
`produced {gains: {pid: map}, tiles: [{q,r,token}]}`, `shortage {resource, owed, available, claimants, paid}`,
`nothing_produced {}`, `discard_required {owed: {pid: n}}`, `discarded {player_id, count}`,
`blocker_moved {player_id, q, r}`, `stole {player_id, victim}` (never says which resource: events are public, the thief
sees the card arrive in their own hand view),
`built {player_id, kind, at}`, `card_bought {player_id}`, `card_played {player_id, card}`,
`harvest_taken`, `swept {player_id, resource, total}`, `bank_traded {player_id, give, get, rate}`,
`offer_made {from, give, want, to}`, `offer_accepted {player_id}`, `offer_declined {player_id}`,
`trade_done {from, with, give, want}`, `offer_cancelled {reason}`, `bonus_changed {bonus, from, to}`,
`turn_changed {player_id}`, `turn_skipped {player_id}`, `won {player_id}`.

## Views (`view_for(state, pid)`, whitelist)

Public: state_version, game_id, phase, settings, board, layout, blocker, players, supply, buildings, paths,
guards_played, bonuses, founding, turn (without nothing hidden), offer, current_player, turn_number, winner.
Per player: `you`, `hand` (own, exact), `hand_counts {pid: int}`, `card_counts {pid: int}` (held + fresh),
`my_cards {held, fresh}`, `deck_remaining: int`, `points {pid: int}` counting only public points (buildings,
bonuses) plus the viewer's own point cards. When finished, `points` is the full tally and point cards are revealed.
Never in a view: `hands` of others, `cards` of others, `deck` order, `rng`, `config` secrets (config is public data).

## Errors (`GtErrors`)

INVALID_STATE, INVALID_SETTINGS, BAD_PLAYERS, INVALID_BOARD (from GtBoard), NOT_YOUR_TURN, GAME_OVER, PLAYER_INACTIVE,
NO_ACTIVE_PLAYERS, WRONG_PHASE (action not allowed now), ALREADY_ROLLED, NOT_ROLLED, BAD_PLACEMENT (occupied,
too close, not connected, not on the board), NO_PIECES, CANNOT_AFFORD, CARD_NOT_AVAILABLE, CARD_ALREADY_PLAYED,
NO_SUCH_CARD, OFFER_INVALID, NO_OFFER, NOT_ADDRESSED, ALREADY_ANSWERED, NOT_AN_ACCEPTER, MUST_DISCARD, BAD_DISCARD,
BAD_BLOCKER_MOVE, BAD_VICTIM, plus the generic ErrorCodes (UNKNOWN_ACTION, BAD_ACTION, UNKNOWN_PLAYER).

## Random draws (stable; changing them breaks saves, bump state_version)

1. `new_game`: board layout (GtBoard.layout order), then the deck shuffle (GtDeck.new_deck).
2. `roll`: die 1 then die 2, each `range_int(1, 6)`.
3. steal: `range_int(0, hand_count - 1)` over the victim's hand expanded in resource order timber, clay, fleece, wheat, stone.
4. absent discards (`settle`): one `range_int` per card removed, over the hand expanded in resource order.

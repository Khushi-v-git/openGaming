# Grow & Trade: rules

Original rules text for `games/grow_and_trade/`. A turn-based island-building game for 3 to 6 players
(a larger board for the bigger table). Mechanics only; names and wording are our own (see "Legal and naming"
in `CLAUDE.md`). Numbers marked *(data)* live in data files, not in rules code, so they can be tuned.

## Idea in one paragraph

Players found a village on a shared island of hex tiles, collect resources from the tiles next to their
buildings whenever the dice match, and spend them on paths, villages, towns and fortune cards. They trade with
each other and with the bank. First to reach the target number of points on their own turn wins. Randomness: dice,
board layout, card deck order. Hidden: each player's resource hand, unplayed fortune cards, the deck order.

## Resources and pieces

- Five resources: **timber, clay, fleece, wheat, stone**. Desert tiles produce nothing.
- Pieces per player *(data)*: 15 paths, 5 villages, 4 towns.
- Costs: path = timber + clay. Village = timber + clay + fleece + wheat. Town upgrade = 3 stone + 2 wheat.
  Fortune card = fleece + wheat + stone.
- Bank supply per resource *(data)*: 24 for 3 to 4 players, 30 for 5 to 6. If the bank cannot pay everyone
  what the dice give, see "Shortage".

## The board

- A board is data: a list of hex coordinates (axial), a tile-type pool, a number-token pool, and harbor
  positions. The 5 to 6 player board has 30 land hexes *(data)*; a smaller 3 to 4 player board may be added later.
- **Layout is random** from the seeded `Prng`: tile types are shuffled onto the hexes, number tokens (2 to 12,
  never 7) are shuffled onto non-desert tiles, harbors are shuffled onto their coastal slots.
- Placement constraint: two high-yield tokens (6 or 8) may not sit on touching tiles. The shuffle retries
  (bounded) until this holds; board validation proves a valid layout exists.
- Buildings sit on hex corners, paths on hex edges.
- **Harbors**: a coastal edge pair that gives a better bank rate to any player with a building on it. Generic
  harbors give 3:1 on any resource; resource harbors give 2:1 on one resource.
- Board validation (like Climb's): all hexes connected, token and tile counts match the hex count, harbors sit
  on coast, every non-desert tile gets a token.

## Setup

1. Seat order is the lobby order. The `Prng` seed shuffles the board and the deck.
2. **Founding round 1**, in seat order: each player places one village and one path touching it.
3. **Founding round 2**, in reverse seat order: each places a second village and a path touching it. The second
   village pays out one resource for each adjacent producing tile, taken from the bank.
4. Placement distance rule: a village may not be placed on a corner adjacent to another building (the
   "one gap" rule). Founding villages may go anywhere that satisfies it; later villages must also touch one of
   the player's own paths.
5. After founding, play starts with seat 1.

## A turn

1. **Roll** two dice (one `range_int(1, 6)` draw each, in order). Mandatory first step.
   - On 2 to 6 or 8 to 12: every tile with that token pays each adjacent building: 1 resource per village,
     2 per town, from the bank. A tile covered by the blocker pays nothing.
   - On **7**: nobody collects. Every player holding more than the **hand limit** *(setting, default 7)* discards
     half of their hand (rounded down), chosen by that player. Then the turn owner **moves the blocker** to
     any other tile and takes one random resource from one player who has a building there (if any).
2. **Main phase**, any order, any number of times while affordable and pieces remain:
   - build a path, village or town (rules below);
   - trade with the bank;
   - trade with players (see "Trading");
   - buy a fortune card; play at most one fortune card per turn (not one bought this turn).
3. **End turn.** The next present player in seat order starts at step 1.

A fortune card played before the roll is allowed (the "knight-style" guard card, see below).

### Building

- **Path**: on an empty edge touching the player's own building or path, but a path may not continue through
  another player's building.
- **Village**: on an empty corner satisfying the distance rule and touching one of the player's paths. +1 point.
- **Town**: replaces one of the player's own villages (the village piece returns to their supply). +2 points total.
- Out of pieces of a kind: cannot build that kind.

### Trading

- **Bank**: 4 of one resource for 1 of another. 3:1 with a generic harbor. 2:1 with the matching resource
  harbor. Only on the player's own turn.
- **Between players**: only the turn owner proposes, during their main phase ("I give these, I want those"),
  to everyone or to one named player. Each recipient answers **accept** or **decline**; answering is the one
  thing a non-turn player may do. When at least one has accepted, the turn owner **chooses** one accepter and the
  swap happens, if both still hold the cards (checked again at that moment). The turn owner may also withdraw
  the offer. There are no counter-offers in v1: the turn owner posts a new offer instead.
- One open offer at a time; a new one replaces it. An open offer is cancelled when the turn ends.
- **Absent player**: while a player is away the game is paused by the host, so nothing resolves. An open offer
  stays open and idle (default); setting `cancel_offers_on_absence` cancels it instead.
- The view shows each player only their own hand, the open offer, and who has accepted or declined it.

### Fortune cards

Bought blind from a deck of 25 *(data)* (shuffled by the `Prng`, order host-only). Types and counts *(data)*:
- **Guard** (14): move the blocker as on a 7 (no discard).
- **Two paths** (2): build two paths free.
- **Harvest** (2): take any 2 resources from the bank.
- **Monopoly-style claim** (2), named **Sweep**: name a resource; every other player gives you all of it.
- **Point card** (5): 1 point each; never played, revealed when it wins.
A card cannot be played the turn it was bought, except a point card that completes the winning total.

### Bonuses

- **Longest road** is named **Longest Path**: 2 points to the player with the longest unbroken chain of at least
  5 paths (a rival building on the chain breaks it). Ties keep the current holder; if nobody holds it, a tie at
  the top gives it to no one.
- **Largest army** is named **Largest Guard**: 2 points to the first player with at least 3 played Guard
  cards; taken by a player who strictly exceeds the holder.

### Points and the end

- Points: village 1, town 2, Longest Path 2, Largest Guard 2, each point card 1.
- Target *(setting, default 10, range 8 to 14)*. A player wins **as soon as** they have the target on their own turn,
  so a bonus lost to a rival is only checked on that rival's turn, and the check happens after any action
  of the turn owner. Other players' points are never decisive off-turn.
- After the game ends, no further actions are accepted until the host rematches or ends the game.

### Shortage

If the bank has too few of one resource to pay what a roll gives:
- if only one player is owed that resource, they get what is left;
- if several are owed, nobody gets that resource this roll.
Other resources are paid normally.

## Edge cases

- **Nobody can do anything useful**: a turn can always end after the roll; there is no forced build.
- **Blocker with no victims**: it moves, no steal.
- **Hand of exactly the limit**: only *more than* the limit discards.
- **Out of fortune cards**: buying is refused.
- **Player removed for good**: their pieces stay on the board as obstacles (their paths still break chains
  and block distances), their hand returns to the bank, and they are skipped.
- **Player away**: turn rotation skips them (`TurnOrder`), and they keep their seat. If they owe a discard the
  discard is done randomly by the host when the game continues without them.

## Settings (house rules)

| Setting | Values | Default |
|---|---|---|
| `target_points` | 8 to 14 | 10 |
| `hand_limit` | 5 to 12 | 7 |
| `cancel_offers_on_absence` | on/off | off |
| `bank_rate` | 4, 3 (no harbor needed) | 4 |
| `friendly_blocker` | on/off: blocker may not be moved onto a tile where the only victim has 2 or fewer points | off |

Invalid combinations: none among the above. Board and player count are checked by `validate_settings`:
the 30-hex board needs 5 or 6 players for the default bank size; 3 or 4 players on it is allowed
with the smaller bank, but the manifest lists the game as 3 to 6 players.

## Actions (for the design step)

`roll`, `place_village`, `place_path` (founding and normal), `build_village`, `build_path`, `build_town`,
`buy_card`, `play_card`, `move_blocker`, `discard`, `bank_trade`, `offer_trade`, `accept_trade`, `decline_trade`,
`choose_trade_partner`, `withdraw_offer`, `end_turn`. `discard` (after a 7), `accept_trade` and `decline_trade`
are the only actions a non-turn player sends.

## Notes

- Online only: there is no hot-seat mode. Every player answers offers and discards on their own screen, which
  also lets the rules rely on hidden hands (rule 9) without a shared screen leaking them.
- 5 to 6 players: a "special build phase" (build-only turn for non-owners) to cut waiting is out of scope for v1.

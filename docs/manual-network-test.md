# Manual network test checklist

The automated suite covers loopback, the fake relay, direct WebSocket on localhost and (the
integration tier) a real local relay. It cannot cover firewalls, real Wi-Fi, other operating
systems, the deployed relay or a tunnel. Do these tests in order, as CLAUDE.md says: two
instances, then LAN, then the deployed relay with a friend on another network. Do not start the
next one until the previous one passes.

| test | what | needs |
|---|---|---|
| A | direct address, several windows on one PC | this PC |
| B | direct address, two computers on the same Wi-Fi | a second computer |
| C | direct address through a tunnel (the fallback) | a friend, a tunnel you set up |
| D | relay, several windows on one PC | Node, a local relay (the script starts it) |
| E | relay, two computers on the same Wi-Fi | a second computer, a deployed relay |
| F | relay, a friend on another network | a friend, a deployed relay |

## Before you start

- Everyone runs the **same commit** (`git rev-parse --short HEAD`), so app version and
  protocol match. Note the hash.
- Use the Godot **console** build so you can capture the log, and start the real game (the
  project's main scene):

  ```
  "%GODOT_BIN%" --path . -- --name=Asha > asha.log 2>&1
  ```

  (`--name=` prefills the name; more options are listed in `scripts/run_network_manual_test.sh`.)
- **One-command setup on one PC:** `scripts/run_network_manual_test.sh` opens a host and up to
  three guests as separate windows, with logs in a temp folder it prints.

  ```
  scripts/run_network_manual_test.sh direct --players=3     # test A
  scripts/run_network_manual_test.sh relay  --players=3     # test D (also starts a local relay)
  ```

  The guests join and tick ready by themselves; you press **Start game** in the host window.
  Enter in the terminal stops only the windows and relay the script started.
- Debug builds log every message as `[net HH:MM:SS.mmm] -> player=p2 peer=2 type=...`
  (never payloads). Keep the logs; they are the evidence if something fails.
- Open the log of each instance after the test and look for `ERROR` and `SCRIPT ERROR`.

### The screens you will use

- **Home:** the game list. Pick **Climb and Slither**, then **Host game** or **Join game** (or
  **Play on this computer** for hot-seat).
- **Connection box** (on the host and join screens): *Host with* (**Room code (relay)** or
  **Direct address**), the **relay address** field (paste any relay's address; it is remembered),
  and a **Test** button that opens and closes a test room and says whether the relay works. The
  port field only shows for direct hosting.
- **Host lobby:** shows what to share (**Share this room code** or **Share this address**) with a
  **Copy** button, and a **public address** field to override the shown address (see C and F).
  The host panel sets the **house rules** (exact finish, roll again after a 6, two dice, need a 1
  to start; incompatible ones are greyed out with a reason). Each guest sees a **read-only
  summary** of those rules.
- **In a game:** the board, the players list with whose turn it is, **Roll**, and overlays for
  *paused* (a player dropped), *game over* (**Play again** / **Back to lobby**) and *connection
  lost*.

## What to record for every test

Copy this block into your notes once per test:

```
Test:            (A two instances / B LAN / C tunnel / D relay local / E relay LAN / F relay friend)
Date, tester:
Commit / app version / Godot version:
Host: OS, Godot build, how it connects (Ethernet/Wi-Fi), host address or room code shown in the app
Clients: OS, how they connect, address or code typed
Time from pressing Join to seeing the lobby (seconds):
Checklist result: list each item as PASS / FAIL / SKIPPED, with a note on every FAIL
Anything odd (lag, flicker, wrong text, a button that did nothing):
Logs attached: host.log, <client>.log
```

For every FAIL record: what you did, what you expected, what happened, the exact on-screen
text, and the log lines around the time (copy 20 lines either side).

## The game checks (used by A, B, D, E and F)

Run these once the lobby is full and the host has pressed **Start game**.

1. Every window opens the game with the same board and the same players; each window's own pawn
   colour matches its row. The first player's **Roll** is enabled; everyone else's is not.
2. **Turns across windows:** roll in the right window; every window shows the dice and the pawn
   moving, and the turn marker moves. Rolling out of turn is impossible (button greyed).
   Play 10 turns; record any window that showed a different position than the others.
3. **House rules reach the game:** with "Roll again after a 6" or "Need a 1 to start" on, the
   game behaves that way in *every* window (banner text appears in all of them).
4. **Pause overlay (rule 7):** close a guest's window (or kill the process). Within about 20 s
   (direct) or about 50 s (relay) the host and the other guests show a **Game paused: waiting
   for <name>** overlay and nobody can roll.
   - Host presses **Keep waiting** (or does nothing): the game stays paused.
   - Host presses **Continue without waiting**: play resumes for the people present; if it was
     the absent player's turn it passes on. The absent player's seat stays.
   - Host presses **Remove** on the absent player: the seat is gone for good.
5. **Rejoin:** (a) with the window still open, switch its network off for 5 s and on; press
   **Rejoin** and you are back in the same seat with the current board. (b) Start a window again
   with the *same name* (the app was restarted): the host is asked to let you in; **Let in** puts
   you back in the same seat; **Decline** refuses. A different name is refused ("already started").
6. **Game over:** play to the end (or roll quickly). Every window shows the winner after the last
   animation. Only the host sees **Play again** and **Back to lobby**. **Play again** starts a
   fresh game for everyone with the same players and rules; **Back to lobby** returns everyone
   to the lobby (anyone who was away loses their seat; everyone must get ready again).
7. **Host closes:** the host leaves mid-game: guests see a "connection lost / session closed"
   screen with a way back to the home screen. **Host process killed:** guests notice within about
   20 s (direct) or about a minute (relay) and offer **Rejoin** (it only works if the host comes
   back; a restarted host opens a *new* room with a new code).

## A. Several windows on one PC (direct address)

Setup: `scripts/run_network_manual_test.sh direct`, or start the real game yourself in as many
windows as you like (`--name=Host`, `--name=Guest1`, ...).

1. Host picks **Host game**, chooses **Direct address**, presses **Host**. The screen shows
   "Starting your game..." briefly, then the lobby with `Share this address: <ip>:24680`. Record the
   address.
2. Guest picks **Join game**, types `127.0.0.1:24680` (not the shown address) and presses **Join**.
   Record the time to the lobby. Both windows list both players; the guest's row says "(you)".
3. Guest ticks **I'm ready**. Host sees "Ready". Host's **Start game** enables. Set a house rule
   first (for example "Roll again after a 6"); the guest's summary shows it. Press **Start game**:
   both windows open the game. Run **the game checks** above.
4. Before starting, try the other actions:
   - Guest unticks and reticks ready; host row updates each time.
   - Host presses **Remove** on the guest: guest returns to the start screen with
     "Left the session: You were removed by the host." and no Rejoin button.
   - Guest joins again; presses **Leave**: guest returns to start without an error;
     host list shrinks.
5. Mistakes: join with an empty name, an empty address, `127.0.0.1:1` (a closed port; it
   should say "Could not join" after about 10 seconds and offer Join again), and `abc` (it must
   say it needs an address or a room code, not hang). Press **Cancel** while it is connecting:
   you must get back to the start screen at once.
6. Start a second host on the same port (a third instance, or `--port=` the same): it must
   say "Could not host: cannot listen on port 24680".
7. Third and fourth guests join (fourth seat full): a fifth gets "This room is full."
8. **Guest process killed:** end the guest's process in Task Manager (not Leave).
   - In the open lobby the guest's row disappears from the host within about 15 seconds
     (the ping timeout) or at once if Windows closes the socket.
   - After the game has started the row stays and says "Disconnected", and the host shows the
     pause overlay with **Continue without waiting**. The other players cannot act while it is
     paused (game check 4).
   - **Restart the app with the same name** and join the same address: the guest sees
     "Waiting for the host to let you back in." with Cancel, and the host shows
     "<name> wants to rejoin" with **Let in** / **Decline**. Let in: the guest is back in the
     same seat and the board matches the others, the pause overlay disappears. Repeat with
     Decline: the guest gets "The host did not let you back in" and the seat stays open. Repeat
     with Cancel on the guest: the host's request disappears.
   - A *different* name while the seat is open must still say "This game has already
     started." Press **Remove** on the absent player's row, then try their name again: also
     "already started" (the seat is gone).
   Also: press **Leave** (not Task Manager) on a guest in a started game: the seat is kept
   the same way, and the same name can ask to come back.
9. **Host closes:** Host presses **Leave** while a guest is in: the guest returns to the start
   screen with "Left the session: ...". Host returns to the start screen within 2 seconds.
10. **Host process killed** (Task Manager): the guest shows "Left the session: Lost connection
    to the host." within about 20 seconds and a **Rejoin** button.

## B. Two computers on the same Wi-Fi (LAN, direct address)

Setup: host PC and a second computer on the same Wi-Fi, same commit. Note the host PC's LAN
IP (`ipconfig`).

1. On the host, start the game, **Host game**, **Direct address**, **Host**. **Windows Firewall
   will ask** whether to allow Godot: allow it on *Private* networks. Record whether the prompt
   appeared and what you chose. If the prompt never appears and the guest cannot connect, the
   firewall is the suspect.
2. The shown address should be the host's LAN IP and port. Record whether it matches
   `ipconfig`. If the PC has several adapters (VPN, virtual), record which one it showed (the
   public address field can override it).
3. Guest types that address and presses **Join**. Record the time to join.
4. Repeat A.3 (ready/start and **the game checks**), A.4 (remove, leave), A.7 (full room).
5. **Wi-Fi blip:** with the guest in a *started* game, switch the guest's Wi-Fi off for 5
   seconds, then on. Record how long until the guest's screen noticed and what it showed
   (expected: the connection-lost screen with a **Rejoin** button). Press **Rejoin**: the guest
   returns to the same player slot with the current board, the host shows Connected and the
   pause overlay goes away. (Rejoin uses the identity the app still holds; the
   restart-and-ask-by-name path is item A.8.)
6. **Sleep:** let the guest's screen lock for 2 minutes without sleeping the PC; then return.
   Record whether the session survived.
7. **Version mismatch:** have the guest check out a different commit that changes the app
   version (or set a different `application/config/version` in Project Settings). Joining
   must show "This host runs app version X but you run Y", never a hang or a crash. Protocol 1
   builds (older than this version) must show a protocol mismatch the same way.
8. Leave both running idle for 10 minutes. Record whether anyone was dropped (the host
   pings every 5 s; a drop would show as "Disconnected").

## C. A friend on another network through a tunnel (direct address, the fallback)

The relay is the default now; this is the fallback for when it is unreachable or its free quota
is used up. Setup: the host runs the game and a tunnel agent of your choice; the friend runs the
same commit on a different network (mobile hotspot also counts). Use a **TCP** tunnel to the
host's local port (24680). Follow your tunnel provider's current instructions; they change, so do
not rely on old notes. Record the tunnel type and the address you were given.

1. Host: **Host game**, **Direct address**, **Host**. **The address the app shows is the host's
   LAN address and is wrong for a remote friend.** Type the tunnel's address into the lobby's
   **public address** field (then **Copy** it and send it to the friend). Record that the host
   had to override it, and that the override showed up in the lobby and in what Copy copied.
2. Friend types the tunnel address and presses **Join**. Record the time to join. A slower
   join than on LAN is normal; record how much.
3. Repeat A.3 (ready/start and **the game checks**), A.4 (leave), A.7 (full room) with the friend.
4. **Latency feel:** during the lobby, toggle ready several times and record how long a
   change takes to appear on the other screen (rough seconds). In the game, record how long a roll
   takes to show on the other screen.
5. **Tunnel blip:** restart the tunnel agent on the host while the friend is in a
   started game. Record what each side saw and whether the friend could press **Rejoin**
   afterwards and return to the same slot.
6. **Friend's network blip:** the friend turns their Wi-Fi/hotspot off for 10 seconds, then
   on, then presses **Rejoin**.
7. Keep the lobby open 30 minutes. Record any drops and the time they happened.
8. Wrong address: the friend types the tunnel address with a wrong port. It must fail with
   "Could not join" within about 10 seconds and be retryable.

## D. The relay on one PC (room codes)

Setup: `scripts/run_network_manual_test.sh relay --players=3` starts a local relay
(`ws://127.0.0.1:8787`) and four windows; or start the relay yourself
(`cd relay/cloudflare && npx wrangler dev --local --port 8787`) and the windows by hand with
`--relay_url=ws://127.0.0.1:8787`. Needs Node 22+ and `npm install` run once in `relay/cloudflare`.

1. Host: **Host game**, **Room code (relay)**, relay address `ws://127.0.0.1:8787` (or
   `localhost:8787`), press **Test**: it must say the relay works. Press **Host**: the lobby shows
   `Share this room code: <6 characters>` (no port field, no IP). **Copy** copies the code.
2. Guests type the code (try lower case, and with a hyphen in the middle) and press **Join**.
   Record the time to join. The guests' relay address box must hold the same relay.
3. Repeat A.3 (ready/start and **the game checks**), A.4, A.7 (full room: "That room is full.").
4. **Bad input:** a wrong code (`ZZZZZZ`) says "No game was found with that room code"; `laptop`
   (not a code, no dot or colon) says it needs a room code or an address; an empty relay address
   says to enter one; **Test** with a wrong port says the relay did not answer or is busy.
5. **Host's network blip** (relay mode only): with a game running, stop the *relay* (not the
   host) for a few seconds and start it again, or block the host's connection for about 20 s
   (a room is held for 60 s). Joiners must show *host away* (no disconnect screen) and play
   continues when the host is back. Record any joiner that showed a disconnect screen instead.
6. **Dead peers:** kill a guest process: the host shows the pause overlay within about a minute
   (relay keepalive: ping 15 s, dead after 50 s). Record the time.
7. **Host killed, then restarted from a save** (when the Save/Resume screens exist): a resumed
   game opens a **new room with a new code**; the old code is refused; guests rejoin with the
   new code and keep their seats.
8. Direct still works from the same build: repeat A.1–A.3 with **Direct address**.

## E. The relay between two computers on the same Wi-Fi

Setup: the relay is deployed (see `docs/relay.md`), its address is set in **Connection**
(press **Test** on both computers). Same commit on both.

1. Host: **Host game**, **Room code (relay)**, **Host**. Guest types the code, **Join**. Record the
   time to join (it goes out to the internet and back, so expect slightly slower than LAN).
2. Repeat A.3 and **the game checks** (including pause and rejoin after a Wi-Fi blip: relay
   rooms survive a host drop of up to a minute).
3. **Both on the relay, one on a hotspot:** put the guest on a phone hotspot and repeat 1.
4. Leave the lobby idle for 10 minutes: nobody may be dropped, and the Cloudflare dashboard
   should show only a few requests for the idle time (the keepalive is answered without waking
   the room).

## F. The relay with a friend on another network

Setup: the same deployed relay; the friend has the same commit and pastes the relay address into
**Connection** (or the build ships the address). Give the friend only the room code.

1. Host: **Host game**, **Room code (relay)**, **Host**; send the code. Friend joins by code.
   Record the time to join. Nobody forwards a port or runs a tunnel.
2. Repeat A.3 and **the game checks** with the friend, 10 turns at least. Record how long a roll
   takes to show on the other screen.
3. **Host's Wi-Fi off for 20 s, then on** during a game: the friend sees *host away* and play
   resumes. Switch it off for 2 minutes instead: the friend ends up on the connection-lost screen
   (the room is held for 60 s), and the host is told its room closed.
4. **Friend's Wi-Fi off for 10 s, then on, then Rejoin:** same seat, current board.
5. After the session, open the Cloudflare dashboard (Workers & Pages, the relay, metrics) and
   record the requests and duration for the hour. About 233 requests per game-hour for four
   players is the estimate; a large difference means something is wrong (for example keepalives
   waking the room).
6. **Different relay:** the friend pastes a *different* relay address (for example another
   person's deployment) and joins a room hosted there; nothing is edited in code.

## Known limits (do not report these as bugs)

- **The host's PC must stay on and awake** for the whole game. If the host leaves for good, the
  game ends unless it was saved.
- **A restarted host cannot resume its old room.** A resumed saved game opens a new room with a
  new code; players rejoin with their session tokens.
- **The relay is a free Cloudflare account with a daily quota** (100,000 requests a day). Anyone
  with the relay's address can use that quota. When it runs out, new rooms fail with "the relay
  is busy"; use a direct address (test C) as the fallback.
- **The relay operator can read all traffic**, including rejoin tokens, and is trusted. Do not
  use a relay you do not trust.
- A dropped relay guest is noticed after about a minute, not 15 seconds (the relay's keepalive is
  deliberately slow to save quota).

## After all tests

If everything passes, record it in your notes with the commit hash. If anything fails, the
log lines and the notes above are what to bring back. Fix automated coverage first
(a failing manual case that can be reproduced with `FakeRelay` delay, the scripted relay or a
dropped connection belongs in `tests/core` or the integration tier before the fix).

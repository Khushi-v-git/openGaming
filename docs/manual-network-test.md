# Manual network test checklist

The automated suite covers loopback, the fake relay and direct WebSocket on localhost.
It cannot cover firewalls, real Wi-Fi, other operating systems or a tunnel. Do these three
tests in order, as CLAUDE.md says: two instances, then LAN, then a real tunnel with a friend
on another network. Do not start the next one until the previous one passes.

## Before you start

- Everyone runs the **same commit** (`git rev-parse --short HEAD`), so app version and
  protocol match. Note the hash.
- Use the Godot **console** build so you can capture the log, and start the demo lobby:

  ```
  "%GODOT_BIN%" --path . res://tests/manual/lobby_demo.tscn -- --name=Asha > asha.log 2>&1
  ```

  (`--name=` prefills the name, `--port=` changes the listen port, default 24680.) The
  launcher is `tests/manual/lobby_demo.tscn`: the real lobby screen on the real direct
  transport, with a dummy game that only prints `[manual] game_started`.
- Debug builds log every message as `[net HH:MM:SS.mmm] -> player=p2 peer=2 type=...`
  (never payloads). Keep the logs; they are the evidence if something fails.
- Open the log of each instance after the test and look for `ERROR` and `SCRIPT ERROR`.

## What to record for every test

Copy this block into your notes once per test:

```
Test:            (A two instances / B LAN / C playit.gg)
Date, tester:
Commit / app version / Godot version:
Host: OS, Godot build, how it connects (Ethernet/Wi-Fi), host address shown in the app
Clients: OS, how they connect, address typed
Time from pressing Join to seeing the lobby (seconds):
Checklist result: list each item as PASS / FAIL / SKIPPED, with a note on every FAIL
Anything odd (lag, flicker, wrong text, a button that did nothing):
Logs attached: host.log, <client>.log
```

For every FAIL record: what you did, what you expected, what happened, the exact on-screen
text, and the log lines around the time (copy 20 lines either side).

## A. Two instances on one PC (localhost)

Setup: start the demo twice in two windows (`--name=Host` and `--name=Guest`).

1. Host presses **Host**. The screen shows "Starting your game..." briefly, then the lobby
   with `Share this address: <ip>:24680`. Record the address.
2. Guest types `127.0.0.1:24680` (not the shown address) and presses **Join**. Record the
   time to the lobby. Both windows list both players; the guest's row says "(you)".
3. Guest ticks **I'm ready**. Host sees "Ready". Host's **Start game** enables. Press it:
   both consoles print `[manual] game_started`.
4. Before starting, try the other actions:
   - Guest unticks and reticks ready; host row updates each time.
   - Host presses **Remove** on the guest: guest returns to the start screen with
     "Left the session: You were removed by the host." and no Rejoin button.
   - Guest joins again; presses **Leave**: guest returns to start without an error;
     host list shrinks.
5. Mistakes: join with an empty name, an empty address, `127.0.0.1:1` (a closed port; it
   should say "Could not join" after about 10 seconds and offer Join again), and `abc`.
   Press **Cancel** while it is connecting: you must get back to the start screen at once.
6. Start a second host on the same port (a third instance, or `--port=` the same): it must
   say "Could not host: cannot listen on port 24680".
7. Third and fourth guests join (fourth seat full): a fifth gets "This room is full."
8. **Guest process killed:** end the guest's process in Task Manager (not Leave).
   - In the open lobby the guest's row disappears from the host within about 15 seconds
     (the ping timeout) or at once if Windows closes the socket.
   - After the game has started the row stays and says "Disconnected"; the host and the
     other players keep going. A restarted demo with the same name is a *new* player and
     is correctly refused ("This game has already started."). Rejoining as the same player
     needs the surviving client's saved identity, so it is tested in B.5 and C.5/C.6 (the
     client process stays alive there), not here.
9. **Host closes:** Host presses **Leave** while a guest is in: the guest returns to the start
   screen with "Left the session: ...". Host returns to the start screen within 2 seconds.
10. **Host process killed** (Task Manager): the guest shows "Left the session: Lost connection
    to the host." within about 20 seconds and a **Rejoin** button.

## B. Two computers on the same Wi-Fi (LAN)

Setup: host PC and a second computer on the same Wi-Fi, same commit. Note the host PC's LAN
IP (`ipconfig`).

1. On the host, start the demo and press **Host**. **Windows Firewall will ask** whether to
   allow Godot: allow it on *Private* networks. Record whether the prompt appeared and what
   you chose. If the prompt never appears and the guest cannot connect, the firewall is the
   suspect.
2. The shown address should be the host's LAN IP and port. Record whether it matches
   `ipconfig`. If the PC has several adapters (VPN, virtual), record which one it showed.
3. Guest types that address and presses **Join**. Record the time to join.
4. Repeat A.3 (ready/start), A.4 (remove, leave), A.7 (full room).
5. **Wi-Fi blip:** with the guest in a *started* game, switch the guest's Wi-Fi off for 5
   seconds, then on. Record how long until the guest's screen noticed and what it showed
   (expected: back to the start screen with "Left the session" and a **Rejoin** button).
   Press **Rejoin**: the guest returns to the same player slot, the host shows Connected.
6. **Sleep:** let the guest's screen lock for 2 minutes without sleeping the PC; then return.
   Record whether the session survived.
7. **Version mismatch:** have the guest check out a different commit that changes the app
   version (or set a different `application/config/version` in Project Settings). Joining
   must show "This host runs app version X but you run Y", never a hang or a crash.
8. Leave both running idle for 10 minutes. Record whether anyone was dropped (the host
   pings every 5 s; a drop would show as "Disconnected").

## C. A friend on another network through playit.gg

Setup: the host runs the demo and a playit.gg agent; the friend runs the same commit on a
different network (mobile hotspot also counts). Use a **TCP** tunnel to the host's local port
(24680). Follow playit.gg's current instructions for creating a TCP tunnel; they change, so
do not rely on old notes. Record the tunnel type and the address playit.gg gives.

1. Host presses **Host** in the app. **The address the app shows is the host's LAN
   address and is wrong for a remote friend.** Give the friend the playit.gg tunnel
   address instead. (Known gap: the app does not know the tunnel address yet.) Record
   that the host had to override it.
2. Friend types the tunnel address and presses **Join**. Record the time to join. A slower
   join than on LAN is normal; record how much.
3. Repeat A.3 (ready/start), A.4 (leave), A.7 (full room) with the friend.
4. **Latency feel:** during the lobby, toggle ready several times and record how long a
   change takes to appear on the other screen (rough seconds).
5. **Tunnel blip:** restart the playit.gg agent on the host while the friend is in a
   started game. Record what each side saw and whether the friend could press **Rejoin**
   afterwards and return to the same slot.
6. **Friend's network blip:** the friend turns their Wi-Fi/hotspot off for 10 seconds, then
   on, then presses **Rejoin**.
7. Keep the lobby open 30 minutes. Record any drops and the time they happened.
8. Wrong address: the friend types the tunnel address with a wrong port. It must fail with
   "Could not join" within about 10 seconds and be retryable.

## After all three

If everything passes, record it in your notes with the commit hash. If anything fails, the
log lines and the notes above are what to bring back. Fix automated coverage first
(a failing manual case that can be reproduced with `FakeRelay` delay or a dropped connection
belongs in `tests/core` before the fix).

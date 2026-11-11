# Native application guide

The Godot application opens on **Play**. Choose Classic Chess or Battle Chess,
then Local or Online. The 2D / 3D choice belongs to this device; opponents can use
different views. The board toolbar switches views during a match without changing
the position, clock or turn.

## Local games

Local play needs no account and uses two players on one device. Classic offers
3+2, 5+0, 10+0, 15+10 and 30+0 from the menu; the in-game New game dialog also
offers additional controls and untimed practice. Battle uses the integrated C0
rules: untimed chess, legal capture duels, and traditional checkmate. Kings do
not enter combat in C0. Local combat retains the existing two-seat controls.

Both local boards retain selection, legal move hints, promotion, move history,
animations and their existing mouse/touch interactions. Local practice permits
undo and FEN import. These actions are unavailable in authoritative online play.
Local matches are not uploaded to online match history or competitive ratings.
Returning to the menu asks before discarding a local match with moves.

## Accounts and online games

Start the account service and authoritative dedicated server using the backend
instructions in [BACKEND.md](BACKEND.md). The default development service address
is `http://127.0.0.1:8787`; set your hosted HTTPS account service in Settings on
each client. Android's loopback address refers to the Android device, so a
physical phone needs the deployed HTTPS service address. Development emulator
forwarding, if used, must be configured separately.

Choose **Sign in** to register a username, a display name and a password of at
least ten characters. Use the same username and password on Windows and Android
to access one profile. The client keeps its account token in memory for the
current run, and does not write passwords or tokens to preferences. Sign out
revokes the current session. There is no email recovery or password-reset UI in
this version; retain your credentials.

- **Quick match:** choose Ranked or Unranked and a supported time control.
  Matchmaking matches the same mode and clock settings. Ranked matching starts
  with a narrow rating range and widens it while waiting.
- **Private match:** create an invite, copy its six-character code and share it
  with the other player. The other player enters the code and chooses Join.
  Private games are unranked. Codes expire after ten minutes.
- **Ready:** after allocation, each player confirms Ready in the match lobby.
  The dedicated server owns the chess position, clocks, combat and final result.
- **Reconnect:** the running client automatically attempts to recover its ENet
  session. The Play menu also offers Reconnect to allocated match to request a
  fresh seat ticket after returning to the menu. A new application run requires
  account sign-in again. Leaving does not pause the server; timeout can forfeit
  an active seat.

During Battle captures, the client previews the duel and switches to the combat
presentation. Server snapshots provide damage and results. On returning to the
board, each client retains its own 2D / 3D selection. HTTPS and DTLS certificate
errors are displayed; the client does not offer a public-server TLS bypass.

The Settings page also provides an advanced direct-server lobby for local
anonymous-server development. This is separate from persistent account
matchmaking and must not be used to imply ranked account play.

## Profiles, results and history

Profile shows the server-issued player ID and independent Classic / Battle
ratings, wins, losses, draws and games. Leaderboard displays each mode and opens
other players' public profiles. Completed online matches appear in Match history
with opponent, outcome, reason, date, final position and rating change. Results
load in compact pages of twenty; choose **Load older matches** to browse earlier
records without downloading their complete move histories. Results
may take a moment to appear while the dedicated server commits them to storage.
The result dialog offers Review board and Main menu. Clients never submit a
rating change or choose a competitive winner.

## Device settings and controls

- Default board, animation, touch controls, graphics quality and master volume
  are saved per device in `user://preferences.cfg`. Changing the account service
  address signs out the previous account session.
- Low quality uses a 30 FPS presentation limit without antialiasing. Balanced
  targets 60 FPS with 2× antialiasing. High uses 4× antialiasing and uncapped FPS.
  These settings do not change the server's fixed simulation rate.
- Mouse / touch: select and move a piece by tapping or dragging. In 3D,
  right-drag or swipe orbits the board; scroll or pinch zooms.
- Controller: d-pad and accept/back navigate focused controls. The left stick
  enables a virtual pointer; A clicks at its position on either board. The
  pointer yields to the existing combat controller when a duel begins.
- Online combat offers keyboard / mouse, a gamepad scheme and virtual touch
  controls. Esc releases a captured combat mouse.

The application uses touch-sized controls and scrolls its content when the
available landscape height is limited. It does not require a keyboard to select
a mode, board view, matchmaking action or menu page. Account text entry uses the
platform's text input.

## UI validation

`godot --headless --path godot --script res://tests/test_application_ui.gd`
checks mode navigation, signed-out gating, queue/invite presentation, supported
clock choices, HTTPS/loopback policy, credential exclusion from saved
preferences, authoritative result labels, and launch into the existing Classic
and Battle scenes with shared 2D / 3D state. The current run passed 49 checks,
including controller-pointer lifecycle, graphics preference application, compact
history pagination, retries, and stale-response rejection after navigation.
The existing Classic view suite passed 345 checks after these navigation changes.

The shell was also rendered and visually inspected at 1280×800 using Godot 4.6.3
and Linux Mesa llvmpipe. That is a software-rendered Linux check, not physical
Windows, Android, touchscreen or controller verification. Native build artifacts
and device installation are documented separately by the export workflow.

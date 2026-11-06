import { copyState } from "./copyState";
import React, {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { Chess, type Color, type Square } from "chess.js";
import { GameBoard } from "../next/GameBoard";
import { Piece } from "../next/Piece";
import { Dialog, SETS } from "../next/ui";
import type { Preferences } from "../next/contracts";
import type { Army } from "../game/battleProfiles";
import { homeArena } from "../game/battleProfiles";
import { gameWebsite } from "../next/mobile";
import { BattleHost, type BattleSnapshot, type BattleCommand } from "./session";
import { battleMoves, restrictedMoves, other } from "./rules";
import { sanitizeInput, type CombatInput } from "./simulation";
import {
  DEFAULT_BINDINGS,
  FIGHTERS,
  ROLE_NAMES,
  type Bindings,
  type BindingAction,
} from "./config";
import { RoomClient, type RoomInfo } from "./RoomClient";
import "./battle.css";
const CombatArena = lazy(() => import("./CombatArena"));
const STORE = "sg-battle-local-v1";
const title = (c: Color) => (c === "w" ? "White" : "Black");
function readSaved(): BattleSnapshot | null {
  try {
    const s = JSON.parse(localStorage.getItem(STORE) || "null");
    if (
      s?.version !== 1 ||
      s.match?.version !== 1 ||
      !["board", "combat", "aftermath", "complete"].includes(s.match.phase) ||
      !Array.isArray(s.match.history)
    )
      return null;
    new Chess(s.match.fen);
    if (s.match.pending && s.match.pending.before !== s.match.fen) return null;
    if (s.combat) {
      if (s.combat.id !== s.match.pending?.id) return null;
      for (const c of ["w", "b"] as Color[]) {
        const f = s.combat.fighters[c];
        if (
          !Object.prototype.hasOwnProperty.call(FIGHTERS, f.role) ||
          ![f.hp, f.stamina, f.x, f.z].every(Number.isFinite)
        )
          return null;
      }
    }
    return s;
  } catch {
    return null;
  }
}
function readBindings(): Record<Color, Bindings> {
  try {
    const saved = JSON.parse(
      localStorage.getItem("sg-battle-bindings") || "null",
    );
    if (
      saved &&
      ["w", "b"].every((c) =>
        Object.keys(DEFAULT_BINDINGS.w).every(
          (k) => typeof saved[c]?.[k] === "string",
        ),
      )
    )
      return saved;
  } catch {}
  return copyState(DEFAULT_BINDINGS);
}
export default function BattleChess({
  preferences,
  onExit,
}: {
  preferences: Preferences;
  onExit: () => void;
}) {
  const [snapshot, setSnapshot] = useState<BattleSnapshot | null>(null),
    live = useRef<BattleSnapshot | null>(null),
    host = useRef<BattleHost | null>(null),
    client = useRef<RoomClient | null>(null);
  const [kind, setKind] = useState<"local" | "server">("local"),
    [room, setRoom] = useState<RoomInfo | null>(null),
    [peers, setPeers] = useState<Record<Color, boolean>>({
      w: false,
      b: false,
    }),
    [started, setStarted] = useState(true),
    [status, setStatus] = useState(""),
    [capable, setCapable] = useState(false);
  const [white, setWhite] = useState<Army>(preferences.pieceSet),
    [black, setBlack] = useState<Army>("skeletons"),
    [saved, setSaved] = useState(readSaved),
    [selected, setSelected] = useState<Square | null>(null),
    [promotion, setPromotion] = useState<{ from: Square; to: Square } | null>(
      null,
    ),
    [notice, setNotice] = useState("");
  const [menu, setMenu] = useState(false),
    [rules, setRules] = useState(false),
    [help, setHelp] = useState(false),
    [binding, setBinding] = useState<{
      color: Color;
      action: BindingAction;
    } | null>(null),
    [bindings, setBindings] = useState(readBindings);
  const [joinCode, setJoinCode] = useState(
      () => new URLSearchParams(location.search).get("battle") || "",
    ),
    [boardView, setBoardView] = useState<"2d" | "3d">(
      preferences.efficiency === "on" ? "2d" : "3d",
    );
  useEffect(() => {
    if (snapshot?.match.phase === "complete") {
      setMenu(false);
      setHelp(false);
      setBinding(null);
    }
  }, [snapshot?.match.phase]);
  const light =
    preferences.efficiency === "on" ||
    (navigator.hardwareConcurrency || 4) <= 4;
  const publish = useCallback(() => {
    if (host.current) {
      live.current = host.current.state;
      setSnapshot(copyState(host.current.state));
    }
  }, []);
  const getSnapshot = useCallback(() => live.current!, []);
  const save = useCallback(() => {
    if (host.current)
      try {
        localStorage.setItem(STORE, JSON.stringify(host.current.state));
      } catch {}
  }, []);
  useEffect(() => {
    let stopped = false;
    const controller = new AbortController();
    void fetch(gameWebsite() + "/api/battle-capabilities", {
      signal: controller.signal,
    })
      .then((r) => r.json())
      .then((d) => {
        if (!stopped)
          setCapable(d.enabled === true && d.transport === "websocket");
      })
      .catch(() => {});
    return () => {
      stopped = true;
      controller.abort();
    };
  }, []);
  useEffect(() => {
    let frame = 0,
      last = performance.now(),
      lastUi = 0,
      lastSave = 0;
    const tick = (now: number) => {
      frame = requestAnimationFrame(tick);
      const h = host.current;
      if (h) {
        h.advance((now - last) / 1000);
        if (now - lastUi > 66) {
          publish();
          lastUi = now;
        }
        if (now - lastSave > 500) {
          save();
          lastSave = now;
        }
      }
      last = now;
    };
    frame = requestAnimationFrame(tick);
    const hidden = () => {
      if (host.current && document.hidden) {
        host.current.pause(true);
        setMenu(true);
        publish();
        save();
      }
    };
    document.addEventListener("visibilitychange", hidden);
    return () => {
      cancelAnimationFrame(frame);
      document.removeEventListener("visibilitychange", hidden);
      if (host.current) {
        host.current.pause(true);
        save();
      }
      client.current?.close();
    };
  }, []);
  useEffect(() => {
    if (!snapshot?.combat) return;
    const before = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = before;
    };
  }, [Boolean(snapshot?.combat)]);
  useEffect(() => {
    if (!binding) return;
    const capture = (e: KeyboardEvent) => {
      e.preventDefault();
      e.stopPropagation();
      if (e.code === "Escape") {
        setBinding(null);
        return;
      }
      setBindings((previous) => {
        const next = copyState(previous);
        const owner = Object.entries(next).some(
          ([color, map]) =>
            (kind === "local" || color === binding.color) &&
            Object.entries(map).some(
              ([action, key]) =>
                key === e.code &&
                (color !== binding.color || action !== binding.action),
            ),
        );
        if (owner) {
          setNotice("That key is already assigned. Choose a different key.");
          return previous;
        }
        next[binding.color][binding.action] = e.code;
        localStorage.setItem("sg-battle-bindings", JSON.stringify(next));
        return next;
      });
      setBinding(null);
    };
    window.addEventListener("keydown", capture, true);
    return () => window.removeEventListener("keydown", capture, true);
  }, [binding]);
  function startLocal(resume = false) {
    client.current?.close();
    client.current = null;
    const h = new BattleHost({ w: white, b: black });
    if (resume && saved) {
      h.state = copyState(saved);
      h.pause(true);
    }
    host.current = h;
    setWhite(h.state.match.armies.w);
    setBlack(h.state.match.armies.b);
    setKind("local");
    setStarted(true);
    setRoom(null);
    setNotice("");
    setSelected(null);
    setMenu(resume);
    live.current = h.state;
    publish();
    save();
  }
  function startRoom(type: "create" | "join") {
    if (!capable) return;
    host.current = null;
    client.current?.close();
    setKind("server");
    setStarted(false);
    setNotice("");
    setSelected(null);
    client.current = new RoomClient(
      gameWebsite(),
      {
        type,
        army: white,
        ...(type === "join" ? { code: joinCode.trim().toLowerCase() } : {}),
      },
      (s, p, ready) => {
        live.current = s;
        setSnapshot(s);
        setPeers(p);
        setStarted(ready);
      },
      (info) => setRoom(info),
      setStatus,
    );
  }
  const send = useCallback((command: BattleCommand, color: Color) => {
    try {
      if (host.current) {
        host.current.command(command, color);
        publish();
        save();
      } else client.current?.command(command);
      setSelected(null);
      setNotice("");
    } catch (e) {
      setNotice(
        e instanceof Error ? e.message : "The action could not be completed.",
      );
    }
  }, []);
  const input = useCallback((color: Color, value: CombatInput) => {
    if (host.current) host.current.inputs[color] = sanitizeInput(value);
    else client.current?.input(color, value);
  }, []);
  function pause() {
    setMenu(true);
    if (host.current) {
      host.current.pause(true);
      publish();
      save();
    }
  }
  function resume() {
    setMenu(false);
    setHelp(false);
    setBinding(null);
    if (host.current) {
      host.current.pause(false);
      publish();
    }
  }
  function exit() {
    if (host.current) {
      host.current.pause(true);
      save();
    } else if (room && live.current?.match.phase !== "complete")
      try {
        client.current?.command({ type: "resign" });
      } catch {}
    client.current?.close();
    onExit();
  }
  const match = snapshot?.match,
    fen = match?.fen || new Chess().fen(),
    turn = new Chess(fen).turn();
  const moves = useMemo(() => battleMoves(fen), [fen]),
    restricted = useMemo(() => restrictedMoves(fen), [fen]);
  const legal = moves.filter((m) => m.from === selected),
    canMove = Boolean(
      match?.phase === "board" &&
        !snapshot?.paused &&
        started &&
        (kind === "local" || room?.seat === turn),
    );
  function move(from: Square, to: Square, promote?: string) {
    const options = moves.filter((m) => m.from === from && m.to === to);
    if (!options.length) {
      setNotice(
        restricted.find((m) => m.from === from && m.to === to)?.reason ||
          "That move is not available.",
      );
      return;
    }
    if (options.some((m) => m.promotion) && !promote) {
      setPromotion({ from, to });
      return;
    }
    send(
      { type: "move", from, to, promotion: promote },
      kind === "local" ? turn : room!.seat,
    );
  }
  function select(square: Square) {
    if (!canMove) return;
    if (selected && moves.some((m) => m.from === selected && m.to === square)) {
      move(selected, square);
      return;
    }
    const blocked = restricted.find(
      (m) => m.from === selected && m.to === square,
    );
    if (blocked) {
      setNotice(blocked.reason);
      return;
    }
    const p = new Chess(fen).get(square);
    setSelected(p?.color === turn && selected !== square ? square : null);
    setNotice("");
  }
  const url = room ? new URL(`/?battle=${room.code}`, gameWebsite()).href : "";
  const combatColors = useMemo<Color[]>(
    () => (kind === "server" && room ? [room.seat] : ["w", "b"]),
    [kind, room?.seat],
  );
  const combat = Boolean(
    snapshot?.combat && ["combat", "aftermath"].includes(match?.phase || ""),
  );
  return (
    <div className={`battle-page ${combat ? "in-combat" : ""}`}>
      {!combat && (
        <header className="battle-header">
          <button className="text-button" onClick={exit}>
            ← Classic Chess
          </button>
          <div>
            <small>A NEW WAY TO HOLD THE LINE</small>
            <h1>
              Battle Chess <span>3D Combat</span>
            </h1>
          </div>
          <button className="text-button" onClick={() => setRules(true)}>
            Rules
          </button>
        </header>
      )}
      {!snapshot ? (
        <main className="battle-setup">
          <div className="battle-intro">
            <span className="battle-emblem">⚔</span>
            <p className="section-eyebrow">
              CHESS SETS THE STAGE. YOU WIN THE FIGHT.
            </p>
            <h2>Every capture is a duel.</h2>
            <p>
              Plan on the chessboard. Take direct control in a third-person
              arena. A defender can win the square by defeating the attacker.
            </p>
          </div>
          <section className="battle-start-card">
            <h2>Local two-player</h2>
            <p>
              Two people, one device. Separate cameras and controls. No bots,
              account or internet required.
            </p>
            <div className="battle-legions">
              <LegionField
                label="White legion"
                value={white}
                change={setWhite}
              />
              <LegionField
                label="Black legion"
                value={black}
                change={setBlack}
              />
            </div>
            <button className="primary-button" onClick={() => startLocal()}>
              Start Battle Chess
            </button>
            {saved && saved.match.phase !== "complete" && (
              <button
                className="secondary-button"
                onClick={() => startLocal(true)}
              >
                Resume saved Battle Chess
              </button>
            )}
            <small>Untimed chess · 90-second duels · Checkmate wins</small>
            <button className="text-button" onClick={() => setHelp(true)}>
              Controls and key bindings
            </button>
          </section>
          {capable ? (
            <section className="battle-start-card battle-room-start">
              <h2>Private server room</h2>
              <p>
                Two devices on this Node host. The server validates moves,
                simulates fights and decides the result. Host plays White; guest
                plays Black.
              </p>
              <LegionField
                label="Your room legion"
                value={white}
                change={setWhite}
              />
              <button
                className="secondary-button"
                onClick={() => startRoom("create")}
              >
                Create Battle room
              </button>
              <label>
                Room code
                <input
                  aria-label="Battle room code"
                  value={joinCode}
                  onChange={(e) => setJoinCode(e.target.value)}
                  maxLength={12}
                  placeholder="12-character room code"
                />
              </label>
              <button
                className="secondary-button"
                disabled={!/^[a-f0-9]{12}$/i.test(joinCode.trim())}
                onClick={() => startRoom("join")}
              >
                Join Battle room
              </button>
              {status && <p role="status">{status}</p>}
            </section>
          ) : (
            <details className="battle-hosting-note">
              <summary>Playing Battle Chess on separate devices</summary>
              <p>
                Private combat rooms need the included persistent Node/WebSocket
                server. This host does not advertise that server. Vercel's
                Classic Chess API continues to handle Classic matches;
                shared-device Battle Chess works here offline.
              </p>
            </details>
          )}
        </main>
      ) : combat ? (
        <Suspense
          fallback={
            <div className="battle-loading">Opening the castle arena…</div>
          }
        >
          <CombatArena
            getSnapshot={getSnapshot}
            colors={combatColors}
            bindings={bindings}
            light={light}
            sound={preferences.sound}
            blocked={menu || help}
            onInput={input}
            onFailure={() => {
              if (host.current) {
                host.current.pause(true);
                publish();
              }
            }}
            onPause={pause}
            onRecovered={resume}
            onContinue={() =>
              send({ type: "continue" }, kind === "local" ? turn : room!.seat)
            }
          />
        </Suspense>
      ) : (
        <main className="battle-board-layout">
          <section className="battle-board-column">
            <div className="battle-turn">
              <span className={`side-dot side-${turn}`} />
              <strong>
                {match?.phase === "complete"
                  ? "Match complete"
                  : !started
                    ? "Waiting for the second player"
                    : `${title(turn)} to move${new Chess(fen).inCheck() ? " · Check" : ""}`}
              </strong>
              <span>
                {kind === "local" ? "Shared device" : "Server room"} · Untimed
              </span>
            </div>
            <GameBoard
              fen={fen}
              orientation={kind === "server" && room ? room.seat : "w"}
              pieceSet={white}
              armies={match!.armies}
              arena={homeArena(match!.armies.w)}
              view={boardView}
              models={!light}
              allowSlow={preferences.efficiency === "off"}
              competitive={false}
              lightweight={light}
              animationMode="brief"
              reducedMotion={preferences.reducedMotion}
              sound={preferences.sound}
              selected={selected}
              onSelect={select}
              onMove={move}
              playerColor={kind === "local" ? turn : room?.seat || null}
              interactive={canMove}
              legal={legal.map((m) => m.to)}
              captureTargets={legal.filter((m) => m.captured).map((m) => m.to)}
              lastMove={match!.history[match!.history.length - 1]}
              coordinates
              onSceneFail={() => setBoardView("2d")}
            />
            <div className="battle-board-actions">
              <button className="secondary-button" onClick={pause}>
                Match options
              </button>
              <button
                className="text-button"
                disabled={light}
                title={
                  light
                    ? "Light graphics uses a 2D chessboard. Capture duels remain in 3D."
                    : undefined
                }
                onClick={() => setBoardView((v) => (v === "2d" ? "3d" : "2d"))}
              >
                {light
                  ? "2D · Light"
                  : boardView === "2d"
                    ? "3D castle"
                    : "2D board"}
              </button>
              <button className="text-button" onClick={() => setRules(true)}>
                Variant rules
              </button>
            </div>
            {(notice || restricted.some((m) => m.from === selected)) && (
              <p className="battle-notice" role="status">
                {notice ||
                  "Some captures are restricted because losing that duel would expose your king. Select one to see why."}
              </p>
            )}
            {status && (
              <p className="battle-notice" role="status">
                {status}
              </p>
            )}
            {kind === "server" && room && (
              <section className="battle-room-card">
                <strong>
                  {started
                    ? `${peers.w ? "White connected" : "White disconnected"} · ${peers.b ? "Black connected" : "Black disconnected"}`
                    : "Invite the second player"}
                </strong>
                <label>
                  Battle room link
                  <input
                    readOnly
                    value={url}
                    aria-label="Battle room invite link"
                    onFocus={(e) => e.target.select()}
                  />
                </label>
                <button
                  className="text-button"
                  onClick={async () => {
                    try {
                      await navigator.clipboard.writeText(url);
                      setNotice("Battle room link copied.");
                    } catch {
                      setNotice("Select and copy the room link above.");
                    }
                  }}
                >
                  Copy room link
                </button>
              </section>
            )}
          </section>
          <aside className="battle-board-sidebar">
            {match?.phase === "complete" ? (
              <section
                className="battle-results"
                aria-label="Battle Chess results"
              >
                <small>THE BATTLE IS OVER</small>
                <h2>
                  {match.result === "1/2-1/2"
                    ? "A hard-fought draw"
                    : `${match.result === "1-0" ? "White" : "Black"} wins`}
                </h2>
                <p>{match.reason}</p>
                <dl>
                  <div>
                    <dt>Moves played</dt>
                    <dd>{match.history.length}</dd>
                  </div>
                  <div>
                    <dt>Capture duels</dt>
                    <dd>{match.history.filter((m) => m.outcome).length}</dd>
                  </div>
                  <div>
                    <dt>Defenders held</dt>
                    <dd>
                      {
                        match.history.filter((m) => m.outcome === "defender")
                          .length
                      }
                    </dd>
                  </div>
                </dl>
                <button
                  className="primary-button"
                  onClick={() => {
                    client.current?.close();
                    client.current = null;
                    host.current = null;
                    live.current = null;
                    setSnapshot(null);
                    setRoom(null);
                    setStatus("");
                    setSaved(readSaved());
                  }}
                >
                  New Battle Chess match
                </button>
                <button className="text-button" onClick={exit}>
                  Return to Classic Chess
                </button>
              </section>
            ) : (
              <section className="battle-explainer">
                <h2>Win the square.</h2>
                <p>
                  Gold rings mark possible capture duels. Both pieces enter the
                  arena at full health and stamina. The loser leaves the board.
                </p>
                <details>
                  <summary>Fighter classes</summary>
                  {Object.entries(FIGHTERS).map(([role, cfg]) => (
                    <div className="battle-class" key={role}>
                      <Piece
                        type={role as any}
                        color="w"
                        set={match!.armies.w}
                      />
                      <div>
                        <strong>
                          {ROLE_NAMES[role as keyof typeof ROLE_NAMES]} ·{" "}
                          {cfg.name}
                        </strong>
                        <small>
                          {cfg.hp} HP · {cfg.stamina} stamina · {cfg.ability}
                        </small>
                        <p>{cfg.description}</p>
                      </div>
                    </div>
                  ))}
                </details>
              </section>
            )}
            <section className="battle-history">
              <h3>Match chronicle</h3>
              {match!.history.length ? (
                <ol>
                  {match!.history.map((m, i) => (
                    <li key={i}>
                      <small>{i + 1}.</small>
                      <strong>{m.san}</strong>
                      {m.outcome && (
                        <span>
                          {m.outcome === "defender"
                            ? "Defender held"
                            : "Attacker won"}
                        </span>
                      )}
                    </li>
                  ))}
                </ol>
              ) : (
                <p>The first move is yours.</p>
              )}
            </section>
          </aside>
        </main>
      )}
      {menu && snapshot && !help && (
        <Dialog title="Battle Chess match" onClose={resume}>
          <div className="dialog-content battle-menu">
            <p>
              {kind === "local"
                ? "Both players are paused."
                : "The server fight continues while this menu is open."}
            </p>
            <button className="primary-button" onClick={resume}>
              Resume Battle Chess
            </button>
            <button className="secondary-button" onClick={() => setHelp(true)}>
              Controls and key bindings
            </button>
            {kind === "local" && (
              <button
                className="secondary-button"
                onClick={() => {
                  startLocal();
                  setMenu(false);
                }}
              >
                Restart Battle Chess
              </button>
            )}
            {match?.phase === "board" && (
              <div className="battle-resign-row">
                {(kind === "server"
                  ? [room!.seat]
                  : (["w", "b"] as Color[])
                ).map((c) => (
                  <button
                    key={c}
                    className="text-button"
                    disabled={snapshot.drawOffers?.includes(c)}
                    onClick={() => {
                      send({ type: "draw" }, c);
                      if (host.current?.state.match.phase === "complete")
                        setMenu(false);
                    }}
                  >
                    {title(c)}{" "}
                    {snapshot.drawOffers?.includes(other(c))
                      ? "accepts"
                      : "offers"}{" "}
                    draw
                  </button>
                ))}
              </div>
            )}
            {kind === "local" ? (
              <div className="battle-resign-row">
                {(["w", "b"] as Color[]).map((c) => (
                  <button
                    key={c}
                    className="text-button"
                    onClick={() => {
                      send({ type: "resign" }, c);
                      setMenu(false);
                    }}
                  >
                    {title(c)} resigns
                  </button>
                ))}
              </div>
            ) : (
              <button
                className="secondary-button"
                onClick={() => {
                  send({ type: "resign" }, room!.seat);
                  setMenu(false);
                }}
              >
                Resign Battle Chess
              </button>
            )}
            <button className="text-button" onClick={exit}>
              {kind === "local"
                ? "Save and exit to Classic Chess"
                : "Resign and exit to Classic Chess"}
            </button>
            {notice && <p role="status">{notice}</p>}
          </div>
        </Dialog>
      )}
      {promotion && (
        <Dialog
          title="Choose Battle promotion"
          onClose={() => setPromotion(null)}
        >
          <div className="dialog-content battle-promotion">
            {(["q", "r", "b", "n"] as const).map((role) => (
              <button
                className="secondary-button"
                key={role}
                onClick={() => {
                  move(promotion.from, promotion.to, role);
                  setPromotion(null);
                }}
                aria-label={`Battle promote to ${ROLE_NAMES[role].toLowerCase()}`}
              >
                <Piece type={role} color={turn} set={match!.armies[turn]} />
                {ROLE_NAMES[role]}
              </button>
            ))}
          </div>
        </Dialog>
      )}
      {rules && (
        <Dialog title="Battle Chess rules" onClose={() => setRules(false)}>
          <div className="dialog-content battle-rules">
            <p>
              Legal quiet moves, castling, check, promotion and en passant use
              chess.js. Captures are resolved by a real fight, with fresh health
              and stamina each time.
            </p>
            <p>
              <strong>Attacker wins:</strong> capture and move to the target.{" "}
              <strong>Defender wins:</strong> remove the attacker, keep the
              defender on its original square and pass the turn. En passant
              attacks the actual pawn square.
            </p>
            <p>
              Kings win through checkmate. Kings cannot be captured or initiate
              capture duels. A capture is unavailable if a defender victory
              would leave the moving king in check. Mate and stalemate use the
              remaining Battle-legal moves.
            </p>
            <p>
              Duels last 90 seconds. On time, higher remaining health percentage
              wins. An exact tie or simultaneous knockout lets the defender
              hold. No random hits or winners. Threefold repetition, fifty-move
              and insufficient-material draws are tracked.
            </p>
            <p>
              Shared-device play pauses when hidden and saves separately from
              Classic Chess. Private rooms run on the Node server; an absent
              player forfeits after 10 seconds. Private rooms are unrated and
              held in memory until the server restarts.
            </p>
          </div>
        </Dialog>
      )}
      {help && (
        <Dialog
          title="Battle Chess controls"
          onClose={() => {
            setHelp(false);
            setBinding(null);
          }}
        >
          <div className="dialog-content battle-controls-help">
            <p>
              Keyboard and mouse, two gamepads, or independent touch controls.
              Drag each arena view to orbit. Scroll to change camera distance.
              Move the joystick to its edge to sprint.
            </p>
            <p>
              Gamepad: left stick move, right stick camera, X light, Y heavy, A
              dodge, B ability, LB block, RB parry, LT sprint, left-stick click
              lock.
            </p>
            {(kind === "server" ? ["w"] : ["w", "b"]).map((seat) => {
              const c = seat as Color;
              return (
                <details key={c} open>
                  <summary>
                    {kind === "server" && c === "w"
                      ? "Your keyboard controls"
                      : `${title(c)} keyboard controls`}
                  </summary>
                  <div className="battle-key-grid">
                    {Object.entries(bindings[c]).map(([action, key]) => (
                      <button
                        className={
                          binding?.color === c && binding.action === action
                            ? "binding-active"
                            : ""
                        }
                        key={action}
                        onClick={() =>
                          setBinding({
                            color: c,
                            action: action as BindingAction,
                          })
                        }
                      >
                        <span>{action}</span>
                        <kbd>
                          {binding?.color === c && binding.action === action
                            ? "Press a key…"
                            : key.replace("Key", "").replace("Arrow", "")}
                        </kbd>
                      </button>
                    ))}
                  </div>
                </details>
              );
            })}
            <p>
              Tap a binding to change it; Escape cancels. Mouse attacks stay
              assigned until replaced. Keep bindings distinct across players on
              a shared keyboard.
            </p>
            <button
              className="secondary-button"
              onClick={() => {
                const defaults = copyState(DEFAULT_BINDINGS);
                setBindings(defaults);
                localStorage.setItem(
                  "sg-battle-bindings",
                  JSON.stringify(defaults),
                );
                setBinding(null);
              }}
            >
              Reset default bindings
            </button>
            <p>
              Parry has a short timing window and recovery. Light/heavy chains
              accept the next strike near the end of recovery. Dodges have a
              brief invulnerable window. Holding attack never generates
              automatic hits.
            </p>
            {notice && <p role="status">{notice}</p>}
          </div>
        </Dialog>
      )}
    </div>
  );
}
function LegionField({
  label,
  value,
  change,
}: {
  label: string;
  value: Army;
  change: (army: Army) => void;
}) {
  return (
    <label className="battle-legion-field">
      <span>{label}</span>
      <select value={value} onChange={(e) => change(e.target.value as Army)}>
        {SETS.map((s) => (
          <option key={s.id} value={s.id}>
            {s.name}
          </option>
        ))}
      </select>
    </label>
  );
}

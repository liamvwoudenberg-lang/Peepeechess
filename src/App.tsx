import React, {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { Chess, type Color, type Square, type PieceSymbol } from "chess.js";
import {
  ArrowLeft,
  ArrowRight,
  BookOpen,
  Check,
  ChevronDown,
  ChevronRight,
  Clock3,
  Copy,
  Crown,
  Download,
  Eye,
  Flag,
  FlipVertical2,
  Gem,
  Home,
  Lightbulb,
  LoaderCircle,
  Menu,
  MessageCircle,
  Pause,
  Play,
  Plus,
  RotateCcw,
  Settings2,
  Shield,
  Smile,
  Sparkles,
  Swords,
  Trophy,
  Users,
  Volume2,
  VolumeX,
  Wifi,
  WifiOff,
  X,
} from "lucide-react";
import { FriendInvite } from "./next/FriendInvite";
import { MobileSettings } from "./next/MobileSettings";
import { inviteCodeFrom, isNativeApp, inviteSessionKey } from "./next/mobile";
import type { InviteInfo } from "./next/contracts";
import { Board } from "./next/Board";
import { GameBoard } from "./next/GameBoard";
import { homeArena, ARENAS } from "./game/battleProfiles";
import { Piece } from "./next/Piece";
import { Social } from "./next/Social";
import {
  Armory,
  Clock,
  Dialog,
  Moves,
  SETS,
  TimePicker,
  Toggle,
} from "./next/ui";
import { useConnection } from "./next/useConnection";
import { useEngine } from "./next/useEngine";
import { battleAudio } from "./game/battleAudio";
import { LESSONS, PUZZLES, type Exercise } from "./next/training";
import {
  DEFAULT_PREFERENCES,
  EMOTES,
  PIECE_NAMES,
  TIME_CONTROLS,
  type Challenge,
  type ChatMessage,
  type EmoteEvent,
  type Friend,
  type FriendRequest,
  type Game,
  type Page,
  type Player,
  type Preferences,
  type TimeControl,
} from "./next/contracts";
function newId() {
  return typeof crypto.randomUUID === "function"
    ? crypto.randomUUID()
    : Array.from(crypto.getRandomValues(new Uint8Array(16)), (v) =>
        v.toString(16).padStart(2, "0"),
      ).join("");
}

function read<T>(key: string, fallback: T): T {
  try {
    const value = localStorage.getItem(key);
    return value ? JSON.parse(value) : fallback;
  } catch {
    return fallback;
  }
}
function write(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    /* Play remains available when browser storage is full. */
  }
}
function restore(game: Game | null) {
  const c = new Chess(game?.initialFen);
  if (game)
    for (const m of game.history)
      c.move({ from: m.from, to: m.to, promotion: m.promotion });
  return c;
}
const navItems = [
  { id: "play", label: "Play", icon: Swords },
  { id: "puzzles", label: "Puzzles", icon: Gem },
  { id: "learn", label: "Learn", icon: BookOpen },
  { id: "friends", label: "Friends", icon: Users },
  { id: "armory", label: "Armory", icon: Shield },
] as const;

export function App() {
  const [page, setPage] = useState<Page>("play"),
    [preferences, setPreferences] = useState<Preferences>(() => ({
      ...DEFAULT_PREFERENCES,
      ...read("sg-preferences-v2", {}),
    }));
  const [user, setUser] = useState<Player | null>(null),
    [friends, setFriends] = useState<Friend[]>([]),
    [requests, setRequests] = useState<FriendRequest[]>([]),
    [challenges, setChallenges] = useState<Challenge[]>([]),
    [messages, setMessages] = useState<Record<string, ChatMessage[]>>({}),
    [onlineCount, setOnlineCount] = useState(0);
  const [game, setGame] = useState<Game | null>(() =>
    read("sg-local-game-v2", null),
  );
  const gameRef = useRef(game),
    chessRef = useRef(restore(game));
  const [archive, setArchive] = useState<Game[]>([]),
    [localArchive, setLocalArchive] = useState<Game[]>(() =>
      read("sg-local-archive-v2", []),
    );
  const [setupMode, setSetupMode] = useState<"online" | "computer" | "friend">(
      "computer",
    ),
    [timeControl, setTimeControl] = useState<TimeControl>("untimed"),
    [elo, setElo] = useState(1200),
    [moveFeedback, setMoveFeedback] = useState(true),
    [chosenSide, setChosenSide] = useState<"w" | "b" | "random">("w");
  const [queued, setQueued] = useState(false),
    [selected, setSelected] = useState<Square | null>(null),
    [orientation, setOrientation] = useState<Color>("w"),
    [premove, setPremove] = useState<{
      from: Square;
      to: Square;
      promotion?: string;
    } | null>(null),
    [promotion, setPromotion] = useState<{ from: Square; to: Square } | null>(
      null,
    );
  const [paused, setPaused] = useState(false),
    [thinking, setThinking] = useState(false),
    [feedback, setFeedback] = useState<any>(null),
    [hint, setHint] = useState<{ from: string; to: string } | null>(null),
    [reviewCursor, setReviewCursor] = useState<number | null>(null);
  const [adaptiveLowPower, setAdaptiveLowPower] = useState(false);
  const [dialog, setDialog] = useState<
      "settings" | "profile" | "resign" | "import" | "invite" | null
    >(null),
    [profileName, setProfileName] = useState(""),
    [profileWatch, setProfileWatch] = useState(true),
    [toast, setToast] = useState(""),
    [mobileMenu, setMobileMenu] = useState(false),
    [sideTab, setSideTab] = useState<"moves" | "friends">("moves");
  const [emoteOpen, setEmoteOpen] = useState(false),
    [emote, setEmote] = useState<EmoteEvent | null>(null),
    [emoteReadyAt, setEmoteReadyAt] = useState(0),
    [view, setView] = useState<"2d" | "3d">("2d");
  const [exercise, setExercise] = useState<Exercise | null>(null),
    [exerciseStep, setExerciseStep] = useState(0),
    [exerciseMessage, setExerciseMessage] = useState(""),
    [exerciseBusy, setExerciseBusy] = useState(false),
    [assisted, setAssisted] = useState(false),
    [completed, setCompleted] = useState<string[]>(() =>
      read("sg-training-v2", []),
    );
  const [pgnInput, setPgnInput] = useState(""),
    [importError, setImportError] = useState("");
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null),
    exerciseTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const engine = useEngine();
  const notify = useCallback((message: string) => {
    setToast(message);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(""), 4500);
  }, []);
  const updateGame = useCallback((next: Game | null) => {
    gameRef.current = next;
    setGame(next);
    if (
      next &&
      ["computer", "analysis", "puzzle", "lesson"].includes(next.mode)
    )
      write("sg-local-game-v2", next);
    else write("sg-local-game-v2", null);
  }, []);
  const [ownInvite, setOwnInvite] = useState<InviteInfo | null>(null),
    [invitePreview, setInvitePreview] = useState<InviteInfo | null>(null),
    [incomingCode, setIncomingCode] = useState<string | null>(null),
    [inviteError, setInviteError] = useState("");
  const pendingInvite = useRef(
    inviteCodeFrom(location.href) ||
      read<string | null>("sg-pending-invite", null),
  );
  const connection = useConnection((data) => {
    if (data.type === "invite:state" || data.type === "invite:created")
      setOwnInvite(data.invite);
    if (data.type === "invite:preview") {
      setInvitePreview(data.invite);
      setInviteError("");
    }
    if (data.type === "error" && data.action?.startsWith("invite:"))
      setInviteError(data.message);

    if (data.type === "ready") {
      setUser(data.user);
    }
    if (data.type === "social:state") {
      setUser(data.user);
      setFriends(data.friends);
      setRequests(data.requests);
      setChallenges(data.challenges);
      setOnlineCount(data.onlineCount);
    }
    if (data.type === "queue:state") setQueued(data.queued);
    if (
      data.type === "error" ||
      data.type === "notice" ||
      data.type === "auth:error"
    )
      notify(data.message);
    if (data.type === "archive") setArchive(data.games);
    if (data.type === "chat:history")
      setMessages((prev) => ({ ...prev, [data.friendId]: data.messages }));
    if (data.type === "chat:message") {
      const m = data.message as ChatMessage;
      const friendId = m.fromId === user?.id ? m.toId : m.fromId;
      setMessages((prev) => {
        const list = prev[friendId] || [];
        return {
          ...prev,
          [friendId]: list.some((x) => x.id === m.id) ? list : [...list, m],
        };
      });
    }
    if (data.type === "game:emote") setEmote(data.event);
    if (data.type === "spectate:ended") {
      if (gameRef.current?.yourColor === null) updateGame(null);
      notify(data.message);
    }
    if (data.type === "game:state") {
      const next = data.game as Game;
      const fresh = next.id !== gameRef.current?.id;
      if (fresh && next.status === "completed") return;
      engine.stop();
      chessRef.current = restore(next);
      updateGame(next);
      setThinking(false);
      setPaused(false);
      setSelected(null);
      setHint(null);
      setFeedback(null);
      if (fresh) {
        setDialog(null);
        setIncomingCode(null);
        setInvitePreview(null);
        pendingInvite.current = null;
        localStorage.removeItem("sg-pending-invite");
        const cleanURL = new URL(location.href);
        cleanURL.searchParams.delete("play");
        history.replaceState(null, "", cleanURL);
        setPage("play");
        setOrientation(next.yourColor || "w");
        setReviewCursor(null);
        setPremove(null);
        setPromotion(null);
        setExercise(null);
        setView("2d");
        setSideTab("moves");
      }
      if (next.status === "completed") {
        setPremove(null);
        setPromotion(null);
      }
    }
  });
  const online = connection.status === "online";
  useEffect(() => {
    const code = pendingInvite.current;
    if (!online || !code) return;
    pendingInvite.current = null;
    localStorage.removeItem("sg-pending-invite");
    if (
      gameRef.current?.status === "active" &&
      ["online", "friend"].includes(gameRef.current.mode)
    )
      return;
    setIncomingCode(code);
    setInvitePreview(null);
    setInviteError("");
    setDialog("invite");
    connection.send({ type: "invite:inspect", code });
  }, [online]);

  useEffect(() => {
    if (online)
      connection.send({ type: "profile:army", army: preferences.pieceSet });
  }, [online, preferences.pieceSet]);
  const isHuman = game?.mode === "online" || game?.mode === "friend";
  const active = game?.status === "active";
  const spectator = Boolean(isHuman && game?.yourColor === null);
  const busy = Boolean(active && isHuman && !spectator);
  const assistance = Boolean(
    game &&
      (game.mode === "analysis" || (game.mode === "computer" && game.feedback)),
  );
  const efficient =
    preferences.efficiency === "on" ||
    (preferences.efficiency === "auto" &&
      (adaptiveLowPower ||
        (navigator.hardwareConcurrency || 8) <= 4 ||
        Number((navigator as any).deviceMemory || 8) <= 4 ||
        (navigator as any).connection?.saveData));
  const armies = useMemo(() => {
    if (game?.armies) return game.armies;
    const own = preferences.pieceSet,
      other =
        preferences.opponentSet === "matching" ? own : preferences.opponentSet;
    return game?.yourColor === "b"
      ? { w: other, b: own }
      : { w: own, b: other };
  }, [
    preferences.pieceSet,
    preferences.opponentSet,
    game?.yourColor,
    game?.armies,
  ]);
  const homeMap = game?.arena || homeArena(armies.w);
  const chess = useMemo(() => new Chess(game?.fen), [game?.fen]);
  const playerColor =
    game?.mode === "analysis" ? chess.turn() : game?.yourColor || null;
  const displayedFen =
    game && reviewCursor !== null
      ? reviewCursor === 0
        ? game.initialFen
        : game.history[reviewCursor - 1]?.fen || game.fen
      : game?.fen || new Chess().fen();
  const displayedLast = game
    ? reviewCursor === null
      ? game.history[game.history.length - 1]
      : reviewCursor > 0
        ? game.history[reviewCursor - 1]
        : undefined
    : undefined;
  const legal = useMemo(() => {
    if (!selected || !game) return [];
    try {
      let c = chess;
      if (c.turn() !== playerColor) {
        const parts = c.fen().split(" ");
        parts[1] = playerColor!;
        parts[3] = "-";
        c = new Chess(parts.join(" "), { skipValidation: true });
      }
      return c.moves({ square: selected, verbose: true }).map((m) => m.to);
    } catch {
      return [];
    }
  }, [selected, chess, playerColor, game?.id]);
  const incoming = challenges.filter((c) => c.toId === user?.id);
  const badgeCount =
    requests.filter((r) => r.toId === user?.id).length +
    incoming.length +
    friends.reduce((sum, f) => sum + f.unread, 0);
  useEffect(() => {
    write("sg-preferences-v2", preferences);
  }, [preferences]);
  useEffect(() => {
    battleAudio.setEnabled(preferences.sound);
    const unlock = () => {
      if (preferences.sound) battleAudio.unlock();
    };
    window.addEventListener("pointerdown", unlock, { passive: true });
    return () => window.removeEventListener("pointerdown", unlock);
  }, [preferences.sound]);
  useEffect(() => {
    if (
      preferences.efficiency !== "auto" ||
      view === "3d" ||
      page === "armory" ||
      !("PerformanceObserver" in window) ||
      !PerformanceObserver.supportedEntryTypes?.includes("longtask")
    )
      return;
    let slowTasks = 0;
    const observer = new PerformanceObserver((list) => {
      if (document.hidden) return;
      for (const entry of list.getEntries())
        if (entry.duration > 120) slowTasks++;
      if (slowTasks >= 2) {
        setAdaptiveLowPower(true);
        setView("2d");
        observer.disconnect();
      }
    });
    observer.observe({ type: "longtask", buffered: false });
    return () => observer.disconnect();
  }, [preferences.efficiency, view, page]);
  useEffect(() => {
    write("sg-training-v2", completed);
  }, [completed]);
  useEffect(() => {
    if (emote) {
      const timer = setTimeout(() => setEmote(null), 3000);
      return () => clearTimeout(timer);
    }
  }, [emote]);
  useEffect(
    () => () => {
      if (toastTimer.current) clearTimeout(toastTimer.current);
      if (exerciseTimer.current) clearTimeout(exerciseTimer.current);
    },
    [],
  );
  useEffect(() => {
    if (dialog === "profile" && user) {
      setProfileName(user.name);
      setProfileWatch(user.allowSpectators !== false);
    }
  }, [dialog, user?.id]);
  useEffect(() => {
    function key(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setSelected(null);
        setPremove(null);
        setEmoteOpen(false);
        setMobileMenu(false);
      }
      if ((e.target as HTMLElement)?.matches("input,textarea,select")) return;
      if (
        (e.key === "ArrowLeft" || e.key === "ArrowRight") &&
        game &&
        game.status === "completed" &&
        !(e.target as HTMLElement)?.closest('[role="grid"]')
      ) {
        e.preventDefault();
        setReviewCursor((cur) =>
          Math.max(
            0,
            Math.min(
              game.history.length,
              (cur ?? game.history.length) + (e.key === "ArrowLeft" ? -1 : 1),
            ),
          ),
        );
      }
    }
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [game]);

  function completeLocal(next: Game, result: Game["result"], reason: string) {
    const finished = {
      ...next,
      status: "completed" as const,
      result,
      reason,
      clocks: { ...next.clocks, updatedAt: Date.now() },
    };
    chessRef.current.header(
      "White",
      finished.white.name,
      "Black",
      finished.black.name,
      "Result",
      result!,
    );
    finished.pgn = chessRef.current.pgn();
    updateGame(finished);
    setPremove(null);
    setSelected(null);
    setPaused(false);
    setThinking(false);
    if (next.mode === "computer") {
      setLocalArchive((prev) => {
        const list = [
          finished,
          ...prev.filter((g) => g.id !== finished.id),
        ].slice(0, 12);
        write("sg-local-archive-v2", list);
        return list;
      });
    }
  }
  function localMove(from: Square, to: Square, promote?: string) {
    const current = gameRef.current;
    if (!current || current.status !== "active") return;
    const c = chessRef.current;
    const before = c.fen();
    let move;
    try {
      move = c.move({ from, to, promotion: promote || "q" });
    } catch {
      return;
    }
    const clocks = { ...current.clocks };
    if (current.timeControl !== "untimed")
      clocks[move.color] =
        Math.max(0, clocks[move.color] - (Date.now() - clocks.updatedAt)) +
        clocks.increment;
    clocks.updatedAt = Date.now();
    clocks.turn = c.turn();
    const next = {
      ...current,
      fen: c.fen(),
      history: [
        ...current.history,
        {
          from: move.from,
          to: move.to,
          promotion: move.promotion,
          san: move.san,
          fen: c.fen(),
        },
      ],
      clocks,
    };
    updateGame(next);
    setSelected(null);
    setHint(null);
    setReviewCursor(null);
    if (
      current.mode === "computer" &&
      current.feedback &&
      move.color === current.yourColor
    ) {
      const id = current.id;
      void engine
        .run({
          action: "feedback",
          fen: before,
          move: { from, to, promotion: promote },
        })
        .then((result) => {
          if (gameRef.current?.id === id && gameRef.current.feedback)
            setFeedback(result);
        })
        .catch(() => {});
    }
    if (current.mode !== "analysis" && c.isGameOver())
      completeLocal(
        next,
        c.isCheckmate() ? (c.turn() === "w" ? "0-1" : "1-0") : "1/2-1/2",
        c.isCheckmate()
          ? "Checkmate"
          : c.isStalemate()
            ? "Stalemate"
            : c.isThreefoldRepetition()
              ? "Threefold repetition"
              : c.isInsufficientMaterial()
                ? "Insufficient material"
                : "Fifty-move rule",
      );
  }
  const localMoveRef = useRef(localMove);
  localMoveRef.current = localMove;
  useEffect(() => {
    if (
      game?.mode !== "computer" ||
      game.status !== "active" ||
      paused ||
      chess.turn() === game.yourColor
    )
      return;
    let cancelled = false;
    setThinking(true);
    const id = game.id,
      fen = game.fen;
    void engine
      .run({ action: "move", fen, elo: game.elo })
      .then((result) => {
        if (
          !cancelled &&
          result.move &&
          gameRef.current?.id === id &&
          gameRef.current.fen === fen
        )
          localMoveRef.current(
            result.move.from,
            result.move.to,
            result.move.promotion,
          );
      })
      .catch(() => {
        if (!cancelled)
          notify(
            "The computer could not respond. Try restarting this computer game.",
          );
      })
      .finally(() => {
        if (!cancelled) setThinking(false);
      });
    return () => {
      cancelled = true;
    };
  }, [game?.fen, game?.id, game?.status, paused]);
  useEffect(() => {
    if (
      !game ||
      game.mode !== "computer" ||
      !active ||
      game.phase === "connecting" ||
      paused ||
      game.timeControl === "untimed"
    )
      return;
    const currentColor = game.clocks.turn;
    const left =
      game.clocks[currentColor] - (Date.now() - game.clocks.updatedAt);
    const id = setTimeout(
      () => {
        if (
          gameRef.current?.id === game.id &&
          gameRef.current.status === "active"
        ) {
          engine.stop();
          const winner = currentColor === "w" ? "b" : "w";
          const opposing = chessRef.current
            .board()
            .flat()
            .filter((p) => p && p.color === winner && p.type !== "k");
          completeLocal(
            gameRef.current,
            opposing.length === 0 || chessRef.current.isInsufficientMaterial()
              ? "1/2-1/2"
              : winner === "w"
                ? "1-0"
                : "0-1",
            "Time expired",
          );
        }
      },
      Math.max(0, left),
    );
    return () => clearTimeout(id);
  }, [game?.fen, game?.status, game?.clocks.updatedAt, paused]);
  useEffect(() => {
    if (
      premove &&
      game?.status === "active" &&
      chess.turn() === game.yourColor &&
      !spectator
    ) {
      const planned = premove;
      setPremove(null);
      const valid = chess
        .moves({ square: planned.from, verbose: true })
        .some(
          (m) =>
            m.to === planned.to &&
            (m.promotion || "") === (planned.promotion || ""),
        );
      if (valid) commit(planned.from, planned.to, planned.promotion);
      else notify("Premove cancelled: the position changed.");
    }
  }, [game?.fen]);
  function commit(from: Square, to: Square, promote?: string) {
    const current = gameRef.current;
    if (
      !current ||
      current.status !== "active" ||
      paused ||
      spectator ||
      reviewCursor !== null
    )
      return;
    if (isHuman) {
      if (!online) {
        notify("Reconnecting. Your move has not been sent.");
        return;
      }
      connection.send({
        type: "game:move",
        id: current.id,
        from,
        to,
        promotion: promote,
        ply: current.history.length,
      });
      setSelected(null);
    } else if (current.mode === "puzzle" || current.mode === "lesson")
      exerciseMove(from, to, promote);
    else localMove(from, to, promote);
  }
  function requestMove(from: Square, to: Square, promote?: string) {
    if (
      !game ||
      !active ||
      game.phase === "connecting" ||
      paused ||
      spectator ||
      reviewCursor !== null ||
      exerciseBusy
    )
      return;
    if (chess.get(from)?.color !== playerColor) return;
    if (chess.turn() !== playerColor) {
      if (chess.get(to)?.color === playerColor) return;
      if (
        chess.get(from)?.type === "p" &&
        ["1", "8"].includes(to[1]) &&
        !promote
      ) {
        setPromotion({ from, to });
        return;
      }
      setPremove({ from, to, promotion: promote });
      setSelected(null);
      return;
    }
    const candidates = chess
      .moves({ square: from, verbose: true })
      .filter((m) => m.to === to);
    if (!candidates.length) {
      setSelected(null);
      return;
    }
    if (candidates.some((m) => m.promotion) && !promote) {
      setPromotion({ from, to });
      return;
    }
    commit(from, to, promote);
  }
  function selectSquare(sq: Square) {
    if (
      !game ||
      !active ||
      game.phase === "connecting" ||
      paused ||
      spectator ||
      reviewCursor !== null ||
      exerciseBusy
    )
      return;
    if (selected === sq) {
      setSelected(null);
      return;
    }
    if (chess.get(sq)?.color === playerColor) {
      setSelected(sq);
      return;
    }
    if (selected) requestMove(selected, sq);
  }
  function resetTransient() {
    window.scrollTo(0, 0);
    engine.stop();
    if (exerciseTimer.current) clearTimeout(exerciseTimer.current);
    setExerciseBusy(false);
    setPaused(false);
    setSelected(null);
    setPremove(null);
    setPromotion(null);
    setFeedback(null);
    setHint(null);
    setReviewCursor(null);
    setView("2d");
    setSideTab("moves");
    setThinking(false);
  }
  function startComputer() {
    if (busy) {
      notify("Finish your online game first.");
      return;
    }
    if (spectator) connection.send({ type: "game:unwatch" });
    connection.send({ type: "queue:leave" });
    resetTransient();
    setExercise(null);
    const color =
      chosenSide === "random" ? (Math.random() < 0.5 ? "w" : "b") : chosenSide;
    const c = new Chess();
    chessRef.current = c;
    const human = user || { id: "local", name: "You", rating: 1200 };
    const bot = {
      id: "computer",
      name:
        elo <= 800
          ? "Squire Rowan"
          : elo <= 1400
            ? "Knight Aldric"
            : "Magister Elowen",
      rating: elo,
    };
    const tc = TIME_CONTROLS.find((t) => t.id === timeControl)!;
    updateGame({
      id: `local-${newId()}`,
      mode: "computer",
      initialFen: c.fen(),
      fen: c.fen(),
      history: [],
      white: color === "w" ? human : bot,
      black: color === "b" ? human : bot,
      yourColor: color,
      status: "active",
      timeControl,
      clocks: {
        w: tc.minutes * 60000,
        b: tc.minutes * 60000,
        increment: tc.increment * 1000,
        turn: "w",
        updatedAt: Date.now(),
      },
      rated: false,
      spectators: 0,
      feedback: moveFeedback,
      elo,
    });
    setOrientation(color);
    setPage("play");
  }
  function newGame() {
    if (busy) return;
    if (spectator) connection.send({ type: "game:unwatch" });
    resetTransient();
    updateGame(null);
    setExercise(null);
    setPage("play");
    window.scrollTo(0, 0);
  }
  function pause() {
    if (!game || game.mode !== "computer") return;
    engine.stop();
    const clocks = { ...game.clocks };
    if (!paused && game.timeControl !== "untimed")
      clocks[clocks.turn] = Math.max(
        0,
        clocks[clocks.turn] - (Date.now() - clocks.updatedAt),
      );
    clocks.updatedAt = Date.now();
    updateGame({ ...game, clocks });
    setPaused(!paused);
  }
  function undo() {
    if (!game || game.mode !== "computer" || !game.history.length) return;
    engine.stop();
    const c = chessRef.current;
    c.undo();
    if (c.turn() !== game.yourColor && c.history().length) c.undo();
    const history = game.history.slice(0, c.history().length);
    updateGame({
      ...game,
      status: "active",
      result: undefined,
      reason: undefined,
      fen: c.fen(),
      history,
      clocks: { ...game.clocks, turn: c.turn(), updatedAt: Date.now() },
    });
    setFeedback(null);
    setSelected(null);
    setHint(null);
    setReviewCursor(null);
  }
  async function requestHint() {
    if (
      !assistance ||
      !game ||
      !active ||
      chess.turn() !== playerColor ||
      thinking
    )
      return;
    const id = game.id;
    try {
      const result = await engine.run({
        action: "hint",
        fen: game.fen,
        elo: 2000,
      });
      if (gameRef.current?.id === id && result.move) {
        setHint(result.move);
        notify(`Consider ${result.san}.`);
      }
    } catch {
      notify("A hint is unavailable right now.");
    }
  }
  function startExercise(item: Exercise, mode: "puzzle" | "lesson") {
    if (busy) {
      notify("Finish your online game before training.");
      return;
    }
    if (spectator) connection.send({ type: "game:unwatch" });
    connection.send({ type: "queue:leave" });
    resetTransient();
    setExercise(item);
    setExerciseStep(0);
    setExerciseMessage("");
    setAssisted(false);
    const c = new Chess(item.fen);
    chessRef.current = c;
    const p = { id: "practice", name: "Practice position", rating: 0 };
    updateGame({
      id: `practice-${newId()}`,
      mode,
      initialFen: c.fen(),
      fen: c.fen(),
      history: [],
      white: { ...p, name: c.turn() === "w" ? "You" : "Defending side" },
      black: { ...p, name: c.turn() === "b" ? "You" : "Defending side" },
      yourColor: c.turn(),
      status: "active",
      timeControl: "untimed",
      clocks: {
        w: 0,
        b: 0,
        turn: c.turn(),
        increment: 0,
        updatedAt: Date.now(),
      },
      rated: false,
      spectators: 0,
    });
    setOrientation(c.turn());
    setPage("play");
  }
  function exerciseMove(from: Square, to: Square, promote?: string) {
    if (!exercise || exerciseBusy || !game) return;
    const c = chessRef.current,
      copy = new Chess(c.fen());
    let executed;
    try {
      executed = copy.move({ from, to, promotion: promote || "q" });
    } catch {
      return;
    }
    const target = new Chess(c.fen()).move(exercise.line[exerciseStep]);
    if (
      executed.from !== target.from ||
      executed.to !== target.to ||
      (executed.promotion || "") !== (target.promotion || "")
    ) {
      setExerciseMessage(
        "Not quite. Look at the objective and try another move.",
      );
      setSelected(null);
      return;
    }
    c.move(executed);
    let next = {
      ...game,
      fen: c.fen(),
      history: [
        ...game.history,
        {
          from: executed.from,
          to: executed.to,
          promotion: executed.promotion,
          san: executed.san,
          fen: c.fen(),
        },
      ],
    };
    updateGame(next);
    setSelected(null);
    let step = exerciseStep + 1;
    setExerciseStep(step);
    function finishExercise(final: Game) {
      setCompleted((prev) =>
        prev.includes(exercise!.id) ? prev : [...prev, exercise!.id],
      );
      setExerciseMessage(exercise!.explanation);
      updateGame({
        ...final,
        status: "completed",
        reason: "Exercise complete",
      });
      setExerciseBusy(false);
    }
    if (step >= exercise.line.length) {
      finishExercise(next);
      return;
    }
    setExerciseBusy(true);
    setExerciseMessage("Good move. Watch the reply.");
    exerciseTimer.current = setTimeout(() => {
      if (gameRef.current?.id !== game.id) return;
      const reply = c.move(exercise.line[step]);
      step++;
      next = {
        ...next,
        fen: c.fen(),
        history: [
          ...next.history,
          {
            from: reply.from,
            to: reply.to,
            promotion: reply.promotion,
            san: reply.san,
            fen: c.fen(),
          },
        ],
      };
      updateGame(next);
      setExerciseStep(step);
      setExerciseBusy(false);
      setExerciseMessage("Your turn. Complete the idea.");
      if (step >= exercise.line.length) finishExercise(next);
    }, 350);
  }
  function showExerciseHint() {
    if (!exercise || !game || game.status !== "active") return;
    const move = new Chess(game.fen).move(exercise.line[exerciseStep]);
    setHint({ from: move.from, to: move.to });
    setAssisted(true);
    setExerciseMessage(
      `Try ${PIECE_NAMES[move.piece]} to ${move.to}. This is assisted practice.`,
    );
  }
  function analyzePosition(fen = displayedFen) {
    if (busy) {
      notify("Analysis is available after your online game.");
      return;
    }
    if (spectator) {
      notify("Leave the live game before opening analysis.");
      return;
    }
    resetTransient();
    const c = new Chess(fen);
    chessRef.current = c;
    const p = { id: "analysis", name: "Analysis", rating: 0 };
    updateGame({
      id: `analysis-${newId()}`,
      mode: "analysis",
      initialFen: c.fen(),
      fen: c.fen(),
      history: [],
      white: p,
      black: p,
      yourColor: c.turn(),
      status: "active",
      timeControl: "untimed",
      clocks: {
        w: 0,
        b: 0,
        turn: c.turn(),
        increment: 0,
        updatedAt: Date.now(),
      },
      rated: false,
      spectators: 0,
    });
    setExercise(null);
    setPage("play");
  }
  function exportPgn() {
    if (!game) return;
    const c = restore(game);
    c.header(
      "White",
      game.white.name,
      "Black",
      game.black.name,
      "Result",
      game.result || "*",
    );
    const blob = new Blob([c.pgn()], { type: "application/x-chess-pgn" }),
      url = URL.createObjectURL(blob),
      a = document.createElement("a");
    a.href = url;
    a.download = "sovereigns-gambit.pgn";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    notify("PGN downloaded.");
  }
  function importGame() {
    try {
      const c = new Chess();
      try {
        c.loadPgn(pgnInput.trim());
      } catch {
        c.load(pgnInput.trim());
      }
      const history = c.history({ verbose: true }).map((m) => ({
        from: m.from,
        to: m.to,
        promotion: m.promotion,
        san: m.san,
        fen: m.after,
      }));
      const first = history.length
        ? c.history({ verbose: true })[0].before
        : c.fen();
      resetTransient();
      chessRef.current = c;
      updateGame({
        id: `import-${newId()}`,
        mode: "analysis",
        initialFen: first,
        fen: c.fen(),
        history,
        white: {
          id: "analysis",
          name: c.getHeaders().White || "White",
          rating: 0,
        },
        black: {
          id: "analysis",
          name: c.getHeaders().Black || "Black",
          rating: 0,
        },
        yourColor: c.turn(),
        status: "completed",
        reason: "Imported game",
        timeControl: "untimed",
        clocks: {
          w: 0,
          b: 0,
          turn: c.turn(),
          increment: 0,
          updatedAt: Date.now(),
        },
        rated: false,
        spectators: 0,
      });
      setExercise(null);
      setDialog(null);
      setPage("play");
      setReviewCursor(history.length);
    } catch {
      setImportError(
        "That PGN or FEN could not be read. Check the notation and try again.",
      );
    }
  }
  function watch(friendId: string) {
    if (active && !spectator) {
      notify("Finish your current game before watching a friend.");
      return;
    }
    resetTransient();
    connection.send({ type: "game:spectate", friendId });
  }
  const socialProps = {
    user,
    friends,
    requests,
    challenges,
    messages,
    send: connection.send,
    notify,
    online,
    busy: Boolean((active && !spectator) || queued),
    onWatch: watch,
  };
  function emoteSend(id: string) {
    if (!game || spectator || game.status !== "active") return;
    if (Date.now() < emoteReadyAt) return;
    const item = EMOTES.find((e) => e.id === id)!;
    setEmoteReadyAt(Date.now() + 3000);
    setEmoteOpen(false);
    if (isHuman)
      connection.send({ type: "game:emote", id: game.id, emote: id });
    else
      setEmote({
        id: game.id,
        userId: user?.id || "you",
        name: "You",
        emote: item,
        at: Date.now(),
      });
  }
  const bottomColor = orientation,
    topColor = orientation === "w" ? "b" : "w";
  function playerRow(color: Color) {
    const p = game
      ? color === "w"
        ? game.white
        : game.black
      : color === "w"
        ? user
        : null;
    const isBot = game?.mode === "computer" && game.yourColor !== color;
    return (
      <div className={`player-row player-${color}`}>
        <span className={`player-crest ${color}`}>
          <Piece type={isBot ? "n" : "k"} color={color} set={armies[color]} />
        </span>
        <div className="player-details">
          <div>
            <strong>
              {p?.name || (color === "w" ? "Your army" : "The opposing army")}
            </strong>
            {isBot ? (
              <span className="tiny-label">BOT</span>
            ) : game?.yourColor === color ? (
              <span className="you-label">you</span>
            ) : null}
          </div>
          <small>
            {isBot
              ? `Simulated ${game?.elo} Elo`
              : p && isHuman
                ? `${game?.timeControl.startsWith("3") || game?.timeControl.startsWith("5") ? p.blitzRating || p.rating : p.rapidRating || p.rating} · ${color === "w" ? "White" : "Black"}`
                : color === "w"
                  ? "The Radiant Order"
                  : "The Obsidian Host"}
          </small>
        </div>
        <Clock
          game={game}
          color={color}
          paused={paused || game?.phase === "connecting"}
          offset={isHuman ? connection.offset.current : 0}
        />
      </div>
    );
  }
  function chooseMode(mode: typeof setupMode) {
    if (queued && mode !== "online") {
      notify("Cancel the search before changing modes.");
      return;
    }
    setSetupMode(mode);
    if (mode === "online" && timeControl === "untimed") setTimeControl("10+0");
  }
  const modeTitle =
    game?.mode === "online"
      ? "Rated online"
      : game?.mode === "friend"
        ? "Friendly game"
        : game?.mode === "computer"
          ? "Computer game"
          : game?.mode === "analysis"
            ? "Analysis board"
            : game?.mode === "puzzle"
              ? "Tactics practice"
              : game?.mode === "lesson"
                ? "Training grounds"
                : "Standard chess";
  function resultTitle() {
    if (!game?.result) return game?.reason || "Game complete";
    if (game.result === "1/2-1/2") return "A well-fought draw.";
    const winner = game.result === "1-0" ? "w" : "b";
    return game.yourColor
      ? winner === game.yourColor
        ? "Victory is yours."
        : "A lesson for the next game."
      : `${winner === "w" ? "White" : "Black"} wins.`;
  }

  return (
    <div
      className={`app ${game ? "playing" : ""} ${efficient ? "efficient" : ""} ${preferences.reducedMotion ? "reduced-motion" : ""}`}
    >
      <aside className={`sidebar ${mobileMenu ? "mobile-open" : ""}`}>
        <a
          className="brand"
          href="#play"
          onClick={(e) => {
            e.preventDefault();
            setPage("play");
            setMobileMenu(false);
          }}
        >
          <span className="brand-crest">
            <Crown size={27} />
          </span>
          <span>
            SOVEREIGN’S<strong>GAMBIT</strong>
            <small>THE CITADEL COLLECTION</small>
          </span>
        </a>
        <div className="sidebar-divider" />
        <nav aria-label="Main navigation">
          {navItems.map((item) => (
            <button
              key={item.id}
              className={`nav-item ${page === item.id ? "active" : ""}`}
              onClick={() => {
                setPage(item.id);
                setMobileMenu(false);
              }}
            >
              <item.icon size={21} />
              <span>{item.label}</span>
              {item.id === "friends" && badgeCount > 0 ? (
                <b className="nav-badge">{badgeCount}</b>
              ) : page === item.id ? (
                <ChevronRight size={15} className="nav-chevron" />
              ) : null}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="sidebar-note">
            <span className="little-diamond">◇</span>
            <span>
              Classic chess.
              <br />
              An extraordinary realm.
            </span>
          </div>
          <button
            className="profile-button"
            onClick={() => setDialog("profile")}
          >
            <span className="avatar">{(user?.name || "K").slice(0, 1)}</span>
            <span>
              <strong>{user?.name || "Your profile"}</strong>
              <small>
                {user?.games ? `${user.rating} Rapid rating` : "New challenger"}
              </small>
            </span>
            <Settings2 size={17} />
          </button>
        </div>
      </aside>
      <main className="main-shell">
        <header className="topbar">
          <div className="topbar-title">
            <button
              className="icon-button mobile-menu-button"
              aria-label="Open navigation"
              onClick={() => setMobileMenu(!mobileMenu)}
            >
              <Menu size={21} />
            </button>
            <span>{navItems.find((i) => i.id === page)?.label}</span>
            <ChevronRight size={14} />
            <small>
              {page === "play"
                ? modeTitle
                : page === "armory"
                  ? "Piece collection"
                  : page === "friends"
                    ? "Your circle"
                    : page === "learn"
                      ? "Training grounds"
                      : "Tactics practice"}
            </small>
          </div>
          <div className="topbar-actions">
            <span
              className={`connection-status ${online ? "connected" : ""}`}
              title={
                online
                  ? `${onlineCount} connected in your circle`
                  : "Online features reconnect automatically"
              }
            >
              <span />
              {online
                ? "Connected"
                : connection.status === "connecting"
                  ? "Connecting"
                  : connection.offlineOnly
                    ? "Offline ready"
                    : connection.error.includes("not available on this server")
                      ? "Offline practice"
                      : "Reconnecting"}
            </span>
            <button
              className="icon-button"
              aria-label="Appearance and preferences"
              onClick={() => setDialog("settings")}
            >
              <Settings2 size={19} />
            </button>
          </div>
        </header>
        {connection.error && !connection.authError && (
          <div className="connection-banner" role="status">
            {connection.error}
          </div>
        )}
        {connection.authError && (
          <div className="connection-banner">
            Your saved profile is unavailable.{" "}
            <button
              onClick={() => {
                localStorage.removeItem("sg-session-v2");
                localStorage.removeItem(inviteSessionKey());
                location.reload();
              }}
            >
              Create a new profile
            </button>
          </div>
        )}
        {!online && busy && (
          <div className="connection-banner">
            <WifiOff size={17} /> Reconnecting to your game. The clock
            continues; moves are sent after reconnection.
          </div>
        )}
        {incoming.length > 0 && page !== "friends" && (
          <div className="challenge-banner">
            <Swords size={19} />
            <span>
              <strong>{incoming[0].fromName}</strong> challenges you ·{" "}
              {incoming[0].timeControl} · unrated
            </span>
            <button
              className="small-primary"
              disabled={Boolean(active && !spectator)}
              onClick={() =>
                connection.send({
                  type: "challenge:respond",
                  id: incoming[0].id,
                  accept: true,
                })
              }
            >
              Accept
            </button>
            <button
              className="icon-button"
              aria-label="Decline incoming challenge"
              onClick={() =>
                connection.send({
                  type: "challenge:respond",
                  id: incoming[0].id,
                  accept: false,
                })
              }
            >
              <X size={17} />
            </button>
          </div>
        )}
        {game && active && page !== "play" && (
          <button className="return-game" onClick={() => setPage("play")}>
            <span className="live-dot" />
            {spectator
              ? "Watching a friend"
              : `Your ${modeTitle.toLowerCase()} is ${paused ? "paused" : "in progress"}`}
            <span>
              Return to board <ArrowRight size={15} />
            </span>
          </button>
        )}
        <div className="page-content">
          {page === "play" && (
            <>
              <div className="play-heading">
                <div>
                  <div className="section-eyebrow">
                    {spectator
                      ? "A SEAT AT THE BOARD"
                      : game
                        ? `${ARENAS.find((a) => a.id === homeMap)?.name.toUpperCase()} · STANDARD CHESS`
                        : "A TIMELESS GAME. YOUR OWN REALM."}
                  </div>
                  <h1>
                    {exercise
                      ? exercise.title
                      : spectator
                        ? "Watch the game unfold."
                        : game?.mode === "analysis"
                          ? "Explore the position."
                          : game
                            ? "Every move matters."
                            : "The board is yours."}
                  </h1>
                  {!game && (
                    <p className="page-description">
                      Familiar chess. A little more legendary.
                    </p>
                  )}
                </div>
                <span className="rules-badge">
                  <Shield size={15} />
                  Classic rules
                </span>
              </div>
              <div className={`play-layout ${!game ? "has-setup" : ""}`}>
                <section className="board-column" aria-label="Chess game">
                  {isHuman && game?.phase === "connecting" && (
                    <div className="online-connection-panel" role="status">
                      <strong>Connecting to your opponent…</strong>
                      <p>
                        Your clocks start when both players are ready. A server
                        connection is available if the direct connection cannot
                        open.
                      </p>
                    </div>
                  )}
                  {playerRow(topColor)}
                  <div className="home-castle-label">
                    <Shield size={12} />
                    {ARENAS.find((a) => a.id === homeMap)?.name} · White’s home
                    {isHuman && (
                      <span
                        className="transport-pill"
                        data-network={connection.network}
                      >
                        {connection.network === "direct"
                          ? "Direct connection"
                          : connection.network === "connecting"
                            ? "Connecting players"
                            : "Server connection"}
                      </span>
                    )}
                  </div>
                  <div className="board-container">
                    <GameBoard
                      fen={displayedFen}
                      orientation={orientation}
                      pieceSet={preferences.pieceSet}
                      armies={armies}
                      arena={homeMap}
                      view={view}
                      models={Boolean(game && !efficient)}
                      allowSlow={preferences.efficiency === "off"}
                      competitive={Boolean(isHuman)}
                      animationMode={preferences.battleAnimations}
                      reducedMotion={preferences.reducedMotion}
                      sound={preferences.sound}
                      selected={selected}
                      onSelect={selectSquare}
                      onMove={requestMove}
                      playerColor={playerColor}
                      interactive={Boolean(
                        game &&
                          active &&
                          !spectator &&
                          !paused &&
                          game.phase !== "connecting" &&
                          reviewCursor === null &&
                          !exerciseBusy,
                      )}
                      legal={legal}
                      lastMove={displayedLast}
                      premove={premove}
                      coordinates={preferences.coordinates}
                      hint={assistance || exercise ? hint : null}
                      onSceneFail={() => {
                        setView("2d");
                        notify("The 2D board is ready.");
                      }}
                    />
                    {paused && (
                      <div className="board-pause">
                        <Pause size={35} />
                        <h2>Take your time.</h2>
                        <p>Your computer game is paused.</p>
                        <button className="primary-button" onClick={pause}>
                          <Play size={17} />
                          Resume game
                        </button>
                      </div>
                    )}
                    {emote &&
                      !preferences.muteEmotes &&
                      game?.id === emote.id && (
                        <div
                          className={`emote-bubble ${emote.userId === user?.id ? "own" : ""}`}
                          role="status"
                        >
                          <span>{emote.emote.icon}</span>
                          <div>
                            <strong>{emote.emote.label}</strong>
                            <small>{emote.name}</small>
                          </div>
                        </div>
                      )}
                    {promotion && (
                      <div
                        className="promotion-panel"
                        role="dialog"
                        aria-label="Choose promotion"
                      >
                        <strong>Promote your pawn</strong>
                        <div>
                          {(["q", "r", "b", "n"] as const).map((type) => (
                            <button
                              key={type}
                              aria-label={`Promote to ${PIECE_NAMES[type]}`}
                              onClick={() => {
                                const pending = promotion;
                                setPromotion(null);
                                requestMove(pending.from, pending.to, type);
                              }}
                            >
                              <Piece
                                type={type}
                                color={playerColor || "w"}
                                set={armies[chess.turn()]}
                              />
                            </button>
                          ))}
                        </div>
                        <button
                          className="text-button"
                          onClick={() => setPromotion(null)}
                        >
                          Cancel
                        </button>
                      </div>
                    )}
                  </div>
                  {playerRow(bottomColor)}
                  <div className="board-toolbar">
                    <div>
                      <button
                        className="icon-button"
                        aria-label="Flip board"
                        onClick={() =>
                          setOrientation((c) => (c === "w" ? "b" : "w"))
                        }
                      >
                        <FlipVertical2 size={18} />
                      </button>
                      <button
                        className="icon-button"
                        aria-label={
                          preferences.sound
                            ? "Mute move sounds"
                            : "Enable move sounds"
                        }
                        onClick={() =>
                          setPreferences((p) => ({ ...p, sound: !p.sound }))
                        }
                      >
                        {preferences.sound ? (
                          <Volume2 size={19} />
                        ) : (
                          <VolumeX size={19} />
                        )}
                      </button>
                      <span className="toolbar-separator" />
                      <button
                        className="text-button collection-shortcut"
                        onClick={() => setPage("armory")}
                      >
                        <Shield size={15} />
                        {SETS.find((s) => s.id === preferences.pieceSet)?.name}
                        <ChevronDown size={13} />
                      </button>
                    </div>
                    <div>
                      {game && (
                        <button
                          className="view-toggle"
                          aria-label={`Switch to ${view === "2d" ? "3D" : "2D"} board`}
                          onClick={() => {
                            if (efficient && view === "2d") {
                              notify(
                                "Turn off Performance mode in preferences to use 3D.",
                              );
                              return;
                            }
                            setView((v) => (v === "2d" ? "3d" : "2d"));
                          }}
                        >
                          {view === "2d" ? "2D pieces" : "3D castle"}
                          <ChevronDown size={13} />
                        </button>
                      )}
                      {game && active && !spectator && (
                        <div className="emote-control">
                          <button
                            className="icon-button"
                            aria-label="Send an emote"
                            onClick={() => setEmoteOpen(!emoteOpen)}
                          >
                            <Smile size={20} />
                          </button>
                          {emoteOpen && (
                            <div className="emote-picker">
                              <header>
                                <strong>A little character.</strong>
                                <button
                                  className="icon-button"
                                  aria-label="Close emotes"
                                  onClick={() => setEmoteOpen(false)}
                                >
                                  <X size={16} />
                                </button>
                              </header>
                              <div>
                                {EMOTES.map((item) => (
                                  <button
                                    key={item.id}
                                    onClick={() => emoteSend(item.id)}
                                    aria-label={item.label}
                                    disabled={Date.now() < emoteReadyAt}
                                  >
                                    <span>{item.icon}</span>
                                    <small>{item.label}</small>
                                  </button>
                                ))}
                              </div>
                              <label>
                                <input
                                  type="checkbox"
                                  checked={preferences.muteEmotes}
                                  onChange={(e) =>
                                    setPreferences((p) => ({
                                      ...p,
                                      muteEmotes: e.target.checked,
                                    }))
                                  }
                                />
                                Mute incoming emotes
                              </label>
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                  <div className="board-status" aria-live="polite">
                    {premove ? (
                      <>
                        <span className="premove-dot" />
                        Premove: {premove.from} → {premove.to}
                        <button onClick={() => setPremove(null)}>Cancel</button>
                      </>
                    ) : reviewCursor !== null ? (
                      <>
                        <BookOpen size={15} />
                        Position {reviewCursor} of {game?.history.length}
                        <button
                          onClick={() => {
                            setReviewCursor(null);
                            setHint(null);
                          }}
                        >
                          Return to {active ? "live board" : "final position"}
                        </button>
                      </>
                    ) : game ? (
                      <>
                        <span
                          className={`live-dot ${!active ? "finished" : ""}`}
                        />
                        {paused
                          ? "Game paused"
                          : !active
                            ? game.reason
                            : thinking
                              ? "Computer is thinking…"
                              : exerciseBusy
                                ? "Watch the reply…"
                                : spectator
                                  ? `${chess.turn() === "w" ? "White" : "Black"} to move`
                                  : chess.inCheck()
                                    ? "Check — protect your king"
                                    : chess.turn() === playerColor
                                      ? "Your move"
                                      : game.mode === "analysis"
                                        ? `${chess.turn() === "w" ? "White" : "Black"} to move`
                                        : "Opponent’s move"}
                        {spectator && (
                          <button onClick={newGame}>Leave game</button>
                        )}
                      </>
                    ) : (
                      <>
                        <span className="small-diamond">◇</span>Ready when you
                        are.
                      </>
                    )}
                  </div>
                  {game && isHuman && (
                    <p className="fair-play-note">
                      <Shield size={13} />
                      {spectator
                        ? "Live spectating · moves only"
                        : `${game.rated ? "Rated" : "Unrated"} · ${game.timeControl} · no hints or move feedback`}
                      {game.spectators > 0 && (
                        <span>
                          <Eye size={13} />
                          {game.spectators}
                        </span>
                      )}
                    </p>
                  )}
                </section>
                <aside className="game-panel-column">
                  {!game ? (
                    <section className="setup-panel panel">
                      <div className="panel-intro">
                        <span className="small-crest">
                          <Swords size={24} />
                        </span>
                        <h2>Find your next game.</h2>
                        <p>A quiet practice or a worthy opponent.</p>
                      </div>
                      <div className="mode-tabs" aria-label="Choose game mode">
                        {(["online", "computer", "friend"] as const).map(
                          (mode) => (
                            <button
                              key={mode}
                              className={setupMode === mode ? "active" : ""}
                              onClick={() => chooseMode(mode)}
                            >
                              {mode === "online" ? (
                                <Users size={16} />
                              ) : mode === "computer" ? (
                                <Crown size={16} />
                              ) : (
                                <Swords size={16} />
                              )}
                              <span>
                                {mode === "online"
                                  ? "Online"
                                  : mode === "computer"
                                    ? "Computer"
                                    : "Friend"}
                              </span>
                            </button>
                          ),
                        )}
                      </div>
                      {setupMode === "computer" ? (
                        <>
                          <div className="setup-group">
                            <div className="field-heading">
                              <label htmlFor="computer-elo">
                                Computer strength
                              </label>
                              <span className="elo-pill">Simulated {elo}</span>
                            </div>
                            <input
                              id="computer-elo"
                              type="range"
                              min="400"
                              max="2000"
                              step="200"
                              value={elo}
                              onChange={(e) => setElo(Number(e.target.value))}
                            />
                            <div className="range-labels">
                              <span>Learning</span>
                              <span>Challenging</span>
                            </div>
                            <p className="field-note">
                              Simulated Elo is a training level, not a rated
                              player.
                            </p>
                          </div>
                          <div className="setup-group">
                            <span className="field-label">Play as</span>
                            <div className="side-picker">
                              {(["w", "random", "b"] as const).map((side) => (
                                <button
                                  key={side}
                                  className={
                                    chosenSide === side ? "chosen" : ""
                                  }
                                  aria-pressed={chosenSide === side}
                                  onClick={() => setChosenSide(side)}
                                >
                                  {side === "random" ? (
                                    <span className="random-sides">◐</span>
                                  ) : (
                                    <Piece
                                      type="k"
                                      color={side}
                                      set={preferences.pieceSet}
                                    />
                                  )}
                                  <span>
                                    {side === "w"
                                      ? "White"
                                      : side === "b"
                                        ? "Black"
                                        : "Random"}
                                  </span>
                                </button>
                              ))}
                            </div>
                          </div>
                        </>
                      ) : setupMode === "online" ? (
                        <>
                          <label className="select-field online-faction-choice">
                            <strong>Your faction</strong>
                            <select
                              aria-label="Your faction"
                              disabled={queued}
                              value={preferences.pieceSet}
                              onChange={(e) =>
                                setPreferences((p) => ({
                                  ...p,
                                  pieceSet: e.target
                                    .value as Preferences["pieceSet"],
                                }))
                              }
                            >
                              {SETS.map((s) => (
                                <option key={s.id} value={s.id}>
                                  {s.name}
                                </option>
                              ))}
                            </select>
                          </label>
                          <div className="online-intro">
                            <Shield size={18} />
                            <p>
                              <strong>Real players. Real chess.</strong>
                              <br />
                              Rated standard chess. No tips or move feedback.
                              White’s faction hosts the castle.
                            </p>
                          </div>
                        </>
                      ) : (
                        <div className="online-intro">
                          <Users size={19} />
                          <p>
                            <strong>A friendly rivalry.</strong>
                            <br />
                            Share a private link or choose someone from your
                            friends list. Friendly games are unrated.
                          </p>
                        </div>
                      )}
                      {setupMode !== "friend" && (
                        <div className="setup-group">
                          <span className="field-label">Time control</span>
                          <TimePicker
                            value={timeControl}
                            onChange={setTimeControl}
                            allowUntimed={setupMode === "computer"}
                            disabled={queued && setupMode === "online"}
                          />
                          {timeControl.includes("+") && (
                            <p className="field-note">
                              {timeControl.split("+")[0]} minutes each
                              {timeControl.split("+")[1] !== "0"
                                ? `, plus ${timeControl.split("+")[1]} seconds after every move`
                                : ""}
                              .
                            </p>
                          )}
                        </div>
                      )}
                      {setupMode === "computer" && (
                        <div className="feedback-option">
                          <Toggle
                            checked={moveFeedback}
                            onChange={setMoveFeedback}
                            label="Move feedback"
                            detail="See move quality and use optional hints."
                          />
                        </div>
                      )}
                      {setupMode === "computer" ? (
                        <button
                          className="primary-button start-game"
                          onClick={startComputer}
                        >
                          Play computer <ArrowRight size={18} />
                        </button>
                      ) : setupMode === "online" ? (
                        <>
                          <button
                            className="primary-button start-game"
                            disabled={!online}
                            onClick={() =>
                              connection.send({
                                type: queued ? "queue:leave" : "queue:join",
                                army: preferences.pieceSet,
                                timeControl,
                              })
                            }
                          >
                            {queued ? (
                              <>
                                <LoaderCircle size={18} className="spin" />
                                Cancel search
                              </>
                            ) : (
                              <>
                                Play{" "}
                                {
                                  TIME_CONTROLS.find(
                                    (t) => t.id === timeControl,
                                  )?.label
                                }
                                <ArrowRight size={18} />
                              </>
                            )}
                          </button>
                          {queued && (
                            <div className="queue-note">
                              <strong>Looking for a human opponent…</strong>
                              <p>
                                Your clock starts once both players are
                                connected. You can keep waiting or cancel and
                                choose Computer.
                              </p>
                            </div>
                          )}
                        </>
                      ) : (
                        <div className="friend-start-actions">
                          <button
                            className="primary-button start-game"
                            disabled={Boolean(active && isHuman)}
                            onClick={() => {
                              setIncomingCode(null);
                              setInvitePreview(null);
                              setInviteError("");
                              setDialog("invite");
                            }}
                          >
                            Share a friend link <ArrowRight size={18} />
                          </button>
                          <button
                            className="secondary-button"
                            onClick={() => setPage("friends")}
                          >
                            Choose from friends <Users size={17} />
                          </button>
                        </div>
                      )}
                      <p className="setup-footer">
                        <Shield size={13} />
                        {setupMode === "computer"
                          ? "Unrated · your pace, your game"
                          : setupMode === "online"
                            ? "Human matchmaking · no automatic bots"
                            : "Private conversation · friendly competition"}
                      </p>
                    </section>
                  ) : exercise ? (
                    <section className="exercise-panel panel">
                      <div className="panel-eyebrow">
                        <BookOpen size={17} />
                        {game.mode === "lesson"
                          ? "LEARN BY PLAYING"
                          : "TACTICS PRACTICE"}
                      </div>
                      <span className="theme-tag">{exercise.theme}</span>
                      <h2>{exercise.title}</h2>
                      <p>{exercise.subtitle}</p>
                      <div className="exercise-progress">
                        {exercise.line.map((_, i) => (
                          <span
                            key={i}
                            className={i < exerciseStep ? "done" : ""}
                          />
                        ))}
                      </div>
                      {exerciseMessage && (
                        <div
                          className={`exercise-message ${game.status === "completed" ? "success" : ""}`}
                        >
                          {game.status === "completed" && <Check size={20} />}
                          <p>{exerciseMessage}</p>
                        </div>
                      )}
                      {game.status === "completed" ? (
                        <>
                          <span className="practice-label">
                            {assisted
                              ? "Completed with a hint"
                              : "Exercise complete"}
                          </span>
                          <button
                            className="primary-button"
                            onClick={() => {
                              const list =
                                game.mode === "lesson" ? LESSONS : PUZZLES;
                              const next =
                                list[
                                  (list.findIndex((x) => x.id === exercise.id) +
                                    1) %
                                    list.length
                                ];
                              startExercise(
                                next,
                                game.mode as "lesson" | "puzzle",
                              );
                            }}
                          >
                            Next {game.mode === "lesson" ? "lesson" : "puzzle"}
                            <ArrowRight size={17} />
                          </button>
                        </>
                      ) : (
                        <button
                          className="secondary-button"
                          onClick={showExerciseHint}
                          disabled={exerciseBusy}
                        >
                          <Lightbulb size={17} />
                          Show a hint
                        </button>
                      )}
                      <button
                        className="text-button"
                        onClick={() =>
                          startExercise(
                            exercise,
                            game.mode as "lesson" | "puzzle",
                          )
                        }
                      >
                        <RotateCcw size={15} />
                        Start this position again
                      </button>
                      <button
                        className="text-button"
                        onClick={() =>
                          setPage(game.mode === "lesson" ? "learn" : "puzzles")
                        }
                      >
                        <ArrowLeft size={15} />
                        Back to {game.mode === "lesson" ? "lessons" : "puzzles"}
                      </button>
                    </section>
                  ) : (
                    <>
                      {game.status === "completed" && (
                        <section className="result-panel panel">
                          <div className="result-icon">
                            <Trophy size={27} />
                          </div>
                          <small>{game.result || "GAME COMPLETE"}</small>
                          <h2>{resultTitle()}</h2>
                          <p>
                            {game.reason}
                            {game.ratingDelta && game.yourColor && (
                              <span>
                                {" "}
                                · Rating{" "}
                                {game.ratingDelta[game.yourColor] >= 0
                                  ? "+"
                                  : ""}
                                {game.ratingDelta[game.yourColor]}
                              </span>
                            )}
                          </p>
                          <div>
                            <button
                              className="primary-button"
                              onClick={() => {
                                setReviewCursor(0);
                                setSelected(null);
                              }}
                            >
                              Review game <BookOpen size={17} />
                            </button>
                            <button
                              className="secondary-button"
                              onClick={newGame}
                            >
                              New game <Plus size={17} />
                            </button>
                          </div>
                        </section>
                      )}
                      <section className="moves-panel panel">
                        <div className="panel-tabs">
                          <button
                            className={sideTab === "moves" ? "active" : ""}
                            onClick={() => setSideTab("moves")}
                          >
                            Moves
                          </button>
                          <button
                            className={sideTab === "friends" ? "active" : ""}
                            onClick={() => setSideTab("friends")}
                          >
                            Friends
                            {badgeCount > 0 && (
                              <span className="count">{badgeCount}</span>
                            )}
                          </button>
                          <span className="game-format">
                            {game.mode === "computer"
                              ? `SIM ${game.elo}`
                              : game.mode === "analysis"
                                ? "STUDY"
                                : game.timeControl}
                          </span>
                        </div>
                        {sideTab === "friends" ? (
                          <Social {...socialProps} compact />
                        ) : (
                          <>
                            <Moves
                              game={game}
                              cursor={reviewCursor}
                              onCursor={(ply) => {
                                setReviewCursor(
                                  ply === game.history.length && active
                                    ? null
                                    : ply,
                                );
                                setSelected(null);
                                setHint(null);
                              }}
                            />
                            {game.drawOffer &&
                              game.drawOffer !== user?.id &&
                              active && (
                                <div className="draw-offer">
                                  <p>Your opponent offers a draw.</p>
                                  <button
                                    className="small-primary"
                                    onClick={() =>
                                      connection.send({
                                        type: "game:draw",
                                        id: game.id,
                                        accept: true,
                                      })
                                    }
                                  >
                                    Accept
                                  </button>
                                  <button
                                    className="text-button"
                                    onClick={() =>
                                      connection.send({
                                        type: "game:draw",
                                        id: game.id,
                                        decline: true,
                                      })
                                    }
                                  >
                                    Decline
                                  </button>
                                </div>
                              )}
                            <div className="match-actions">
                              {active &&
                                !spectator &&
                                game.mode !== "analysis" && (
                                  <>
                                    <button
                                      className="text-button"
                                      onClick={() => setDialog("resign")}
                                    >
                                      <Flag size={16} />
                                      Resign
                                    </button>
                                    {isHuman ? (
                                      <button
                                        className="text-button"
                                        disabled={
                                          game.drawOffer === user?.id || !online
                                        }
                                        onClick={() => {
                                          connection.send({
                                            type: "game:draw",
                                            id: game.id,
                                          });
                                          notify("Draw offered.");
                                        }}
                                      >
                                        ½{" "}
                                        {game.drawOffer === user?.id
                                          ? "Draw offered"
                                          : "Offer draw"}
                                      </button>
                                    ) : (
                                      <button
                                        className="text-button"
                                        onClick={pause}
                                      >
                                        {paused ? (
                                          <Play size={16} />
                                        ) : (
                                          <Pause size={16} />
                                        )}{" "}
                                        {paused ? "Resume" : "Pause"}
                                      </button>
                                    )}
                                  </>
                                )}
                              {!active && (
                                <>
                                  <button
                                    className="text-button"
                                    onClick={exportPgn}
                                  >
                                    <Download size={16} />
                                    PGN
                                  </button>
                                  {!spectator && (
                                    <button
                                      className="text-button"
                                      onClick={() => analyzePosition()}
                                    >
                                      <Sparkles size={16} />
                                      Analyze position
                                    </button>
                                  )}
                                </>
                              )}
                              {spectator && active && (
                                <button
                                  className="text-button"
                                  onClick={newGame}
                                >
                                  <Eye size={16} />
                                  Leave spectating
                                </button>
                              )}
                              {game.mode === "analysis" && (
                                <>
                                  <button
                                    className="text-button"
                                    onClick={exportPgn}
                                  >
                                    <Download size={16} />
                                    PGN
                                  </button>
                                  <button
                                    className="text-button"
                                    onClick={newGame}
                                  >
                                    Close analysis
                                  </button>
                                </>
                              )}
                            </div>
                          </>
                        )}
                      </section>
                      {assistance && active && reviewCursor === null && (
                        <section className="coach-panel panel">
                          <header>
                            <span className="coach-avatar">
                              <Crown size={22} />
                            </span>
                            <div>
                              <h3>
                                {game.mode === "analysis"
                                  ? "Position tools"
                                  : "Your practice companion"}
                              </h3>
                              <small>
                                {game.mode === "analysis"
                                  ? "Explore freely"
                                  : "Move feedback enabled for this game"}
                              </small>
                            </div>
                          </header>
                          {feedback && (
                            <div
                              className={`move-feedback feedback-${feedback.verdict?.toLowerCase()}`}
                            >
                              <span>
                                {feedback.verdict === "Blunder"
                                  ? "??"
                                  : feedback.verdict === "Mistake"
                                    ? "?"
                                    : feedback.verdict === "Inaccuracy"
                                      ? "?!"
                                      : "✓"}
                              </span>
                              <div>
                                <strong>
                                  {feedback.san} · {feedback.verdict}
                                </strong>
                                <p>
                                  {feedback.loss > 90
                                    ? `Consider ${feedback.best} instead. This quick search found a stronger continuation.`
                                    : "Your move keeps the position active in this quick analysis."}
                                </p>
                              </div>
                            </div>
                          )}
                          <div className="coach-actions">
                            <button
                              className="secondary-button"
                              disabled={
                                thinking ||
                                paused ||
                                chess.turn() !== playerColor
                              }
                              onClick={requestHint}
                            >
                              <Lightbulb size={16} />
                              Hint
                            </button>
                            {game.mode === "computer" && (
                              <button
                                className="secondary-button"
                                disabled={!game.history.length || paused}
                                onClick={undo}
                              >
                                <RotateCcw size={16} />
                                Take back
                              </button>
                            )}
                          </div>
                          <p className="field-note">
                            Training estimates · not a deep engine review.
                          </p>
                        </section>
                      )}
                      {game.mode === "computer" && !game.feedback && active && (
                        <div className="unassisted-note">
                          <Shield size={17} />
                          <div>
                            <strong>Just you and the board.</strong>
                            <p>
                              Move feedback and hints are off for this game.
                            </p>
                          </div>
                        </div>
                      )}
                      {game.mode === "computer" && (
                        <button
                          className="text-button new-computer"
                          onClick={newGame}
                        >
                          <Plus size={16} />
                          Set up a new game
                        </button>
                      )}
                    </>
                  )}
                  {!game && (
                    <button
                      className="learn-callout"
                      onClick={() => setPage("learn")}
                    >
                      <span>
                        <BookOpen size={21} />
                      </span>
                      <div>
                        <strong>New to the game?</strong>
                        <small>Learn one move at a time.</small>
                      </div>
                      <ArrowRight size={18} />
                    </button>
                  )}
                </aside>
              </div>
              {!game && (
                <section className="under-board">
                  <div className="under-heading">
                    <h2>Your next chapter</h2>
                    <span>A little practice goes a long way.</span>
                  </div>
                  <div className="quick-links">
                    <button onClick={() => startExercise(PUZZLES[0], "puzzle")}>
                      <span className="quick-icon">
                        <Gem size={22} />
                      </span>
                      <div>
                        <small>TACTICS</small>
                        <strong>Find the winning move</strong>
                        <span>A fresh perspective on the board.</span>
                      </div>
                      <ArrowRight size={18} />
                    </button>
                    <button onClick={() => setPage("friends")}>
                      <span className="quick-icon">
                        <Users size={23} />
                      </span>
                      <div>
                        <small>GOOD COMPANY</small>
                        <strong>Bring a friend to the table</strong>
                        <span>Play, chat, and watch together.</span>
                      </div>
                      <ArrowRight size={18} />
                    </button>
                  </div>
                </section>
              )}
              {(!game || game.status === "completed") && !spectator && (
                <div className="study-shortcuts">
                  <button
                    className="text-button"
                    onClick={() => analyzePosition()}
                  >
                    <Sparkles size={16} />
                    Open an analysis board
                  </button>
                  <button
                    className="text-button"
                    onClick={() => {
                      setPgnInput("");
                      setImportError("");
                      setDialog("import");
                    }}
                  >
                    <BookOpen size={16} />
                    Import PGN / FEN
                  </button>
                </div>
              )}
              {(!game || game.status === "completed") &&
                archive.length + localArchive.length > 0 && (
                  <section className="recent-games">
                    <div className="under-heading">
                      <h2>Recent games</h2>
                      <button
                        className="text-button"
                        disabled={busy || spectator}
                        onClick={() => {
                          setPgnInput("");
                          setImportError("");
                          setDialog("import");
                        }}
                      >
                        Import PGN / FEN
                      </button>
                    </div>
                    {[...archive, ...localArchive].slice(0, 5).map((g) => (
                      <button
                        className="archive-row"
                        key={g.id}
                        onClick={() => {
                          resetTransient();
                          chessRef.current = restore(g);
                          updateGame({
                            ...g,
                            yourColor:
                              g.white.id === user?.id
                                ? "w"
                                : g.black.id === user?.id
                                  ? "b"
                                  : g.yourColor,
                          });
                          setExercise(null);
                          setReviewCursor(g.history.length);
                        }}
                      >
                        <span className="archive-result">{g.result}</span>
                        <span>
                          {g.white.name} <small>vs</small> {g.black.name}
                        </span>
                        <small>
                          {g.mode === "computer"
                            ? "Computer"
                            : g.rated
                              ? "Rated"
                              : "Friendly"}{" "}
                          · {g.history.length} moves
                        </small>
                        <ChevronRight size={17} />
                      </button>
                    ))}
                  </section>
                )}
            </>
          )}
          {(page === "learn" || page === "puzzles") && (
            <section className="training-page">
              <div className="section-eyebrow">
                {page === "learn"
                  ? "ONE IDEA AT A TIME"
                  : "SMALL POSITIONS. BIG IDEAS."}
              </div>
              <h1>
                {page === "learn"
                  ? "Build your chess intuition."
                  : "Find a little brilliance."}
              </h1>
              <p className="page-description">
                {page === "learn"
                  ? "Clear explanations. Real positions. Learn by moving the pieces."
                  : "Play the complete idea on the board, including your opponent’s reply."}
              </p>
              <div className="training-intro panel">
                <span className="empty-crest">
                  {page === "learn" ? (
                    <BookOpen size={29} />
                  ) : (
                    <Gem size={29} />
                  )}
                </span>
                <div>
                  <h2>
                    {page === "learn"
                      ? "Start with the foundations."
                      : "Tactics you can trust."}
                  </h2>
                  <p>
                    {page === "learn"
                      ? `${LESSONS.filter((x) => completed.includes(x.id)).length} of ${LESSONS.length} lessons completed. Your progress is saved on this device.`
                      : "Hand-checked positions with legal solution lines. Practice at your own pace; hints are always optional."}
                  </p>
                </div>
              </div>
              <div className="exercise-grid">
                {(page === "learn" ? LESSONS : PUZZLES).map((item, i) => (
                  <button
                    key={item.id}
                    className="exercise-card panel"
                    onClick={() =>
                      startExercise(
                        item,
                        page === "learn" ? "lesson" : "puzzle",
                      )
                    }
                  >
                    <span
                      className={`exercise-number ${completed.includes(item.id) ? "complete" : ""}`}
                    >
                      {completed.includes(item.id) ? (
                        <Check size={20} />
                      ) : (
                        String(i + 1).padStart(2, "0")
                      )}
                    </span>
                    <small>{item.theme}</small>
                    <h2>{item.title}</h2>
                    <p>{page === "learn" ? item.subtitle : item.subtitle}</p>
                    <span className="exercise-action">
                      {completed.includes(item.id)
                        ? "Practice again"
                        : page === "learn"
                          ? "Start lesson"
                          : "Solve on the board"}
                      <ArrowRight size={17} />
                    </span>
                  </button>
                ))}
              </div>
            </section>
          )}
          {page === "friends" && <Social {...socialProps} />}
          {page === "armory" && (
            <Armory
              preferences={preferences}
              onChange={setPreferences}
              lowPower={efficient}
            />
          )}
        </div>
        <footer className="app-footer">
          <span>◇ SOVEREIGN’S GAMBIT</span>
          <span>Standard chess. Extraordinary character.</span>
        </footer>
      </main>
      <nav className="bottom-nav" aria-label="Mobile navigation">
        {navItems.map((item) => (
          <button
            key={item.id}
            className={page === item.id ? "active" : ""}
            onClick={() => setPage(item.id)}
          >
            <item.icon size={20} />
            <span>{item.label}</span>
            {item.id === "friends" && badgeCount > 0 && <b>{badgeCount}</b>}
          </button>
        ))}
      </nav>
      {toast && (
        <div className="toast" role="status">
          <span>{toast}</span>
          <button aria-label="Dismiss message" onClick={() => setToast("")}>
            <X size={17} />
          </button>
        </div>
      )}
      {dialog === "settings" && (
        <Dialog title="Make yourself at home." onClose={() => setDialog(null)}>
          <div className="dialog-content">
            <MobileSettings busy={Boolean(active && isHuman)} notify={notify} />
            <p className="dialog-description">
              A clear board, a comfortable game. Your preferences are saved on
              this device.
            </p>
            <Toggle
              checked={preferences.coordinates}
              onChange={(coordinates) =>
                setPreferences((p) => ({ ...p, coordinates }))
              }
              label="Board coordinates"
              detail="Show ranks and files around the board."
            />
            <Toggle
              checked={preferences.sound}
              onChange={(sound) => setPreferences((p) => ({ ...p, sound }))}
              label="Move sounds"
              detail="A quiet sound for moves and captures."
            />
            <Toggle
              checked={preferences.muteEmotes}
              onChange={(muteEmotes) =>
                setPreferences((p) => ({ ...p, muteEmotes }))
              }
              label="Mute emotes"
              detail="Hide reactions while you concentrate."
            />
            <Toggle
              checked={preferences.reducedMotion}
              onChange={(reducedMotion) =>
                setPreferences((p) => ({ ...p, reducedMotion }))
              }
              label="Reduced motion"
              detail="Keep transitions and reactions still."
            />
            <label className="select-field">
              <strong>Battle animations</strong>
              <select
                value={preferences.battleAnimations}
                onChange={(e) =>
                  setPreferences((p) => ({
                    ...p,
                    battleAnimations: e.target
                      .value as Preferences["battleAnimations"],
                  }))
                }
              >
                <option value="cinematic">
                  Cinematic · full encounters in 3D
                </option>
                <option value="brief">Brief · quick strikes</option>
                <option value="off">Off · instant moves</option>
              </select>
              <small>
                Online games always use brief encounters. Every move is applied
                immediately.
              </small>
            </label>
            <label className="select-field">
              <strong>Performance mode</strong>
              <select
                value={preferences.efficiency}
                onChange={(e) => {
                  setPreferences((p) => ({
                    ...p,
                    efficiency: e.target.value as Preferences["efficiency"],
                  }));
                  if (e.target.value === "on") setView("2d");
                }}
              >
                <option value="auto">Automatic · recommended</option>
                <option value="on">On · lightest graphics</option>
                <option value="off">Off · full detail</option>
              </select>
              <small>
                Automatic simplifies decoration on low-memory devices. Ordinary
                2D chess never loads the 3D engine.
              </small>
            </label>
            <button
              className="secondary-button"
              onClick={() => {
                setDialog(null);
                setPage("armory");
              }}
            >
              <Shield size={17} />
              Choose your piece set
            </button>
            <button
              className="text-button"
              onClick={() => setDialog("profile")}
            >
              <Users size={17} />
              Edit your profile
            </button>
          </div>
        </Dialog>
      )}
      {dialog === "invite" && (
        <FriendInvite
          own={ownInvite}
          preview={invitePreview}
          code={incomingCode}
          online={online}
          offlineOnly={connection.offlineOnly}
          busy={Boolean(active && isHuman) || queued}
          faction={preferences.pieceSet}
          error={inviteError}
          notify={notify}
          onClose={() => {
            setDialog(null);
            setIncomingCode(null);
            setInvitePreview(null);
            connection.send({ type: "invite:clear" });
            const u = new URL(location.href);
            u.searchParams.delete("play");
            history.replaceState(null, "", u);
          }}
          onCreate={(tc, color) => {
            setInviteError("");
            connection.send({
              type: "invite:create",
              timeControl: tc,
              color,
              army: preferences.pieceSet,
            });
          }}
          onCancel={(code) => {
            connection.send({ type: "invite:cancel", code });
          }}
          onJoin={(code) => {
            setInviteError("");
            connection.send({
              type: "invite:join",
              code,
              army: preferences.pieceSet,
            });
          }}
          onPreview={(code) => {
            setIncomingCode(code);
            setInvitePreview(null);
            setInviteError("");
            connection.send({ type: "invite:inspect", code });
          }}
          onSettings={() => setDialog("settings")}
        />
      )}
      {dialog === "profile" && (
        <Dialog
          title="Your place in the realm."
          onClose={() => setDialog(null)}
        >
          <form
            className="dialog-content"
            onSubmit={(e) => {
              e.preventDefault();
              connection.send({
                type: "profile:update",
                name: profileName,
                allowSpectators: profileWatch,
              });
              setDialog(null);
            }}
          >
            <label className="select-field">
              <strong>Player name</strong>
              <input
                value={profileName}
                onChange={(e) => setProfileName(e.target.value)}
                minLength={2}
                maxLength={24}
                required
                placeholder="Your name"
              />
            </label>
            <div className="profile-code">
              <span>Friend code</span>
              <strong>{user?.code || "Connecting…"}</strong>
              <button
                type="button"
                className="icon-button"
                aria-label="Copy your friend code"
                onClick={() => {
                  void navigator.clipboard
                    ?.writeText(user?.code || "")
                    .then(() => notify("Friend code copied."));
                }}
              >
                <Copy size={16} />
              </button>
            </div>
            <Toggle
              checked={profileWatch}
              onChange={setProfileWatch}
              label="Let friends spectate"
              detail="Friends can watch your online and friendly games."
            />
            <p className="field-note">
              This browser keeps your profile sign-in. Your friends, messages,
              and online games are stored on the game server.
            </p>
            <button className="primary-button" disabled={!online}>
              Save profile <Check size={17} />
            </button>
          </form>
        </Dialog>
      )}
      {dialog === "resign" && (
        <Dialog title="Resign this game?" onClose={() => setDialog(null)}>
          <div className="dialog-content">
            <p className="dialog-description">
              Your opponent will win by resignation.
            </p>
            <div className="dialog-actions">
              <button
                className="secondary-button"
                onClick={() => setDialog(null)}
              >
                Keep playing
              </button>
              <button
                className="danger-button"
                onClick={() => {
                  if (game) {
                    if (isHuman)
                      connection.send({ type: "game:resign", id: game.id });
                    else {
                      engine.stop();
                      completeLocal(
                        game,
                        game.yourColor === "w" ? "0-1" : "1-0",
                        "Resignation",
                      );
                    }
                  }
                  setDialog(null);
                }}
              >
                Resign game
              </button>
            </div>
          </div>
        </Dialog>
      )}
      {dialog === "import" && (
        <Dialog
          title="Bring a game to the board."
          onClose={() => setDialog(null)}
        >
          <div className="dialog-content">
            <label className="select-field">
              <strong>PGN game or FEN position</strong>
              <textarea
                value={pgnInput}
                onChange={(e) => setPgnInput(e.target.value)}
                rows={7}
                placeholder="Paste your game notation or position…"
              />
            </label>
            {importError && <p className="form-error">{importError}</p>}
            <button
              className="primary-button"
              disabled={!pgnInput.trim()}
              onClick={importGame}
            >
              Open analysis <ArrowRight size={17} />
            </button>
          </div>
        </Dialog>
      )}
    </div>
  );
}
export default App;

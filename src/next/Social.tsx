import React, { useEffect, useRef, useState } from "react";
import {
  ArrowLeft,
  Check,
  Copy,
  Eye,
  MessageCircle,
  Plus,
  Send,
  Shield,
  Swords,
  UserPlus,
  Users,
  X,
} from "lucide-react";
import {
  type Player,
  type Friend,
  type FriendRequest,
  type Challenge,
  type ChatMessage,
  type TimeControl,
} from "./contracts";
import { TimePicker } from "./ui";

interface Props {
  user: Player | null;
  friends: Friend[];
  requests: FriendRequest[];
  challenges: Challenge[];
  messages: Record<string, ChatMessage[]>;
  send: (data: any) => boolean;
  notify: (message: string) => void;
  online: boolean;
  busy: boolean;
  onWatch: (friendId: string) => void;
  compact?: boolean;
  initialFriend?: string | null;
}
export function Social(props: Props) {
  const {
    user,
    friends,
    requests,
    challenges,
    messages,
    send,
    notify,
    online,
    busy,
    onWatch,
    compact = false,
    initialFriend,
  } = props;
  const [code, setCode] = useState(""),
    [adding, setAdding] = useState(false),
    [chatId, setChatId] = useState<string | null>(initialFriend || null),
    [text, setText] = useState(""),
    [challengeFriend, setChallengeFriend] = useState<Friend | null>(null),
    [tc, setTc] = useState<TimeControl>("10+0");
  const chatScroll = useRef<HTMLDivElement>(null);
  const chatFriend = friends.find((f) => f.id === chatId),
    thread = chatId ? messages[chatId] || [] : [];
  useEffect(() => {
    if (initialFriend) setChatId(initialFriend);
  }, [initialFriend]);
  useEffect(() => {
    if (chatId && online) send({ type: "chat:history", friendId: chatId });
  }, [chatId, online]);
  useEffect(() => {
    if (chatScroll.current)
      chatScroll.current.scrollTop = chatScroll.current.scrollHeight;
    if (chatId && online && thread.length)
      send({ type: "chat:history", friendId: chatId });
  }, [thread.length]);
  function add(e: React.FormEvent) {
    e.preventDefault();
    if (!online) {
      notify("Reconnect to add a friend.");
      return;
    }
    send({ type: "friend:add", code: code.toUpperCase() });
    setCode("");
    setAdding(false);
  }
  async function copy() {
    try {
      await navigator.clipboard.writeText(user?.code || "");
      notify("Friend code copied.");
    } catch {
      notify(`Your friend code: ${user?.code || "Connecting…"}`);
    }
  }
  return (
    <div className={`social-page ${compact ? "compact-social" : ""}`}>
      {!compact && (
        <>
          <div className="section-eyebrow">GOOD COMPANY. GREAT GAMES.</div>
          <h1>Friends in your realm.</h1>
          <p className="page-description">
            A rematch, a conversation, or a seat at a friend’s board.
          </p>
        </>
      )}
      {challengeFriend ? (
        <div className="challenge-setup panel">
          <button
            className="text-button"
            onClick={() => setChallengeFriend(null)}
          >
            <ArrowLeft size={16} />
            Back to friends
          </button>
          <h2>Challenge {challengeFriend.name}</h2>
          <p>Standard chess · unrated · no assistance</p>
          <TimePicker value={tc} onChange={setTc} allowUntimed />
          <button
            className="primary-button"
            disabled={!online || busy}
            onClick={() => {
              send({
                type: "challenge:send",
                friendId: challengeFriend.id,
                timeControl: tc,
              });
              setChallengeFriend(null);
            }}
          >
            Send challenge <Swords size={18} />
          </button>
        </div>
      ) : (
        <>
          <div className="friend-code panel">
            <div className="friend-code-icon">
              <Shield size={23} />
            </div>
            <div>
              <small>Your friend code</small>
              <strong data-testid="friend-code">
                {user?.code || "Connecting…"}
              </strong>
            </div>
            <button
              className="icon-button"
              onClick={copy}
              aria-label="Copy friend code"
              disabled={!user}
            >
              <Copy size={17} />
            </button>
          </div>
          {requests
            .filter((r) => r.toId === user?.id)
            .map((r) => (
              <div className="request-card" key={r.id}>
                <UserPlus size={20} />
                <div>
                  <strong>{r.name}</strong>
                  <small>wants to be your friend</small>
                </div>
                <button
                  className="icon-button positive"
                  aria-label={`Accept friend request from ${r.name}`}
                  onClick={() =>
                    send({ type: "friend:respond", id: r.id, accept: true })
                  }
                >
                  <Check size={18} />
                </button>
                <button
                  className="icon-button"
                  aria-label={`Decline friend request from ${r.name}`}
                  onClick={() =>
                    send({ type: "friend:respond", id: r.id, accept: false })
                  }
                >
                  <X size={18} />
                </button>
              </div>
            ))}
          {challenges.map((c) => (
            <div className="request-card" key={c.id}>
              <Swords size={20} />
              <div>
                <strong>
                  {c.fromId === user?.id
                    ? `Waiting for ${c.toName}`
                    : `${c.fromName} challenges you`}
                </strong>
                <small>
                  {c.timeControl === "untimed" ? "Untimed" : c.timeControl} ·
                  Friendly game
                </small>
              </div>
              {c.toId === user?.id ? (
                <>
                  <button
                    className="small-primary"
                    disabled={busy}
                    onClick={() =>
                      send({
                        type: "challenge:respond",
                        id: c.id,
                        accept: true,
                      })
                    }
                  >
                    Accept
                  </button>
                  <button
                    className="icon-button"
                    aria-label="Decline challenge"
                    onClick={() =>
                      send({
                        type: "challenge:respond",
                        id: c.id,
                        accept: false,
                      })
                    }
                  >
                    <X size={17} />
                  </button>
                </>
              ) : (
                <button
                  className="icon-button"
                  aria-label="Cancel challenge"
                  onClick={() => send({ type: "challenge:cancel", id: c.id })}
                >
                  <X size={17} />
                </button>
              )}
            </div>
          ))}
          <div className={`social-columns ${chatFriend ? "has-chat" : ""}`}>
            <section className="friend-list panel">
              <header>
                <h2>
                  <Users size={18} />
                  Your friends <span className="count">{friends.length}</span>
                </h2>
                <button
                  className="icon-button"
                  onClick={() => setAdding(!adding)}
                  aria-label="Add a friend"
                >
                  <Plus size={20} />
                </button>
              </header>
              {adding && (
                <form className="add-friend-form" onSubmit={add}>
                  <label
                    htmlFor={
                      compact ? "compact-friend-code" : "add-friend-code"
                    }
                  >
                    Enter a friend code
                  </label>
                  <div>
                    <input
                      id={compact ? "compact-friend-code" : "add-friend-code"}
                      autoFocus
                      maxLength={10}
                      value={code}
                      onChange={(e) => setCode(e.target.value.toUpperCase())}
                      placeholder="e.g. A1B2C3D4E5"
                      autoComplete="off"
                    />
                    <button
                      className="small-primary"
                      disabled={code.trim().length !== 10 || !online}
                    >
                      Add
                    </button>
                  </div>
                </form>
              )}
              {!friends.length ? (
                <div className="friends-empty">
                  <div className="empty-crest">
                    <Users size={30} />
                  </div>
                  <h3>A good game is better together.</h3>
                  <p>
                    Share your code or add a friend to chat, play, and watch
                    their games.
                  </p>
                  <button
                    className="secondary-button"
                    onClick={() => setAdding(true)}
                  >
                    <UserPlus size={17} />
                    Add your first friend
                  </button>
                </div>
              ) : (
                friends.map((friend) => (
                  <article
                    className={`friend-row ${chatId === friend.id ? "active" : ""}`}
                    key={friend.id}
                  >
                    <button
                      className="friend-identity"
                      onClick={() => setChatId(friend.id)}
                    >
                      <span
                        className={`avatar ${friend.online ? "is-online" : ""}`}
                      >
                        {friend.name.slice(0, 1).toUpperCase()}
                      </span>
                      <span>
                        <strong>{friend.name}</strong>
                        <small>
                          {friend.gameId
                            ? "Playing chess"
                            : friend.online
                              ? "Online"
                              : "Offline"}
                          {friend.unread > 0 && (
                            <b className="unread">{friend.unread}</b>
                          )}
                        </small>
                      </span>
                    </button>
                    <div className="friend-actions">
                      <button
                        className="icon-button"
                        aria-label={`Chat with ${friend.name}`}
                        onClick={() => setChatId(friend.id)}
                      >
                        <MessageCircle size={17} />
                      </button>
                      {friend.canWatch ? (
                        <button
                          className="icon-button"
                          aria-label={`Watch ${friend.name}`}
                          disabled={busy}
                          onClick={() => onWatch(friend.id)}
                        >
                          <Eye size={18} />
                        </button>
                      ) : (
                        <button
                          className="icon-button"
                          aria-label={`Challenge ${friend.name}`}
                          disabled={
                            !friend.online || Boolean(friend.gameId) || busy
                          }
                          onClick={() => setChallengeFriend(friend)}
                        >
                          <Swords size={18} />
                        </button>
                      )}
                    </div>
                  </article>
                ))
              )}
              {requests
                .filter((r) => r.fromId === user?.id)
                .map((r) => (
                  <div className="pending-request" key={r.id}>
                    Request sent to <strong>{r.name}</strong>
                  </div>
                ))}
            </section>
            <section
              className={`chat-panel panel ${!chatFriend ? "empty-thread" : ""}`}
              aria-label="Friend chat"
            >
              {chatFriend ? (
                <>
                  <header>
                    <button
                      className="icon-button chat-back"
                      aria-label="Back to friends"
                      onClick={() => setChatId(null)}
                    >
                      <ArrowLeft size={19} />
                    </button>
                    <span
                      className={`avatar small ${chatFriend.online ? "is-online" : ""}`}
                    >
                      {chatFriend.name.slice(0, 1)}
                    </span>
                    <div>
                      <h2>{chatFriend.name}</h2>
                      <small>
                        {chatFriend.online
                          ? "Online"
                          : "Offline · messages are saved"}
                      </small>
                    </div>
                    <button
                      className="icon-button"
                      aria-label={`Challenge ${chatFriend.name}`}
                      disabled={
                        !online ||
                        !chatFriend.online ||
                        Boolean(chatFriend.gameId) ||
                        busy
                      }
                      onClick={() => setChallengeFriend(chatFriend)}
                    >
                      <Swords size={18} />
                    </button>
                  </header>
                  <div
                    className="chat-messages"
                    ref={chatScroll}
                    role="log"
                    aria-label={`Messages with ${chatFriend.name}`}
                    aria-live="polite"
                  >
                    {!thread.length && (
                      <p className="chat-start">
                        Say hello. Your next rivalry starts here.
                      </p>
                    )}
                    {thread.map((m) => (
                      <div
                        key={m.id}
                        className={`chat-bubble ${m.fromId === user?.id ? "mine" : ""}`}
                      >
                        <p>{m.text}</p>
                        <time>
                          {new Date(m.createdAt).toLocaleTimeString([], {
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </time>
                      </div>
                    ))}
                  </div>
                  <form
                    className="chat-compose"
                    onSubmit={(e) => {
                      e.preventDefault();
                      if (text.trim() && online) {
                        send({
                          type: "chat:send",
                          friendId: chatFriend.id,
                          text: text.trim(),
                        });
                        setText("");
                      }
                    }}
                  >
                    <input
                      aria-label={`Message ${chatFriend.name}`}
                      value={text}
                      maxLength={500}
                      onChange={(e) => setText(e.target.value)}
                      placeholder={online ? "Send a message…" : "Reconnecting…"}
                      disabled={!online}
                    />
                    <button
                      className="icon-button send-button"
                      aria-label="Send message"
                      disabled={!text.trim() || !online}
                    >
                      <Send size={18} />
                    </button>
                  </form>
                  <button
                    className="remove-friend text-button"
                    onClick={() => {
                      if (
                        window.confirm(
                          `Remove ${chatFriend.name}? You will no longer be able to chat or watch their games.`,
                        )
                      ) {
                        send({
                          type: "friend:remove",
                          friendId: chatFriend.id,
                        });
                        setChatId(null);
                      }
                    }}
                  >
                    Remove friend
                  </button>
                </>
              ) : (
                <div>
                  <MessageCircle size={32} />
                  <h3>Stay for a conversation.</h3>
                  <p>Select a friend to open your chat.</p>
                </div>
              )}
            </section>
          </div>
        </>
      )}
    </div>
  );
}

import { LegionPicker } from "./LegionPicker";
import React, { useState } from "react";
import {
  Copy,
  Share2,
  Link,
  ArrowRight,
  Globe,
  LoaderCircle,
  Check,
} from "lucide-react";
import { Dialog, TimePicker, SETS } from "./ui";
import {
  inviteURL,
  inviteCodeFrom,
  gameWebsite,
  isNativeApp,
  normalizeWebsite,
  saveWebsite,
} from "./mobile";
import type { InviteInfo, PieceSet, TimeControl } from "./contracts";
async function copyLink(text: string) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const input = document.createElement("textarea");
    input.value = text;
    input.style.position = "fixed";
    input.style.opacity = "0";
    document.body.append(input);
    input.select();
    const copied = document.execCommand("copy");
    input.remove();
    return copied;
  }
}
export function FriendInvite({
  own,
  preview,
  code,
  online,
  offlineOnly,
  busy,
  faction,
  legionConfirmed,
  onFactionChange,
  error,
  onClose,
  onCreate,
  onCancel,
  onJoin,
  onPreview,
  onSettings,
  notify,
}: {
  own: InviteInfo | null;
  preview: InviteInfo | null;
  code: string | null;
  online: boolean;
  offlineOnly: boolean;
  busy: boolean;
  faction: PieceSet;
  legionConfirmed: boolean;
  onFactionChange: (army: PieceSet) => void;
  error: string;
  onClose: () => void;
  onCreate: (tc: TimeControl, color: "w" | "b" | "random") => void;
  onCancel: (code: string) => void;
  onJoin: (code: string) => void;
  onPreview: (code: string) => void;
  onSettings: () => void;
  notify: (s: string) => void;
}) {
  const [tc, setTc] = useState<TimeControl>("10+0"),
    [side, setSide] = useState<"w" | "b" | "random">("w"),
    [input, setInput] = useState(""),
    [localError, setError] = useState(""),
    [copied, setCopied] = useState(false);
  const active = own?.status === "waiting" ? own : null,
    guest = Boolean(code && !preview?.isHost),
    url = active ? inviteURL(active.code) : "",
    label = TIME_CONTROLS_LABEL(
      preview?.timeControl || active?.timeControl || tc,
    );
  function openLink() {
    try {
      const parsed = inviteCodeFrom(input);
      if (!parsed)
        throw Error(
          "Paste the full friend link or its 32-character invite code.",
        );
      if (isNativeApp() && input.includes("://")) {
        const origin = normalizeWebsite(input);
        if (origin !== gameWebsite()) {
          if (busy)
            throw Error("Finish your match before connecting another website.");
          localStorage.setItem("sg-pending-invite", JSON.stringify(parsed));
          saveWebsite(origin);
          location.reload();
          return;
        }
      }
      onPreview(parsed);
      setError("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Check the friend link.");
    }
  }
  return (
    <Dialog
      title={guest ? "Join your friend." : "Play with a friend."}
      onClose={onClose}
    >
      <div className="dialog-content invite-content">
        {!active && (
          <LegionPicker
            value={faction}
            confirmed={legionConfirmed}
            disabled={busy}
            onChange={onFactionChange}
          />
        )}
        {guest ? (
          <>
            {!preview && !error ? (
              <p className="invite-wait">
                <LoaderCircle className="spin" size={18} />
                Opening invite…
              </p>
            ) : preview?.status === "waiting" ? (
              <>
                <div className="invite-host">
                  <Link size={24} />
                  <div>
                    <strong>{preview.hostName} invited you</strong>
                    <span>{label} · Unrated · Standard chess</span>
                  </div>
                </div>
                <p>
                  Your friend plays{" "}
                  {preview.hostColor === "random"
                    ? "a random side"
                    : preview.hostColor === "w"
                      ? "White"
                      : "Black"}
                  . Your faction is {SETS.find((s) => s.id === faction)?.name}.
                </p>
                {!preview.hostOnline && (
                  <p className="invite-notice">
                    Waiting for your friend to reopen the game. This screen
                    updates automatically.
                  </p>
                )}
                <button
                  className="primary-button"
                  disabled={
                    !online || busy || !preview.hostOnline || !legionConfirmed
                  }
                  onClick={() => onJoin(preview.code)}
                >
                  Join match <ArrowRight size={17} />
                </button>
              </>
            ) : (
              <p className="invite-notice">
                This invite has{" "}
                {preview?.status === "joined"
                  ? "already been used"
                  : preview?.status === "cancelled"
                    ? "been cancelled"
                    : "expired"}
                . Ask your friend for a new link.
              </p>
            )}
          </>
        ) : active ? (
          <>
            <div className="invite-host">
              <Link size={25} />
              <div>
                <strong>Your private match is ready</strong>
                <span>
                  {label} · You play{" "}
                  {active.hostColor === "random"
                    ? "a random side"
                    : active.hostColor === "w"
                      ? "White"
                      : "Black"}
                </span>
              </div>
            </div>
            <p>
              Send this link to one friend. Keep the game open while they join.
              Your clocks wait until both players are ready.
            </p>
            <label className="select-field">
              <strong>Friend invite link</strong>
              <input
                readOnly
                value={url}
                onFocus={(e) => e.currentTarget.select()}
              />
            </label>
            <div className="invite-actions">
              <button
                className="secondary-button"
                onClick={() =>
                  void copyLink(url).then((ok) => {
                    setCopied(ok);
                    notify(
                      ok
                        ? "Invite link copied."
                        : "Select the link above to copy it.",
                    );
                  })
                }
              >
                {copied ? <Check size={17} /> : <Copy size={17} />}Copy link
              </button>
              <button
                className="primary-button"
                onClick={async () => {
                  try {
                    if (isNativeApp()) {
                      const { Share } = await import("@capacitor/share");
                      await Share.share({
                        title: "Play Sovereign’s Gambit",
                        text: "Join my private chess match.",
                        url,
                      });
                    } else if (navigator.share)
                      await navigator.share({
                        title: "Play Sovereign’s Gambit",
                        text: "Join my private chess match.",
                        url,
                      });
                    else {
                      const ok = await copyLink(url);
                      notify(
                        ok
                          ? "Invite link copied."
                          : "Select the link above to copy it.",
                      );
                    }
                  } catch (e) {
                    if ((e as any)?.name !== "AbortError")
                      notify("Use Copy link to send the invitation.");
                  }
                }}
              >
                <Share2 size={17} />
                Share invite
              </button>
            </div>
            {url &&
              ["localhost", "127.0.0.1"].includes(new URL(url).hostname) && (
                <small className="invite-notice">
                  This is a local preview address. A public game website is
                  needed to share across devices.
                </small>
              )}
            <button
              className="text-button"
              onClick={() => onCancel(active.code)}
            >
              Cancel link / change setup
            </button>
            <small>Private link · One guest · Valid for one hour</small>
          </>
        ) : (
          <>
            <p>
              Create a private, unrated match. Your friend opens the link in a
              browser—no friend code or app download needed.
            </p>
            {offlineOnly ? (
              <div className="invite-notice">
                <strong>Connect a game website</strong>
                <p>
                  Offline computer play is ready. To create online friend links,
                  add the hosted game address.
                </p>
                <button className="secondary-button" onClick={onSettings}>
                  <Globe size={16} />
                  Game website settings
                </button>
              </div>
            ) : (
              <>
                <span className="field-label">Time control</span>
                <TimePicker value={tc} onChange={setTc} allowUntimed />
                <label className="select-field">
                  <strong>Your side</strong>
                  <select
                    aria-label="Your side"
                    value={side}
                    onChange={(e) => setSide(e.target.value as typeof side)}
                  >
                    <option value="w">White · my home castle</option>
                    <option value="b">Black · my friend’s home castle</option>
                    <option value="random">Random</option>
                  </select>
                </label>
                <button
                  className="primary-button"
                  disabled={!online || busy || !legionConfirmed}
                  onClick={() => onCreate(tc, side)}
                >
                  <Link size={17} />
                  Create invite link
                </button>
              </>
            )}
          </>
        )}
        {(error || localError) && (
          <p className="invite-error" role="alert">
            {localError || error}
          </p>
        )}
        {!guest && (
          <div className="invite-paste">
            <label className="select-field">
              <strong>Already have a friend link?</strong>
              <input
                type="text"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                placeholder="Paste your friend’s invite link"
                autoCapitalize="none"
                autoCorrect="off"
              />
            </label>
            <button
              className="secondary-button"
              disabled={!input.trim() || busy}
              onClick={openLink}
            >
              Open friend link <ArrowRight size={16} />
            </button>
          </div>
        )}
      </div>
    </Dialog>
  );
}
function TIME_CONTROLS_LABEL(tc: string) {
  return tc === "untimed" ? "Untimed" : tc.replace("+", " + ");
}

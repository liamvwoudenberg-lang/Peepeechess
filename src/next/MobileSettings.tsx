import React, { useState } from "react";
import { Download, Globe, Check } from "lucide-react";
import {
  gameWebsite,
  isNativeApp,
  saveWebsite,
  getInstallPrompt,
  installWebApp,
} from "./mobile";
export function MobileSettings({
  busy,
  notify,
}: {
  busy: boolean;
  notify: (s: string) => void;
}) {
  const [website, setWebsite] = useState(gameWebsite()),
    [error, setError] = useState(""),
    [saved, setSaved] = useState(false);
  if (isNativeApp())
    return (
      <section className="mobile-settings">
        <h3>Online game website</h3>
        <p>
          Computer games work offline. Connect the hosted game website to play
          online and use friend links.
        </p>
        <label className="select-field">
          <strong>Game website address</strong>
          <input
            type="url"
            value={website}
            onChange={(e) => {
              setWebsite(e.target.value);
              setSaved(false);
            }}
            placeholder="https://your-game.vercel.app"
            disabled={busy}
          />
        </label>
        {error && <p role="alert">{error}</p>}
        <button
          className="secondary-button"
          disabled={busy}
          onClick={() => {
            try {
              saveWebsite(website);
              setError("");
              setSaved(true);
              notify("Connecting to the game website.");
            } catch (e) {
              setError(
                e instanceof Error ? e.message : "Check that website address.",
              );
            }
          }}
        >
          {saved ? <Check size={16} /> : <Globe size={16} />}Connect website
        </button>
        {busy && <small>Finish this match before changing websites.</small>}
      </section>
    );
  return (
    <details className="mobile-settings">
      <summary>
        <Download size={16} />
        Install on your phone
      </summary>
      <p>
        Install this game for a full-screen board and offline computer play.
      </p>
      {getInstallPrompt() ? (
        <button
          className="secondary-button"
          onClick={() => void installWebApp()}
        >
          Install game <Download size={16} />
        </button>
      ) : (
        <p>
          iPhone: Safari → Share → Add to Home Screen.
          <br />
          Android: Chrome menu → Install app or Add to Home screen.
        </p>
      )}
    </details>
  );
}

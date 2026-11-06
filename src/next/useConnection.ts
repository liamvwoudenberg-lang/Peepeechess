import { useCallback, useEffect, useRef, useState } from "react";
import { gameWebsite, isNativeApp } from "./mobile";
import { PeerTransport } from "./PeerTransport";
export function useConnection(onMessage: (data: any) => void) {
  const handler = useRef(onMessage);
  handler.current = onMessage;
  const transport = useRef<PeerTransport | null>(null),
    offset = useRef(0);
  const [status, setStatus] = useState<"connecting" | "online" | "offline">(
      "connecting",
    ),
    [network, setNetwork] = useState<"connecting" | "direct" | "server">(
      "server",
    ),
    [error, setError] = useState(""),
    [authError, setAuthError] = useState(false);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const changed = () => setRevision((v) => v + 1);
    window.addEventListener("sg-website-changed", changed);
    return () => window.removeEventListener("sg-website-changed", changed);
  }, []);
  useEffect(() => {
    setAuthError(false);
    setError("");
    setStatus("connecting");
    const t = new PeerTransport(
      (d) => {
        if (d.type === "auth:error") setAuthError(true);
        handler.current(d);
      },
      (state, message) => {
        setStatus(state);
        setError(message || "");
      },
      setNetwork,
      (value) => (offset.current = value),
    );
    transport.current = t;
    t.start();
    return () => t.stop();
  }, [revision]);
  const send = useCallback(
    (data: any) => transport.current?.send(data) || false,
    [],
  );
  return {
    status,
    network,
    error,
    send,
    authError,
    offset,
    offlineOnly: isNativeApp() && !gameWebsite(),
  };
}

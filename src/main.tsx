import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { captureInstallPrompt, isNativeApp } from "./next/mobile";

captureInstallPrompt();
if (import.meta.env.PROD && !isNativeApp() && "serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    void navigator.serviceWorker.register("/sw.js").catch(() => {});
  });
}

createRoot(document.getElementById("root")!).render(<App />);

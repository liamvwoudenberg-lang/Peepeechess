export const DEFAULT_GAME_WEBSITE = "https://cheesy-indol.vercel.app";
export function isNativeApp() {
  return (
    typeof window !== "undefined" &&
    Boolean((window as any).Capacitor?.isNativePlatform?.())
  );
}
export function gameWebsite() {
  if (typeof location === "undefined") return "";
  if (!isNativeApp()) return location.origin;
  try {
    return (
      localStorage.getItem("sg-game-website") ||
      import.meta.env?.VITE_PUBLIC_GAME_URL ||
      DEFAULT_GAME_WEBSITE
    );
  } catch {
    return import.meta.env?.VITE_PUBLIC_GAME_URL || DEFAULT_GAME_WEBSITE;
  }
}
export function normalizeWebsite(value: string) {
  const u = new URL(value.trim());
  if (
    u.protocol !== "https:" &&
    !(["localhost", "127.0.0.1"].includes(u.hostname) && u.protocol === "http:")
  )
    throw Error("Use the secure https:// address of the game website.");
  if (u.username || u.password)
    throw Error("Use a game website address without a username or password.");
  return u.origin;
}
export function saveWebsite(value: string) {
  const origin = normalizeWebsite(value);
  localStorage.setItem("sg-game-website", origin);
  window.dispatchEvent(new Event("sg-website-changed"));
  return origin;
}
export function inviteCodeFrom(value: string) {
  const trimmed = value.trim();
  if (/^[a-f0-9]{32}$/.test(trimmed)) return trimmed;
  try {
    const code = new URL(trimmed).searchParams.get("play");
    return code && /^[a-f0-9]{32}$/.test(code) ? code : null;
  } catch {
    return null;
  }
}
export function inviteURL(code: string) {
  const origin = gameWebsite();
  if (!origin) return "";
  const u = new URL("/", origin);
  u.searchParams.set("play", code);
  return u.href;
}
export function inviteSessionKey() {
  return isNativeApp()
    ? "sg-peer-session-v3@" + gameWebsite()
    : "sg-peer-session-v3";
}
let installPrompt: any = null;
export function captureInstallPrompt() {
  window.addEventListener("beforeinstallprompt", (event: any) => {
    event.preventDefault();
    installPrompt = event;
    window.dispatchEvent(new Event("sg-install-ready"));
  });
}
export function getInstallPrompt() {
  return installPrompt;
}
export async function installWebApp() {
  if (installPrompt) {
    const event = installPrompt;
    installPrompt = null;
    await event.prompt();
    return event.userChoice;
  }
}

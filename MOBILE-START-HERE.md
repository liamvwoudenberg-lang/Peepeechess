# Play on your phone

## Android APK — play immediately

Install `sovereigns-gambit-android.apk` on an Android phone. Android may ask you to allow installation from the app you used to download the file. This is a signed **debug APK for sideloading**, not a Play Store release. It supports Android 6.0+ with a current Android System WebView/Chrome. The full game and computer opponent are bundled: no website or internet connection is needed for computer games, lessons, puzzles, or analysis.

The game opens in 3D on capable phones. Choose a legion before starting. The 2D board uses original ink drawings that share the 3D characters’ livery and role silhouettes. It supports touch moves and stays readable from either side. You can switch views any time. Keep Performance mode on Auto or Light for older phones.

## Online play uses the included website address

The APK is preconfigured for **https://cheesy-indol.vercel.app/**. It keeps the game bundled for offline play; it uses that website’s API for online profiles, friend links and matchmaking. You can change the website in settings. Your browser and APK have separate player profiles.

The website’s multiplayer API needs a working Vercel deployment with Upstash Redis. See [DEPLOY-VERCEL.md](DEPLOY-VERCEL.md). A functioning website alone does not guarantee the API/storage are configured. At the start of this update the endpoint returned HTTP 500; this update fixes native ESM server imports and includes a regression check against emitted JavaScript.

To play online once the server is ready:

1. Open the APK. The default game website is already entered. Choose your legion. To use a different host, change **More → Appearance and preferences → Online game website** or paste a full friend link.
2. Choose **Friend → Share a friend link**, select your legion, time control and side, then choose **Create invite link**.
3. Tap **Share invite** or **Copy link** and send it to your friend yourself. Keep the game open while your friend joins.
4. Your friend opens the link, chooses their own legion, and taps **Join match**. They can use the browser without installing anything. To join in the APK, paste the link into **Already have a friend link?**

Links admit one guest and expire after an hour. Games are unrated. The selected White faction sets the home castle for both players; clocks start after both clients are ready. Profiles are local to each browser/app and game website. The app keeps each website’s profile credential separate. Links alone do not add a permanent friendship; use friend codes for persistent chat and spectating.

## Simple menus and the match view

Pick a mode and legion, then Play. Expand **Match settings** to change the time control, computer Elo, side or move feedback. Their selected values are shown while the section is closed.

During a match the board fills the available screen. Open the top-right **Moves and game options** button for history, chat, pause, resignation, draws and training tools. **Menu** returns to the main app. **More** contains puzzles, the armory, analysis, imports, profile and preferences. No game features were removed.

## iPhone and Android browsers

Open the deployed HTTPS website. In iPhone Safari, use **Share → Add to Home Screen**. In Android Chrome, use **Install app** or **Add to Home screen**. The game also has installation instructions in Appearance and preferences.

After the first complete load, the installed web app caches its interface, pieces and computer worker for offline play. Online matches, friends and chat require an internet connection. Browser storage can be cleared or evicted by the phone; the APK is the most direct way to keep the game bundled offline. Website updates wait for existing tabs to close so a new build does not replace an active game.

## Build a new APK

Use Node 24, JDK 21, and Android SDK platform/build-tools 35. Android Studio can install the SDK. Set `ANDROID_HOME` and `JAVA_HOME` for your machine, or create your own `android/local.properties` with `sdk.dir=/your/android/sdk`.

```sh
npm ci
npm run android:apk
```

The result is `android/app/build/outputs/apk/debug/app-debug.apk`. `npm run android:sync` builds the web app and copies it into the native project. Open `android/` in Android Studio for a device run or a release build. For Play Store distribution, configure your own release signing key and build an AAB; no release signing key is included.

To preconfigure the hosted website in future APKs, set `VITE_PUBLIC_GAME_URL=https://your-game.vercel.app` before `npm run android:apk`. Otherwise the player can connect the website in settings. Do not put database tokens or TURN shared secrets in `VITE_` variables.

## Verification limits

The APK was assembled and its Android package/signature checked. Touch layouts, offline computer play, invitation joins, and reconnect were checked in Chromium with phone viewports; the native-platform branch was also simulated there. This is not a physical Android/iPhone device test. A real cross-network mobile WebRTC test still requires healthy live storage and real devices. Authenticated HTTP fallback remains available when PeerJS cannot connect directly.

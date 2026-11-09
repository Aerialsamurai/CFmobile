# CF Phone

A C++ editor + Codeforces companion for iPhone. Compiles on-device (Clang in WebAssembly), no server, no paid account.

## What's in step 1–3 (all included in this first build)
- **Code tab** – CodeMirror editor, VS Code *Dark Modern* theme (+ Dark+, Light Modern, One Dark, Dracula, Monokai, GitHub Dark), symbol key row above the keyboard, red line marks + a short plain-English error bar.
- **Tests tab** – sample tests, custom tests, run one / run all, AC / WA / TLE / RE per test, **Submit**.
- **Submissions tab** – your Codeforces submissions with live verdicts.
- **Contests tab** – live + upcoming contests, **Register**, reminders (24 h and 15 min before), live-contest problem list.
- **Settings** – handle + login, theme, font size, C++ standard, runtime checks, **template** (import a `.cpp`/`.txt`, edit in app, or edit `template.cpp` in the Files app).

## Build it without a Mac
1. Create a GitHub repository (public is simplest) and put **all of this folder's contents** in it (keep `.github/`).
   Using the website: *Add file → Upload files*, drag everything in, commit to `main`.
2. Open the repo's **Actions** tab → *Build iOS app (unsigned IPA)*. It runs automatically on push (or press *Run workflow*). It takes ~5–10 min.
3. When it's green, open the run and download the artifact **CFPhone-ipa** (a zip containing `CFPhone.ipa`). If it's red, download the **build-log** artifact and send it to Claude.

## Install on your iPhone from Windows (free)
1. Install **iTunes** and **iCloud** from apple.com (not the Microsoft Store versions), then **AltServer** from https://altstore.io.
2. Plug in the iPhone, trust the PC, start AltServer (tray icon) → *Install AltStore* → your iPhone, using your Apple ID.
3. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID. Settings → Privacy & Security → turn on **Developer Mode** (restarts the phone).
4. Send `CFPhone.ipa` to the phone (AirDrop is not available from Windows; use iCloud Drive, or the Files app via email/Drive), open AltStore → *My Apps* → **+** → pick the IPA.
5. Keep AltServer running on the PC on the same Wi-Fi: AltStore refreshes the 7-day signing in the background.

(Sideloadly is an alternative: https://sideloadly.io — drag the IPA onto it with the phone plugged in.)

## Known limits
- C++ exceptions (`try`/`catch`/`throw`) aren't supported by the on-device compiler.
- First compile after launch takes several seconds (loads a ~100 MB compiler).
- Runtime checks (overflow, out-of-bounds) are optional in Settings; programs run slower than on Codeforces.
- Submitting/registering drive the real Codeforces website inside the app. If Codeforces changes its page layout, the auto-fill may need an update; the page stays visible so you can finish by hand.

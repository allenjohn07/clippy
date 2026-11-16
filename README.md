# Clippy

A tiny clipboard history for macOS. Press **⌘⇧V** in any text field to pick something you copied earlier.

- **⌘V** still pastes normally. Clippy never gets in the way.
- **⌘⇧V** opens a small popup just below the input box you're typing in (or above it, if the box is at the bottom of the screen).
- History is saved locally in SQLite and survives restarts. Nothing ever leaves your Mac.
- No Dock icon, no windows. Just a small menu bar icon.

[![CI](https://github.com/allenjohn07/clippy/actions/workflows/ci.yml/badge.svg)](https://github.com/allenjohn07/clippy/actions/workflows/ci.yml)

## Using it

| Key / action | What it does |
|---|---|
| **⌘⇧V** | Open the popup (only where you can paste) |
| **V**, **↓**, **↑** | Move the selection |
| **1–9** or **click** an item | Paste that item |
| **Return** | Paste the highlighted item |
| **Esc**, any other key, or click elsewhere | Close the popup |
| **⌫** or click **Clear history** (twice to confirm) | Delete all history |

The menu bar icon has **Launch at Login**, **Clear History…**, and **Quit**.

## Install

### Download (easiest)

1. Grab `Clippy.zip` from the [latest release](https://github.com/allenjohn07/clippy/releases/latest) and unzip it.
2. Move `Clippy.app` to your **Applications** folder.
3. Open it. See the note below about the security warning.
4. When asked, allow Clippy in **System Settings → Privacy & Security → Accessibility**. It needs this to see ⌘⇧V and paste for you.

> [!NOTE]
> **macOS will warn that Clippy "cannot be opened because Apple cannot check it for malicious software."**
>
> That's expected. To get rid of that warning, an app has to be signed and notarized with an Apple Developer certificate, which costs $99/year. This is a small free side project and I don't want to pay that, so the app isn't notarized. The code is all here if you want to check it, or you can build it yourself (below).
>
> To open it anyway: **right-click `Clippy.app` → Open → Open**. Or go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only have to do this once.

### Build from source

Needs macOS 13+ and Xcode (or the Xcode Command Line Tools).

```bash
git clone https://github.com/allenjohn07/clippy.git
cd clippy
./scripts/install.sh
```

This builds `Clippy.app`, copies it to `~/Applications`, and starts it. Apps you build yourself don't get the security warning.

On first launch Clippy adds itself to **Login Items**, so it starts automatically. Turn that off from the menu bar icon or in **System Settings → General → Login Items**.

### Uninstall

```bash
./scripts/uninstall.sh           # remove the app
./scripts/uninstall.sh --purge   # …and delete your clipboard history
```

Then remove Clippy from **System Settings → Privacy & Security → Accessibility**.

## Privacy

- History lives in `~/Library/Application Support/clippy/history.db`. The file is readable only by your user account.
- Only the newest **1,000** items are kept. Older ones are deleted automatically.
- Copies from password managers that mark content as concealed (1Password, Bitwarden, etc.) are **not** recorded.
- No network access. Nothing is sent anywhere.

## Battery & performance

Clippy is idle almost all the time. It checks whether the clipboard changed twice a second, and macOS groups those checks with other work to save power. It only does real work when you copy something or press ⌘⇧V. In Activity Monitor's Energy tab it should sit at around zero.

## Known limitations

- **Secure input:** while a password field is focused, or when Terminal/iTerm's "Secure Keyboard Entry" is on, macOS blocks all keyboard monitoring, so ⌘⇧V can't work there.
- **Finder** counts as "somewhere you can paste" (it pastes files), so the popup opens there, but pasting text does nothing.
- **Rebuilding** changes the app's signature, so macOS may ask you to re-allow Accessibility after an update. If that happens, remove Clippy from the Accessibility list and add it again.
- Text only. Images and files aren't recorded yet.

## Development

```bash
swift build          # build
swift run            # run from the terminal (grant Accessibility to your terminal app)
swift test           # run the tests
./scripts/build-app.sh --zip   # build build/Clippy.app and build/Clippy.zip
```

> If `swift test` fails with *"plugin for module 'TestingMacros' not found"*, your Command Line Tools are missing the test plugin. Run it with Xcode's toolchain instead:
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

| File | What it does |
|---|---|
| `main.swift` | Startup |
| `Controller.swift` | Key/mouse handling |
| `EventTap.swift` | System-wide keyboard & mouse listener |
| `FocusInspector.swift` | Finds the focused input and caret (Accessibility API) |
| `PopupPanel.swift` / `PopupLayout.swift` | The popup and where it goes on screen |
| `ClipboardStore.swift` | Watches the clipboard |
| `HistoryDatabase.swift` | SQLite storage |
| `StatusMenu.swift` / `LoginItem.swift` | Menu bar icon and launch at login |
| `Config.swift` | Settings and key codes |

### End-to-end tests

`./scripts/e2e.sh` drives a real Clippy with real keystrokes and mouse clicks. It opens test windows and a Chromium + Chrome window (via Playwright), and checks popup placement, pasting, Esc, clicks, clearing, and that history survives a restart.

```bash
cd Tests/E2E/browser && npm install && npx playwright install chromium && cd -   # once
./scripts/e2e.sh
```

- It **takes over your keyboard and mouse for about a minute.** Don't touch anything while it runs.
- Your clipboard is saved and restored, a running Clippy is paused and restarted, and a throwaway database is used.
- Your terminal app needs Accessibility permission.
- It stops by itself if a test window isn't in front, so stray keystrokes never land in other apps.
- It doesn't run in CI, because GitHub's Mac runners can't grant Accessibility permission.

Still worth a quick manual check before a release: VS Code / Slack (Electron), Terminal, Notes, and Safari.

### Releasing

Push a version tag. GitHub Actions runs the tests, builds a universal (Apple Silicon + Intel) app, and publishes the release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## License

[MIT](LICENSE)

# LapLock

**Did I lock my MacBook?** — answered from your phone in under a second.

You step away from your desk. You're in a meeting, at lunch, or halfway across the building. Then it hits you — *did I lock my laptop?* You can't remember. The anxiety builds.

LapLock fixes this. It silently watches for macOS lock/unlock events and pushes the status to [ntfy.sh](https://ntfy.sh). Open the status page on your phone and see — right now — whether your MacBook is locked or not.

---

## How It Works

```
┌──────────────┐       POST        ┌──────────┐       SSE        ┌──────────────┐
│   MacBook    │ ──────────────▶   │  ntfy.sh │ ──────────────▶  │  Your Phone  │
│  (daemon)    │  lock/unlock      │ (public) │   live updates   │  (browser)   │
└──────────────┘                   └──────────┘                  └──────────────┘
```

1. A lightweight Swift daemon listens for native macOS lock/unlock notifications
2. On each event, it sends the status to a private [ntfy.sh](https://ntfy.sh) topic
3. A static HTML page on your phone fetches the latest status and stays updated via Server-Sent Events

No accounts. No servers to run. No app to install on your phone — just a web page.

---

## Prerequisites

- macOS (tested on Ventura and later)
- Xcode Command Line Tools (`xcode-select --install`)

---

## Install

```bash
git clone https://github.com/Anush01/laplock.git
cd laplock
./install.sh
```

The installer will:
- Compile the Swift daemon
- Generate a random ntfy topic (or let you choose one)
- Install a LaunchAgent that starts automatically on login
- Print your topic — save this for the status page

That's it. Lock your Mac to test it.

---

## Check Status From Your Phone

**Option A** — Use the hosted page:

1. Open **https://anush01.github.io/laplock** on your phone
2. Enter the ntfy topic from the install step
3. Bookmark it for quick access

**Option B** — Open `index.html` locally or host it anywhere you like.

The page connects to ntfy.sh via SSE for live updates. When you revisit the page, it fetches the latest status instantly.

---

## Uninstall

```bash
./uninstall.sh
```

Removes the daemon, LaunchAgent, logs, and config. Clean slate.

---

## Privacy

Your lock status is sent to a **private ntfy.sh topic** — a random UUID that acts as a secret URL. Nobody can see your status unless they know your topic string. Don't share it publicly.

If you want full control, you can [self-host ntfy](https://docs.ntfy.sh/install/) and point the daemon at your own server.

---

## Logs

```bash
tail -f ~/Library/Logs/macbook-notify/stderr.log
```

---

## How It's Built

| Component | What | Where |
|-----------|------|-------|
| **Daemon** | Swift, listens to `com.apple.screenIsLocked` / `screenIsUnlocked` | `Sources/MacBookNotify.swift` |
| **Agent** | launchd plist, auto-starts on login, restarts on crash | `com.macbook-notify.agent.plist` |
| **Status page** | Single HTML file, inline CSS/JS, SSE + polling fallback | `index.html` |

Zero dependencies. No npm. No Python. No Docker. Just Swift and a browser.

---

## License

MIT

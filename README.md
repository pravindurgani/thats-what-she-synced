<h1 align="center">That's What She Synced</h1>

<p align="center"><strong>Your MacBook's notch, in sync with your music.</strong></p>

| Genesis · Vivid | Pink Floyd · Vivid | Pink Floyd · Duotone |
|:---:|:---:|:---:|
| <img src="docs/thats-what-she-synced/vivid-genesis.jpg" alt="The island in the warm colours of Genesis' album"> | <img src="docs/thats-what-she-synced/vivid-pinkfloyd.jpg" alt="The island in the prism colours of The Dark Side of the Moon"> | <img src="docs/thats-what-she-synced/duotone-look.jpg" alt="Duotone: one orange accent on a calm neutral"> |

> **Unofficial** fork of [Vorssaint](https://github.com/vorssaint/vorssaint-utils), not affiliated with it. Source only; the official app is at [vorssaint.com](https://vorssaint.com).

## What it does

- 🎨 **Album-art colours** on the island, its buttons and its text
- 🥁 **Moves with the music:** the beat, your volume, the genre and the cover's mood
- 🌙 **Glows when closed,** too
- 🤖 **Your companion dances** to the beat
- 🎧 **Headphones connect** with an animated card

Works with Apple Music, Spotify, and music in Safari, Chrome or Firefox.

## Install

You need an Apple silicon Mac on macOS 14.4 or later, plus Apple's Command Line Tools (`xcode-select --install`).

1. **Build it:**
   ```bash
   git clone https://github.com/pravindurgani/thats-what-she-synced.git
   cd thats-what-she-synced
   VORSSAINT_DEV_OPTIMIZE=1 ./build.sh --dev --install
   ```
2. **Let it hear the beat:** System Settings → Privacy & Security → Screen & System Audio Recording → under *System Audio Recording Only*, turn on **Vorssaint (Developer)**.
3. **Switch on**, in the app's Settings: **Dynamic Island**, **Bars follow the music** and **Accessory alerts**.
4. **Play a song** and hover over the notch.

Also running the official Vorssaint? Quit it, so you don't get two islands.

## Options

**Duotone:** one accent colour from the cover, plus a neutral.
```bash
defaults write com.vorssaint.utils.dev notchSongLook -string duotone
```

**Song mode off:**
```bash
defaults write com.vorssaint.utils.dev notchSongModeEnabled -bool false
```

Reopen the app after either change. To undo, use `vivid` or `true`.

## Not working?

- **No beat?** Check step 2, then reopen the app.
- **No colours?** Black-and-white covers stay neutral; try a colourful album.
- **Firefox?** Turn on *Find covers for Firefox and Zen* in the app's music settings.

## Update

```bash
git pull && VORSSAINT_DEV_OPTIMIZE=1 ./build.sh --dev --install
```

## Credits

Built on **[Vorssaint](https://github.com/vorssaint/vorssaint-utils)** by [@vorssaint](https://github.com/vorssaint). ⭐ the original. It's inspired by [Atoll](https://github.com/Ebullioscopic/Atoll) and [boring.notch](https://github.com/TheBoredTeam/boring.notch), with no code taken from either. The name is a nod to Michael Scott, and it was made with [Claude Code](https://claude.com/claude-code). Licensed [GPL-3.0-or-later](LICENSE), like Vorssaint, whose name and look belong to the Vorssaint project ([TRADEMARKS.md](TRADEMARKS.md)).

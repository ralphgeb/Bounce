# Bounce

A minimal block breaker for iPhone, in the same style as Halo and Scout: the same looks, type and quiet interface.

- **The game**: move the paddle with your finger, keep the ball up, and break the wall of squares that keeps drifting down. New rows keep coming, so a game lasts as long as you do; the ball, the wall and the tougher squares all speed up over time.
- **Squares**: plain squares in nine columns, with the same gap across and down. Pale squares take one hit, mid-tone two, solid three.
- **The twist**
  - **Chains**: every block you break before the ball comes back to the paddle raises the multiplier (×2, ×3, up to ×9).
  - **Accent squares** (about one in 30) split the ball in three.
  - **Twenty in a row** without the paddle earns an extra life (at most 5; +50 points when you're full).
- **Lives**: three to start. You lose one when your last ball falls, or when the wall reaches the line above your paddle (that also knocks the bottom three rows away).
- **Landing page**: six squares over B O U N C E (the accent over the O), the three rules, and Start. After a game it shows your score, time and best, and Again.
- **Settings** (the half circle at the top right): seven looks (Graphite, Ocean, Sky, Blush, Forest, Dusk, Mono), each with its own app icon; Automatic, Light or Dark; haptics; your best score and longest game.
- **App icon**: one ball in the centre of the look's background, lit from the top left, with its shadow underneath. `BounceApp/tools/make_icon.py` draws them.

SwiftUI, iOS 17+, no third-party libraries, nothing collected.

## Project layout

```
BounceApp/
  project.yml        XcodeGen project
  Sources/
    BounceApp.swift    entry point; the landing page and the game share one screen
    Game.swift         the board, physics, lives, chains and the display link
    GameView.swift     the canvas, the score, lives and pause
    HomeView.swift     the landing page
    SettingsView.swift looks, appearance, haptics, records
    Theme.swift        looks, colours, saved settings, haptics
  tools/make_icon.py draws the app icons
```

## Build

On a Mac with Xcode 16 or later:

```
brew install xcodegen
cd BounceApp
xcodegen generate
open Bounce.xcodeproj
```

GitHub Actions runs `Bounce – build check` on every push (simulator build, no signing) and `Bounce – upload to TestFlight` on every push to main that changes the app (or by hand). The upload needs the same four secrets as your other apps, added to this repository: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `APPLE_TEAM_ID`, and the app `com.ralphgeb.bounce` created in App Store Connect.

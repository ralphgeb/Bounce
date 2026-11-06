# Bounce

Minimal games for iPhone, in the same style as Halo and Scout: the same looks, type and quiet interface.
The app opens on a menu of three games, one section each, split by thin lines:

- **Bounce**: a block breaker with an endless wall.
- **Maze**: find your way through a huge maze in pitch black, by the light you give off.
- **Switch**: a match-three of shades, with the same special shapes as Bounce.

On the menu and every landing page, drag anywhere and the logos' squares stretch after your finger and spring back.

## Maze

- Everything is pitch black. You are the accent square, and light comes out of you all around (about 5 tiles, gently breathing). Walls catch the light, brighter the closer they are, and throw shadows behind them; that is all you see. The view is zoomed in, about seven tiles across.
- **Swipe** up, down, left or right to slide until a wall, a turning or the way out. Swipe again while sliding and that move waits for the next stop.
- **Dots**: tap to drop a small dot where you stand (30 a level); tap on it again to pick it up. Your light shows them when you come back, so you know you've been there.
- **The way out** is an accent circle with its own glow, the farthest spot from where you start.
- **Levels**: level 1 is 10 × 14 rooms; each level adds 3 across and 4 down, with a few loops. Every player gets the same maze for each level. Records: the deepest level and your fastest time for each.
- Settings › Maze › **Show the walls** draws every wall faintly, for trying things out.

## Switch

- A 7 × 8 board of squares in five shades (four of the main colour and the accent). **Swipe** a square to swap it with its neighbour; three or more of a shade in a line clear, the rest fall, and new squares drop in. Chains score ×2, ×3…
- **Powers**, in the shade of the square they're on: **four in a line** makes a line clearer (cut corners and a line across clears the row, a line down clears the column), **an L or a T** makes a circle that clears the squares around it, **five in a line** makes a diamond that clears every square of its shade. They go off when they're part of a line or caught in another power, and now and then one turns up on its own.
- **30 moves** a game; the best score is kept.

## Bounce

- **The game**: move the paddle with your finger, keep the ball up, and break the wall of squares that keeps drifting down. New rows keep coming, so a game lasts as long as you do; the ball, the wall and the tougher squares all speed up over time.
- **Squares**: plain squares in nine columns, with the same gap across and down. Pale squares take one hit, mid-tone two, solid three.
- **Special squares**, all in the accent colour, break in one hit and turn up at random, roughly:
  - **Row and column clearers** (every 20 or so, either one): squares with cut corners and a short line in the middle, across for a row, down for a column. Breaking one clears its whole row or column.
  - **Split square** (every 50 or so): a plain square; splits the ball in three.
  - **Blaster** (every 100 or so): an outline around a big inner square. The paddle shoots from both ends for 3 seconds; a thin line under the paddle shows the time left.
  - **Circle** (every 150 or so): a big circle, as wide as a square, that clears every square on the screen.
  - Special squares caught in a clear go off too.
- **Score multiplier**: every block the ball breaks before it comes back to the paddle raises it (×2, ×3, up to ×9). Twenty in a row earns an extra life (at most 5; +50 points when you're full).
- Power-up squares never appear in the two starting rows nearest the paddle.
- **Lives**: three to start. You lose one when your last ball falls, or when the wall reaches the line above your paddle (that also knocks the bottom three rows away).
- **Landing page** (with a back arrow to the menu): six squares over B O U N C E (the accent over the O), the four special squares and what they do, and Start low on the screen. After a game it shows your score, time and best, and Again.
- **Paddle**: sits well above the bottom of the screen, leaving room for your thumb under it.
- **Settings** (the half circle at the top right of the menu): Automatic, Light or Dark at the top; five looks (Graphite, Ocean, Sky, Blush, Forest) as one line of accent squares; the app icon can follow the look (off at first); haptics; your best score and longest game.
- **App icon**: one square in the accent colour in the centre of the look's background, a touch lighter at the top, with a soft shadow under it. `BounceApp/tools/make_icon.py` draws them.

SwiftUI, iOS 17+, no third-party libraries, nothing collected.

## Project layout

```
BounceApp/
  project.yml        XcodeGen project
  Sources/
    BounceApp.swift    entry point: the menu and each game's screens
    Menu/              the menu: a section per game
    Common/            the stretchy logo, the back arrow, the frame timer
    Maze/              Maze: the maze and the light, the game, drawing, its screens
    Switch/            Switch: the board, the rules, drawing, its screens
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

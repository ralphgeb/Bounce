# Bounce

Minimal games for iPhone, in the same style as Halo and Scout: the same looks, type and quiet interface.
The app opens on a menu of five games, one section each, split by thin lines:

- **Bounce**: a block breaker with an endless wall.
- **Hide**: Bounce in the dark. The wall stays still and the ball is your only light.
- **Maze**: find your way through 20 ever bigger mazes in pitch black, by the light you give off.
- **Switch**: a match-three of shades, with the same special shapes as Bounce.
- **Hue**: put a shuffled colour gradient back in order. 10 levels.

On the menu, drag in a game's section and its logo stretches after your finger and springs back (the others barely move); only a tap, without dragging, opens the game. Each landing page has the settings button at the top right.

**Tutorials**: the first time you play each game, a short tutorial teaches it by doing, one thing at a time (it waits for you to do each step; rule cards move on with a tap; Skip is always there). Settings › Show tutorials again brings them back.

## Hide

- Pitch black in dark mode (pitch white in light). Each ball is a light: rays stop at the squares, so they throw shadows, and a square shows only as much as the light reaching it. Your paddle is always visible.
- The wall doesn't move. Clear every square and the next, bigger board comes (5 rows, then one more each level up to 11, with tougher squares).
- The same powers as Bounce, a little more often, plus the **flare** (an accent ring) that lights up every square for 3 seconds. Three lives; 20 in a row earns one.

## Maze

- Pitch black in dark mode, pitch white in light mode. You are the accent square, and bright light comes out of you all around (about 5 tiles, gently breathing). Walls catch the light, brighter the closer they are, corners included, and throw shadows behind them; that is all you see. The view is zoomed in, about seven tiles across.
- **Swipe** up, down, left or right to slide until a wall, a turning or the way out. Swipe again while sliding and that move waits for the next stop.
- **Dots**: tap to drop a dot where you stand; tap on it again to pick it up. You get 10 on level 1 and 3 more each level on top of what you have left (a ring of new dots gathers into you, and a "+3" pops up by the count). Dots stay where you left them, glowing softly, brighter in your light.
- **The map**: hold still for a moment, or pinch in, and the view zooms out over the whole level showing the walls you've lit, your dots and a ring where you are (not the way out). Let go and it zooms back.
- **The way out** is an accent circle with its own glow.
- **20 levels**, each bigger and harder: level 1 is 21 x 29 tiles with the way out about 160 steps away and 17 dead ends; level 20 is 97 x 143 tiles, about 650 steps and 420 dead ends. Later levels branch more, with a few more loops. Every player gets the same mazes. [All 20 levels](docs/maze-levels.png) (drawn by `BounceApp/tools/maze_levels.py`, which uses the same generator and random numbers as the app). Records: the deepest level, the fastest time for each, and whether you've made it out of level 20.
- Settings › Maze › **Show the walls** draws every wall faintly, for trying things out.

## Switch

- A 7 x 8 board of squares in five shades: the main colour at 90%, 65%, 40% and 15%, and the accent. **Swipe** a square to swap it with its neighbour; three or more of a shade in a line clear, the rest fall, and new squares drop in. Chains score x2, x3…
- **Powers**, in the shade of the square they're on: **four across** makes a row clearer (cut corners, line across), **four down** a column clearer (line down), **five in a line** a circle that clears the squares around it, and a **T or an L** a diamond (with a shine sweeping across it) that clears every square of its shade. A diamond also turns up after every 120 squares cleared, and now and then a line clearer or circle turns up on its own.
- **No limit on moves**; end the game from pause to keep your score. **Hint** shows one move that works.

## Hue

- A 7 x 8 board blending smoothly between four corner colours (light, dark, your accent and a second accent from another look), mixed in OKLab so the steps look even. You see it finished for a moment ("Remember it"), then it shuffles.
- **Drag** a square onto another to swap them, or tap one then the other. Squares with a dot are fixed. Solve it and a wave runs across the board.
- **10 levels**, easy to hard: level 1 has its whole border fixed and 12 squares out of place; by level 10 only the four corners are fixed, every other square is shuffled, and the colours sit close together. Every player gets the same shuffle for each level. Pick any solved level (or the next one) from the row of squares on the landing page; the fewest swaps for each is kept.

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
    Hue/               Hue: the levels and colour maths, the game, its screens
    Common/Coach.swift the first-time tutorials
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

# Bricks

**Bricks**: minimal games for iPhone, in the same style as Halo and Scout: the same looks, type and quiet interface.
On first launch a short welcome shows BRICKS with its squares dropping into place, a line under it and the four games in a row, then you choose your look from six (a strip of squares above shows its colours; that one is yours for free) and Automatic, Light or Dark. After that the app opens on a menu of four games, one section each, split by thin lines:

- **Bounce**: a block breaker with an endless wall.
- **Maze**: find your way through 20 ever bigger mazes in pitch black, by the light you give off.
- **Switch**: a match-three of shades, with the same special shapes as Bounce.
- **Hue**: put a shuffled colour gradient back in order. 50 levels.

On the menu, drag in a game's section and its logo stretches after your finger and springs back (the others barely move); only a tap, without dragging, opens the game. Each landing page has the settings button at the top right.

**Unlock everything** (£1.99, once): every game can be played without it. It opens Maze and Hue past level 2, every look (the one picked at the start is free; the others show a padlock in Settings), and keeps your best scores in Bounce and Switch (without it, you see your score but your best isn't saved). Tapping a locked level or look (or Settings › Unlock everything) opens the unlock sheet, which uses Apple's own payment sheet (StoreKit 2) and has Restore purchases. In TestFlight it's Apple's sandbox, so nothing is charged. For trying it out, Settings › Unlock has **Apply paywall** (off = everything open) and **Reset purchase** (locks it all again on this iPhone until you buy or restore again). The product is created in App Store Connect by `.github/workflows/bounce-unlock-setup.yml`; Apple's Paid Applications Agreement must be signed in App Store Connect › Business.

**Tutorials**: the first time you play each game, a short tutorial teaches it by doing, on the real game, one thing at a time. Action steps show a small, see-through centred panel (at the top, or low for Bounce) and leave the game playable, with Skip at the bottom of the screen; pausing puts Carry on above the tutorial; rule cards sit in the middle and move on with a tap; the game waits while a card is up. Each tutorial is played on its own small board so the instructions above never cover it: Maze has a tutorial maze (a corridor to slide along, a dot to drop, move away from and come back to pick up, the map, then up and right to the star) before level 1; Switch plays seven guided moves where everything falls after each clear but nothing chains; Hue starts with one row of five shades to put back in order with two swaps. The squares to use are outlined and a finger shows the move. Skip is always there; Settings › Show tutorials again (above the records) brings them back. In Maze's tutorial, while it asks you to drop or pick up a dot, sliding two moves away fades the screen and brings you back to the spot.

## Maze

- Pitch black in dark mode, pitch white in light mode. You are the accent square, and bright light comes out of you all around (about 5 tiles, gently breathing). Each ray of light (360 of them, walked square by square so they end exactly on a wall's edge) stops at the first wall it meets: that wall lights up (brighter the closer it is, corners included, and steady as you move) and everything behind it stays in shadow; that is all you see. The view is zoomed in, about seven tiles across.
- **Swipe** up, down, left or right to slide until a wall, a turning or the way out. Swipe again while sliding and that move waits for the next stop.
- **Dots**: tap to drop a dot where you stand; tap on it again to pick it up. You get 10 on level 1 and 3 more each level on top of what you have left (a "+3" pops up by the count). Each level starts with you growing in from a tiny square as your light comes up, with one soft wave of light going out. Dots stay where you left them, glowing softly, brighter in your light.
- **The map**: pinch in and the view zooms out over the whole level. It stays dark: you see only what your light reaches, your dots and a ring where you are (not the star), so you can tell where your dots are compared to you. Let go and it zooms back.
- **The way out** is a glowing accent star, slowly turning (so it never looks like one of your dots). It only shows when your light reaches it, never on the map.
- **Squares to the star**: under the time, how many squares the star is from you, walking, counting down as you go. Once you're within a fifth of the starting distance it switches to "Close. Find it." and you're on your own (and your dots).
- **Stars**: each level gives 1 to 3. Three for close to the fewest slides that reach the star (within a quarter) in time (a second and a half a slide plus ten seconds); two for up to about twice the fewest; one otherwise. The level-done card shows them with your slides and the fewest; the landing page shows each level's stars and your total.
- **40 levels** with a slow learning curve: the first ones are tiny with almost no dead ends (level 1: 11 x 15 tiles, about 20 steps to the star), growing to level 10 (39 x 53 tiles, about 175 steps), then more slowly to level 40 (87 x 121 tiles). From level 11 the star isn't simply the farthest spot: it's the one with the longest walk for how near it is in a straight line, so it can be close by and still a long way round. Levels 1 and 2 are free; the rest come with Unlock everything. [All 40 levels](docs/maze-levels.png).
- **Map squares** (an accent outline round a smaller square): one on levels 1 to 4, then one more every four levels. Step on one and the view zooms out over the whole maze with every wall showing for 3 seconds. Every player gets the same mazes. [All 20 levels](docs/maze-levels.png) (drawn by `BounceApp/tools/maze_levels.py`, which uses the same generator and random numbers as the app). Records: the deepest level, the fastest time for each, and whether you've made it out of level 20.

## Switch

- An 8 x 8 board in seven colours. Choose before you play: **Mono** (four greys of the main colour and three tones of the accent) or **Colour** (three tones of a partner colour, the accent of another look picked to sit well with yours, a dark grey, and three tones of the accent). **Swipe** a square to swap it with its neighbour; three or more in a line clear, the rest fall, and new squares drop in. Chains score x2, x3…
- **Powers** only come from your lines: **four across** makes a row clearer (cut corners, line across), **four down** a column clearer (line down), **five in a line** a circle that clears the squares around it, and a **T or an L** a diamond that clears every square of its colour. Every power piece shines: a soft diagonal band of light sweeps across it now and then (brighter on the diamond). One diamond also turns up after every 120 squares cleared.
- **No limit on moves**; end the game from pause to keep your score. **Hint** shows one move that works.
- The tutorial is seven moves on real boards: three in a row, four, setting off the line clearer, five, the circle, a T, the diamond. Only your line ever clears (nothing falls in afterwards, so there are no surprise chains). Plain lines clear at normal speed; when a power goes off, what it reaches (the row, the column, the nine around the circle, or every square of the diamond's colour) glows for a moment first and then clears slowly.

## Hue

- A board blending smoothly between four corner colours (light, dark, your accent and a second accent from another look), mixed in OKLab so the steps look even. You see it finished for a moment ("Remember it"), then it shuffles.
- **Drag** a square onto another to swap them, or tap one then the other. Squares with a dot are fixed. Solve it and a wave runs across the board.
- **50 levels**, gently harder ([all of them](docs/hue-levels.png)): the first boards are small (5 x 5, 6 x 6, 6 x 7, 7 x 7) and 7 x 8 from level 5; level 1 has its whole border fixed and 6 squares out of place, levels 1 to 7 shuffle only some squares, and fewer squares are fixed as you go (alternate border squares from 7, corners and edge middles from 15, a few anchors from 25, only the corners from 39). The colours draw closer until about level 25 and then stay there, so the long run stays enjoyable. Some levels use one colour (white, the accent, black), others two accents. Every player gets the same shuffle for each level. Pick any solved level (or the next one) from the 10 x 5 grid on the landing page; the fewest swaps for each is kept.
- **Stars**: each level gives 1 to 3: three for solving it in the fewest swaps possible, two for a few more, one otherwise. The solved card shows them with your swaps and the fewest; the level grid shows each level's stars. Levels 1 and 2 are free; the rest come with Unlock everything.
- The logo's three squares are three shades of your accent.

## Bounce

- **The game**: move the paddle with your finger, keep the ball up, and break the wall of squares that keeps drifting down. New rows keep coming, so a game lasts as long as you do; the ball, the wall and the tougher squares all speed up over time.
- **Squares**: plain squares in nine columns, with the same gap across and down. Pale squares take one hit, mid-tone two, solid three.
- **Special squares**, all in the accent colour, break in one hit and turn up at random, roughly:
  - **Row and column clearers** (every 20 or so, either one): squares with cut corners and a short line in the middle, across for a row, down for a column. Breaking one clears its whole row or column.
  - **Split square** (every 50 or so): a plain square; splits the ball in three.
  - **Blaster** (every 90 or so): an outline around a big inner square. The paddle shoots from both ends for 3 seconds; a thin line under the paddle shows the time left.
  - **Circle** (every 150 or so): a big circle, as wide as a square, that clears every square on the screen.
  - **Heart** (every 75 or so at first, up to every 30 as the game speeds up): an extra life (+50 points when you have 5).
  - As the ball speeds up, every special square turns up more often (up to 1.6 times after 3 minutes).
  - Special squares caught in a clear go off too.
- **Score multiplier**: every block a ball breaks before it comes back to the paddle raises that ball's multiplier (×2, ×3, up to ×9). Each ball keeps its own: when the ball splits, the new ones carry on with it, a ball touching the paddle only ends its own run, and each run shows side by side at the top. Ten in a row earns an extra life (at most 5; +50 points when you're full).
- Power-up squares never appear in the two starting rows nearest the paddle.
- **Lives**: three to start. You lose one when your last ball falls, or when the wall reaches the line above your paddle (that also knocks the bottom three rows away).
- **Landing page** (with a back arrow to the menu): six squares over B O U N C E (the accent over the O), the four special squares and what they do, and Start low on the screen. After a game it shows your score, time and best, and Again.
- **Paddle**: sits well above the bottom of the screen, leaving room for your thumb under it.
- **Settings** (the half circle at the top right of the menu): Automatic, Light or Dark at the top; six looks (Graphite, Ocean, Sky, Blush, Dusk, Forest), each a small 3 x 3 grid blending from its accent to its main colour, with its name (one free, the others with Unlock everything); the app icon can follow the look (off at first); haptics; your best score and longest game.
- **App icon**: one square in the accent colour in the centre of the look's background, a touch lighter at the top, with a soft shadow under it. `BounceApp/tools/make_icon.py` draws them.

SwiftUI, iOS 17+, no third-party libraries, nothing collected.

## Project layout

```
BounceApp/
  project.yml        XcodeGen project
  Sources/
    BounceApp.swift    entry point: the menu and each game's screens
    Menu/              the menu: a section per game
    Onboarding/        the first-launch welcome and look picker
    Common/            the stretchy logo, the back arrow, the frame timer, Unlock everything
    Maze/              Maze: the maze and the light, the game, drawing, its screens
    Switch/            Switch: the board, the rules, drawing, its screens
    Hue/               Hue: the levels and colour maths, the game, its screens
    Common/Coach.swift the first-time tutorials: steps, the panel and cards, finger hints, pictures
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

# RoboCup: Ultimate

An AI-powered soccer simulation game where two fully autonomous teams compete in real-time. Built using HTML5 Canvas for rendering and **Tau Prolog** for AI decision-making logic.

## Overview

Two teams — **Strikers** and **Titans** — each with 4 players (goalkeeper, defender, midfielder, forward) compete to be the first to score 3 goals. Before the match, you predict the winner. After the final whistle, the game tells you if you were right.

All player behavior is driven by a Prolog knowledge base: each role has its own decision tree, and teams dynamically shift between attacking and defensive formations based on possession.

## Features

- Role-based AI with position-specific behaviors (GK, DEF, MID, FWD)
- Dynamic formations — teams adjust shape based on possession state
- Physics-based ball movement with friction decay and boundary handling
- Stamina system affecting player speed and action success rates
- Goalkeeper save probability based on shot distance and speed
- Cooldown system to prevent unrealistic rapid actions
- Real-time stats: shots, passes, tackles, saves
- Color-coded event log showing match actions
- Winner prediction with result verification at full-time

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Markup & Styling | HTML5, Tailwind CSS |
| Game Engine | JavaScript (Canvas 2D, requestAnimationFrame) |
| AI / Logic | [Tau Prolog](https://tau-prolog.org/) v0.3.4 |

## Getting Started

Clone the repo and open `robocup_enhanced.html` directly in any modern browser — no server or build step required. All dependencies load from CDN.

```bash
git clone <your-repo-url>
cd robo-cup-2
open robocup_enhanced.html   # macOS
# or just double-click the file in your file manager
```

## How to Play

1. Click **Kick Off** to begin match setup
2. Select your prediction — Strikers or Titans
3. Watch the match unfold on the canvas in real-time
4. First team to 3 goals wins
5. See if your prediction was correct, then rematch

## Project Structure

```
robo-cup-2/
├── robocup_enhanced.html   # Complete single-file application
│                     #   - HTML structure & Tailwind styling
│                     #   - Tau Prolog AI logic & ball physics
│                     #   - JavaScript game engine & Canvas renderer
└── robocup.pl        # Prolog source (reference copy, not loaded at runtime)
```

## Architecture

```
Browser (single HTML file)
├── HTML / Tailwind CSS      — UI, overlays, stats panels
├── JavaScript (RAF Loop)    — State sync, rendering, input handling
└── Tau Prolog Session       — Player AI, ball physics, score tracking
```

The Prolog session is created fresh for each match with 3000 choice points. JavaScript queries Prolog state each frame and renders it to the canvas at ~60 FPS.

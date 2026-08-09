# Gen1MMO

**Online play for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp): other trainers in *your* save.**

Install the mod, open GEN1MMO from the START menu, pick a name — and the
overworld you already play has real people walking around in it. Chat with
them, wave your look around, add friends. Disconnect any time; your game is
still just your game.

> **Beta.** One official server, online 24/7, already set up — install and
> play. No account beyond a name and password. No email. Ever.

## This is not a "start over" MMO

Other multiplayer projects give you a fresh character that lives on their
server. **Gen1MMO is an overlay on your own single-player save.** Your team,
your badges, your box full of level 100s from 1998 — that save is the one
other players see you walking around in. Nothing is uploaded, nothing is
imported, nothing is reset. The server only ever sees your position, your
chosen look, and what you type.

## Cheat or don't — everyone plays together

There is no anti-cheat and there never will be. GameShark teams, glitch
runs, speedruns, a perfectly legitimate Red cartridge playthrough — all of it
shares one world. Your save is yours to bend; being together is the point.
Everyone stays in the same world until a single area gets genuinely crowded —
the server actively keeps players on the same channel so you actually *see*
each other.

## Together is the feature

- **See other players** live on your map, with nametags — walk right through
  them, they can never block a doorway.
- **Chat**: map / channel / global scopes, a fading overlay in the game's own
  menu style (size and opacity are yours to tune), and native keyboard input
  on phones — tap the text line and type.
- **Press A on a player** to whisper or send a friend request.
- **Your look**: body, and eight skin tones that really render — on your own
  character too. Hair and outfits are drawn from the same catalog and coming
  to the sprite art next. All cosmetics free, forever.
- **Server info** in the menu: who's online, your channel, your ping.
- Plays nicely with other mods, including Dramatic Shape Voxel — nametags
  follow players into the 3D views.

## Privacy is the constitution, not a feature

Built to hold **as little about you as technically possible** — and the
server's own test suite fails if anyone tries to change that.

- Registration is a name and a password. **No email, no phone, no personal
  anything** — account recovery is a one-time code shown at registration
  (write it down; there are no resets because we have nothing to identify
  you with, which is the point).
- **Your password never leaves your device** — only a derived verifier does.
- **Everything is encrypted** end to end with the server's identity pinned
  in the mod — a fake server fails closed.
- **Chat is never stored.** Public messages are filtered (links blocked,
  profanity starred) and forgotten on delivery. Whispers are mutual-friends
  only.
- **No IP retention, no play history.** A subpoena or a breach would yield a
  username, a password verifier, an outfit, and a friends list.
- **No age verification, ever** — it's the one thing the server refuses to
  be taught.

Report bad actors in-game; repeat offenders forfeit their name.

## Install

1. Have Gen1Recomp set up with your own legally-obtained ROM (Gen1MMO ships
   no game data — your skin tones are even derived on-device from your own
   import).
2. Download the latest `gen1mmo-<version>.zip` from Releases.
3. Launcher → MODS → **Import mod .zip**, enable **Gen1MMO** (it asks for the
   `network` permission — that is the connection to the server, and every
   line it sends is readable in this repo).
4. In game: START → GEN1MMO → **Register**. That's the whole account.

Self-hosters: point the mod at your own server with a drop-in `config.lua`
(host, port, identity pin).

## Status

| | |
|---|---|
| Live player sync, nametags, pass-through collision | ✅ |
| Chat (3 scopes), overlay, native keyboard, filter | ✅ |
| Looks: body + 8 rendered skin tones, catalog for hair/outfits | ✅ |
| Friends, whispers, player interact menu | ✅ |
| Encrypted transport, pinned server identity | ✅ |
| Accounts + recovery codes, moderation, reports | ✅ |
| Hair/outfit sprite art, trading, more swag | 🔜 |

## Licence

MIT. Original code only — no ROM-derived content ships in this repository.

# Gen1MMO

**An MMO for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) — everyone
shares one world on a free public server, with nothing to host and no data
collected.**

Install the mod, open GEN1MMO from the START menu, pick a name, and the
world you already play fills with real people. Chat, show off your look,
make friends. One official server runs 24/7 and is already configured —
there is nothing to set up.

> Accounts are a name and a password. No email, ever.

## Your save is your character

Gen1MMO overlays multiplayer onto your own single-player save. Your team,
your badges, your box full of level 100s from way back — that is the
trainer other players meet. Nothing is uploaded, imported, or reset; you
keep playing the game you were already playing, and you can disconnect any
time. The server only ever sees your position, your chosen look, and what
you type.

## Everyone plays together

Your game stays your own: what other players see of you is your position,
your look, and your chat — never your save. That means how anyone plays
their own game can't affect yours, so there is no anti-cheat and no need
for one: play it straight, glitch it, GameShark it, and you all still meet
in the same overworld. When you enter an area the server places you with
the people already there, opening a parallel copy of that area only if it
gets genuinely crowded.

- **Live players on your map**, with floating nametags — and you can walk
  straight through anyone, so nobody can ever block a doorway.
- **Chat** in three scopes (map / channel / global), shown on a fading
  panel drawn in the game's own menu style — size, opacity, and length are
  yours to tune. On phones, tap the text line and your keyboard pops up.
- **Press A on a player** to whisper or send a friend request.
- **Your look**: body choice plus eight skin tones that render in the
  overworld — on your own character too. Hair styles and outfits come from
  the same catalog, with sprite art on the way. Every cosmetic is free,
  forever.
- **Server info** in the menu: players online, your channel, your ping.
- Plays nicely alongside other mods, including full 3D render mods —
  nametags follow players into those views.

## Privacy is the constitution

Gen1MMO is built to hold as little about you as technically possible, and
the server's own test suite fails any change that would weaken that.

- **An account is a name and a password.** No email, no phone, nothing
  personal. Recovery is a one-time code shown when you register — write it
  down; it is the only way back in, precisely because we hold nothing that
  could identify you.
- **Your password never leaves your device** — only a derived verifier
  does.
- **Every connection is encrypted** end to end, with the official server's
  identity pinned inside the mod, so an impostor server fails closed.
- **Chat is never stored.** Public messages are filtered (links blocked,
  profanity starred) and forgotten on delivery. Whispers are between
  mutual friends only.
- **No IP retention, no play history.** The server's complete knowledge of
  you: a username, a password verifier, an outfit, a friends list.
- **No age verification, ever.**

Report bad actors in-game; repeat offenders forfeit their name.

## Install

1. Have Gen1Recomp set up with your own legally-obtained ROM — Gen1MMO
   ships no game data, and even your skin tones are derived on-device from
   your own import.
2. Download the latest `gen1mmo-<version>.zip` from Releases.
3. Launcher → MODS → **Import mod .zip**, then enable **Gen1MMO**. It asks
   for the `network` permission — that is its connection to the server,
   and every line it sends is readable in this repository.
4. In game: START → GEN1MMO → **Register**. That's the whole account.

## Status

Multiplayer (connecting, chat, sync) is confirmed working on Desktop and
Android. iOS support is still being verified — the overworld, looks, and
everything offline work there today.

| | |
|---|---|
| Live player sync, nametags, walk-through collision | ✅ |
| Chat (3 scopes), tunable overlay, native keyboard, filter | ✅ |
| Looks: body + 8 rendered skin tones; hair/outfit catalog | ✅ |
| Friends, whispers (friends-only), player interact menu | ✅ |
| Trainer cards: badges, money, team, history badges, titles | ✅ |
| Emotes (heart / wave / fist) dropped as world breadcrumbs | ✅ |
| Encrypted transport with pinned server identity | ✅ |
| Accounts, recovery codes, in-game reports, moderation | ✅ |
| Hair/outfit sprite art, trading, more swag | 🔜 |

## Licence

MIT. Original code only — no ROM-derived content ships in this repository.
Emote icons are [Twemoji](https://github.com/jdecked/twemoji) (CC-BY 4.0);
see `assets/emotes/CREDITS.txt`.

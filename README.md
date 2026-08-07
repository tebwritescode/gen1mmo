# Gen1MMO

**PokeMMO-style online play for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp).**

Walk the same Kanto as other trainers in real time, chat, customise how your
character looks, and add friends — as a normal, installable mod. No ROM data is
touched or transmitted; Gen1MMO only syncs your position, your chosen look, and
your messages.

> **Beta.** This is an early release. The world sync, chat, and customisation
> work; expect rough edges. See *Status* below for exactly what is and isn't on
> yet.

## What it does

- **See other players** walking the overworld on your channel and map, as live
  trainers you can walk past (no bumping — you never block each other).
- **Chat** — local (same map), channel, and global, with a built-in filter (see
  *Privacy & safety*).
- **Customise your trainer** — body type, skin tone, hair style, hair colour,
  and outfit. Thousands of combinations, all free.
- **Friends & whispers** — add friends and message them privately.
- **Accounts** — pick a username and password in-game. No email required.

## Install

1. Have Gen1Recomp set up with your own legally-obtained ROM (Gen1MMO ships no
   game data).
2. Download the latest `gen1mmo-<version>.zip` from Releases.
3. In Gen1Recomp, open the Mod Manager and import the zip.
4. Enable **Gen1MMO**. It requests the **network** permission — that is how it
   reaches the game server. You can read every line of what it sends right here
   in this repo.
5. Launch, open the Gen1MMO menu, and register a username.

## Privacy & safety

Gen1MMO is built to hold **as little about you as technically possible.**

- **No email, no personal info.** Registration is a username and a password.
  Nothing else is asked or stored.
- **Your password never leaves your machine in the clear** — the client turns it
  into a verifier locally; the server never sees the password itself.
- **Chats are not stored.** Public messages are delivered and forgotten. Private
  whispers are between mutual friends only.
- **No IP logging** for player tracking. The server keeps no history of where
  you were or when you played.
- **Advertising and links are blocked; foul language is starred out**, so the
  world stays friendly for all ages. Filtering also runs *in your own client on
  what you receive*, so it protects you even if someone uses a modified client.
- **No age verification, ever.** By design — see the server's constitution.

Honest limits: no filter is perfect and no online space is risk-free. Report
bad actors with the in-game report tool; persistent offenders lose their name.

The server is open about exactly what it stores (essentially: your username, a
password verifier, your look, and your friends list) and what it never does. If
you run your own server, its source describes every byte on disk.

## Status (0.1.0-beta)

| Feature | State |
|---|---|
| Live overworld player sync | ✅ |
| Local / channel / global chat + filter | ✅ |
| Character customisation | ✅ |
| Friends & whispers | ✅ |
| Accounts (username + password) | ✅ |
| Report / moderation | ✅ |
| **End-to-end encrypted transport** | ⏳ *pre-launch gate — closed beta runs on a trusted, access-limited server until this lands* |
| Trading & PvP | 🔜 planned |
| Cosmetic "swag" | 🔜 planned |

## Connecting

By default the mod connects to the official Gen1MMO server. To point at your own,
set the server address in the Gen1MMO options screen.

## Licence

MIT. Original art and code only — no ROM-derived content, as required by the
Gen1Recomp mod index.

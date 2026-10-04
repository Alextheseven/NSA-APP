# DEDHEC Panel

A rebuilt server administration panel for Roblox. Same layout as the original DEDHEC panel (player list on the left, Ban / Kick / Scare / More on the right, Terminate Game at the bottom) with a modern, readable design and every action validated on the server.

## What changed from the original

| Original | Rebuilt |
| --- | --- |
| Blue text on solid red buttons | Dark theme with tinted icon tiles, readable contrast, hover and press feedback |
| Static `PlayerName` placeholder | Live player list with avatars, display names, `@usernames`, search and a `YOU` tag |
| No selected-player info | Target card with avatar, user ID, account age and status chips (`FROZEN`, `WATCHING`) |
| `More` did nothing | `More` slides to a second page: Kill, Freeze, Bring, Go to, Respawn, Spectate |
| Ban and Kick fire instantly | Confirmation dialog with an optional reason (filtered) and ban duration (1 hour, 1 day, 7 days, permanent) |
| Terminate Game is one click | Hold-to-confirm button with a progress fill, so it can't be triggered by accident |
| Fixed size | Scales to any screen, draggable header, open and close animations, toast notifications |
| Client-side only | Server checks admin access, rate-limits requests, validates every argument and protects other admins |

## Install

### Option A: drop-in place file

1. Open `DedhecPanel.rbxl` in Roblox Studio.
2. Copy these three items into the same locations in your game:
   - `ReplicatedStorage > DedhecPanel`
   - `ServerScriptService > DedhecPanelServer`
   - `StarterPlayer > StarterPlayerScripts > DedhecPanelClient`

### Option B: Rojo

```sh
rojo serve default.project.json
```

## Usage

- Press **F2** or click the red **D** button on the left edge of the screen to open the panel.
- Pick a player from the list, then choose an action.
- Ban and Kick open a dialog. Press Enter or **Ban player** / **Kick player** to confirm.
- **Terminate Game** must be held for 1.5 seconds. It kicks everyone and locks the server.
- Drag the panel by its header.

## Who gets access

Edit `ServerScriptService > DedhecPanelServer > Settings`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `AdminUserIds` | `{}` | User IDs that always get the panel, for example `{ 12345678, 87654321 }` |
| `AdminGroups` | `{}` | Group rank rules, for example `{ { GroupId = 1234567, MinimumRank = 200 } }` |
| `CreatorHasAccess` | `true` | The experience owner (or group owner rank) gets access |
| `CreatorGroupMinimumRank` | `255` | Minimum rank in the owning group when the game is group-owned |
| `StudioGrantsAccess` | `true` | Everyone is an admin during Studio play tests |
| `AllowTerminate` | `true` | Set to `false` to remove Terminate Game entirely |
| `LogActions` | `true` | Prints every action to the server output |

Players who aren't admins never get the panel UI, and the server rejects their requests even if they send them manually. Admins can't ban, kick, kill or freeze other admins.

## Client options

Edit `ReplicatedStorage > DedhecPanel > Config`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `ToggleKey` | `Enum.KeyCode.F2` | Keyboard shortcut that opens and closes the panel |
| `ShowLauncher` | `true` | Shows the small **D** button for mouse and mobile users |
| `TerminateHoldSeconds` | `1.5` | How long Terminate Game must be held |
| `Scare.Text` | `"I SEE YOU"` | Text shown in the jumpscare |
| `Scare.SoundId` | `""` | Optional sound, for example `"rbxassetid://1234567890"` |
| `Scare.ImageId` | `""` | Optional full-screen image, for example `"rbxassetid://1234567890"` |
| `Scare.Duration` | `2.2` | Seconds the jumpscare lasts |

## Bans

Bans use `Players:BanAsync`, so they apply across every server of the experience and Roblox also tries to block the player's alt accounts. Enable it in Studio by selecting **Players** in the Explorer and turning on **BanningEnabled**, then publish. If the Ban API call fails (for example because banning isn't enabled), the panel still kicks the player, bans them from the current server, and shows a warning telling you the ban is server-only.

## Project layout

```
src/
  shared/      ReplicatedStorage.DedhecPanel
    Protocol   action rules, limits and ban durations shared by client and server
    Config     client options
  server/      ServerScriptService.DedhecPanelServer
    Settings   admin access and messages
  client/      StarterPlayerScripts.DedhecPanelClient
    Panel      window, target card, actions, terminate button
    PlayerList player list and search
    Dialog     ban and kick confirmation
    Toasts     notifications
    Scare      jumpscare effect
    Components tiles, icon buttons and chips
    Theme      colors, fonts, motion and layout
    Ui         instance helpers
```

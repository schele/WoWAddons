# WoWAddons

World of Warcraft addons for WoW Forever (interface 16001) and Classic Era
(11509), one folder each. See [README.md](README.md) for layout, tests and
packaging.

- **Icons:** every icon and thumbnail comes from `tools/draw-icons.mjs`. Add
  new designs there; never draw one in a one-off script, and never scale a
  64px icon up for a thumbnail.
- **Publishing on Wago:** follow [docs/publishing.md](docs/publishing.md).
  Uploading reaches players, so do it only when asked for by name, after a
  `-WagoDryRun`; "commit and push" alone never includes an upload.
- **Windows look like BossLoot's:** the same SettingsFrameTemplate-based
  frame, logo in the title, red X, and a solid background, never
  see-through. Copy the frame code from BossLoot, BankBags or LFGBoard.
- **Every addon has a page in the game's options (AddOns list)**, and a new
  feature with any switch gets its option there, rows hanging a 16px gap
  under the description.
- **WoW Forever is not vanilla.** Data from the vMaNGOS (1.12) database is a
  first guess: check it against the real game before building on it, show
  players which data the game has confirmed, and bake players' recordings
  (saved-variables files) into releases. BossLoot learned this the hard way.

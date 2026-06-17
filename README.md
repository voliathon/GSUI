<!-- BEGIN DISCLAIMER (managed by FFXIWindower author; do not remove) -->
## ⚠️ Disclaimer — Use at Your Own Risk

This is unofficial, fan-made software for *Final Fantasy XI*. It is **not affiliated with, endorsed by, or supported by Square Enix Holdings Co., Ltd.** FINAL FANTASY is a registered trademark of Square Enix.

**Square Enix's official position is that third-party tools and modifications to the FFXI client are prohibited by the Terms of Service.** Installing or using this software may result in account suspension, account termination, character data loss, or other action taken by Square Enix at their sole discretion.

This software is provided **AS IS, without warranty of any kind**, express or implied — including but not limited to warranties of merchantability, fitness for a particular purpose, and non-infringement. In no event shall the author or contributors be liable for any claim, damages, account action, lost time, lost progress, file corruption, or any other liability arising from the use of, or inability to use, this software.

**By installing, building, or running this software you acknowledge that you understand and accept these risks.**

<!-- END DISCLAIMER -->
# GSUI — GSUI + GearTree-style GearSwap integration

## 🔑 Hotkey

**Default toggle: `Alt+G`**

Press `Alt+G` in-game to show or hide the window. Routes through Windower's `bind` system, so the keybind is automatically suppressed while the chat bar, search box, or macro editor is open.

**Rebind it any time** — GSUI is the only addon in the family with live hotkey rebinding:

| Command | What it does |
|---|---|
| `//gsui changekey p` | Bind to a specific letter / digit (a-z, 0-9, F1-F12) |
| `//gsui changekey capture` | Press any physical key — it becomes the new toggle |
| `//gsui changekey #45` | Bind to a raw DirectInput scancode (any 0-255) |
| `//gsui changekey off` | Disable the hotkey entirely; `//gsui` still works |
| `//gsui changekey` | Echo the current binding |

The rebind takes effect immediately — no `//lua reload` needed.

Slash-command equivalents: `//gsui`, `//gsui toggle`.

---

## ⌨️ Keyboard mode

GSUI ships with full keyboard navigation as an alternative to mouse +
drag. Toggle it with **F3** (the title bar shows `[F3:Drag]` in mouse
mode and `[F3:KB]` in keyboard mode). The keybind only fires while the
GSUI window is open and chat / macro editor is closed.

### Global keys

| Key | What it does |
|---|---|
| `F1` | Switch to **GearSwap** mode (gear builder + sets panel) |
| `F2` | Switch to **Organizer** mode (bag mover) |
| `F3` | Toggle Keyboard ↔ Drag mode |
| `F4` | Open / close the **Filter** dropdown |
| `Tab` | Cycle focus zone — what the cursor highlights |
| `↑ ↓ ← →` | Move within the current focus zone |
| `Enter` | Select / confirm — fires the action under the cursor |
| `Escape` | Cancel: closes filter, clears slot filter, deselects item |
| `Delete` | Remove the item from the focused equipment slot (Equip grid) |

### Focus zones

`Tab` cycles between these. The yellow cursor outline shows which zone
you're in.

**GearSwap mode:**

| Zone | What's there | How to interact |
|---|---|---|
| `inv` | All Storage grid (the inventory pane on the right) | Arrows move cell-by-cell. Enter selects an item; the focus jumps to `equip` so you can pick a slot for it. |
| `equip` | The 16 equipment slots (head, body, ear, ring, etc.) | Arrows move slot-by-slot. With an item selected, Enter equips it. With no item selected, Enter toggles slot-filter (restrict inventory grid to items that fit that slot). `Delete` clears the slot. |
| `buttons` | The action buttons on the left: **Generate Set / Remove / Remove All / Equip Now / Save / Load** | `↑ ↓` walks the button list. `Enter` fires the focused button. |
| `sets` | The gearset list at the bottom of the left panel (parsed from your current GearSwap .lua) | `↑ ↓` walks the rows. `Enter` clicks the focused row — loads its gear into the equip grid (and toggles branches open/closed). Use **Save** afterward to write your changes back to the .lua. |

**Organizer mode:**

| Zone | What's there | How to interact |
|---|---|---|
| `inv` | All Storage grid | Same as gearswap mode. Enter selects, focus jumps to `bags`. |
| `bags` | Bag list on the left (inventory / wardrobe / safe / locker / etc.) | Arrows walk the bags. Enter opens the focused bag's contents in the grid; with an item selected from `inv`, Enter moves it to the focused bag. |

### Filter dropdown (F4)

Opens a menu of stat-based and slot-based filters parsed from your live
inventory.

| Key | What it does |
|---|---|
| `F4` | Open dropdown (focus becomes `filter`) |
| `↑ ↓` | Walk filter presets |
| `Enter` | Apply the focused filter |
| `Escape` or `F4` again | Close dropdown |

The slot section at the bottom (`[Main]`, `[Sub]`, `[Head]`, …, `[Ring]`,
`[Back]`) restricts the inventory grid to items that fit that slot — same
effect as clicking the slot in the Equip grid, but reachable from inside
the dropdown.

### Chat commands

For users who prefer slash commands or want to wire actions into FFXI
macros:

| Command | What it does |
|---|---|
| `//gsui` or `//gsui toggle` | Open / close the window |
| `//gsui show` / `//gsui hide` | Explicit show / hide |
| `//gsui refresh` | Force re-scan inventory + sets file |
| `//gsui front` (or `top`, `raise`) | Pull GSUI on top of other addons |
| `//gsui sets-where` | Print which GearSwap file the locator picked + the candidate filenames it tried (diagnostic for "Sets (no GS file)") |
| `//gsui changekey …` | Rebind the toggle hotkey (see Hotkey section above) |

---

**Status: in development.** This is a fork of [GSUI](https://github.com/mullerdane85-hash/GSUI)
that adds direct read/edit/save integration with your currently-loaded
GearSwap Lua file, similar to [GearTree](https://github.com/tru2/GearTree).

GSUI runs **side-by-side with GSUI** so the stable addon stays working
while we iterate on the new features here.

## Key differences from GSUI

| | GSUI | GSUI |
|---|---|---|
| Toggle key | `B` | `N` |
| Slash command | `//gsui` | `//gsui` (or `//g2`) |
| Data file | `GSUI/data/...` | `GSUI/data/...` (separate settings) |
| Window title | "GSUI" | "GSUI" |

Both addons can be loaded at the same time — they don't share state or
keybinds.

## Planned features (the "incorporate GearTree" work)

- [ ] Auto-detect the currently-loaded GearSwap file based on the
      player's job (e.g. `Kalitzo_whm.lua` for WHM).
- [ ] Parse the file as text (not execute) to extract the `sets` table
      hierarchy — idle, engaged, precast, midcast, etc.
- [ ] New "Sets" tab showing the gear sets as a clickable tree.
      Click to expand / preview; double-click to equip via `gs equip`.
- [ ] Right-click a set to see its full slot-by-slot contents + augments
      detected via `extdata.decode`.
- [ ] Edit a set's slot in-place inside GSUI's UI, then save back to
      the source `.lua` file with an automatic backup.
- [ ] Annotation/note system for sets without modifying the source.
- [ ] Undo last save via `//gsui undo` (restore latest backup).

Heavy inspiration / reference implementation: [tru2/GearTree](https://github.com/tru2/GearTree)
(public domain / Unlicense — code may be ported or bundled freely).

## Inherits everything from GSUI 1.3.0

All the existing tabs and features are preserved:
- GearSwap set builder (`F1`)
- Inventory organizer with multi-select + bulk-move (`F2`)
- KB/Drag mode toggle (`F3`)
- Filter dropdown (`F4`)
- Gear Stats / Total Stats toggle
- Icon extraction from FFXI DAT files
- Save/load named sets (`/gsui save <name>` / `/gsui load <name>`)

See the [GSUI 1.3.0 changelog](https://github.com/mullerdane85-hash/GSUI/blob/main/README.md)
for the full list of inherited features.

## Credits

Inherits all of GSUI's credits (Rubenator, Trv, Byrthnoth — see GSUI's
README for details), plus:

- **tru2** — author of GearTree. The parser / tree / writer design that
  the planned Sets-tab work draws from is GearTree's. Bundled or ported
  code will live under `libs/gear_tree/` once added.

## Development notes

This addon is unstable while the GearTree integration is being built.
For day-to-day use, run **GSUI** (the stable one). Load GSUI only when
testing the new features:

```
//lua load GSUI
```

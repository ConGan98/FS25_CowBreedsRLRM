> [!NOTE]
> Ritter version of [FS25 Realistic Livestock](https://github.com/rittermod/FS25_RealisticLivestockRM) is needed for this to work.

<img src="images/icon1.png">


## FS25_CowBreedsRLRM
With the help of Ritter in creating the base structure of the mod, we are able to introduce 14 new cow breeds to the FS25_RealisticLivestockRM mod. This is a companion mod to work with FS25_Realistic_livestock. This mod adds new breeds with corresponding textures for each one. The 3D models of the base game cows are reused, so the 3D assets may appear larger or smaller than the actual breed of cow.

## Requires
- [FS25_RealisticLivestockRM](https://github.com/rittermod/FS25_RealisticLivestockRM) — required. v1.2.4.0 or newer recommended for the built-in Le Mechet bridge.
- [FS25_AnimalPackage_vanillaEdition](https://www.farming-simulator.com/) — *optional*. Adds five vanilla breeds via the Vanilla Edition Bridge.
- [FS25_The_Mechet](https://www.farming-simulator.com/) — *optional*. When the map is in use, the pack ships a Mechet-aware synth bundle so Charolaise / Simmental / Montbeliarde / Vosgienne render with their own meshes.

## Features

### Fourteen new breeds (always on)
Values adjusted to represent each breed — Holstein gives the most milk while Charolais and Angus gain the most weight for beef production.

**Six new dairy breeds**
- Red Holstein
- Ayrshire
- Jersey
- Guernsey
- Kerry
- Shorthorn Milkers

**Eight new beef breeds**
- Red Angus
- Hereford
- Charolais
- Shorthorn
- Irish Moiled
- British Blue
- Belted Galloway
- Simmental

### Vanilla Edition Bridge (optional)
If `FS25_AnimalPackage_vanillaEdition` is also loaded, five additional vanilla breeds are surfaced as bridge entries:
- Holstein (Vanilla)
- Red Holstein (Vanilla)
- Brown Swiss (Vanilla)
- Limousin (Vanilla)
- Angus (Vanilla)

Default mode (no Mechet): full GS01–GS04 growth-stage support for both cow and bull across all five breeds.

The bridge auto-disables if you don't have the vanilla mod installed.
To opt out manually, create an empty file at:
`<UserProfile>/Documents/My Games/FarmingSimulator2025/modSettings/CowBreedsRLRM_VanillaBridge.disabled`

### Le Mechet support (optional)
If [FS25_The_Mechet](https://www.farming-simulator.com/) is loaded, the pack ships a separate synth bundle (`_synth_mechet/` or `_synth_mechet_only/` depending on whether AnimalPackage is also loaded) that bakes Mechet's four custom breeds into the husbandry config:
- Charolaise
- Simmental (Mechet variant)
- Montbeliarde
- Vosgienne

Each at all four growth stages, both cow and bull. Renders with Mechet's own meshes — no fallback to base-game cattle.

When **all three** mods are loaded (pack + AnimalPackage + Mechet) the engine's 32-slot husbandry cap forces a trade-off: the vanilla bridge collapses to **bulls only** at all four growth stages, and vanilla cow subtypes are not purchasable. A one-time warning dialog explains this on each new save; acknowledgement is persisted per-savegame.

### Custom Highland textures
The Highland Cattle adult, calf and baby use a pack-local i3d wrapper plus fresh 4K BC7 diffuse textures, so the Highland look has been updated without modifying any base-game files.

### Water Buffalo
Water Buffalo adult, calf and baby are bundled and remapped through the pack atlases so they render with the correct buffalo models.

### Visual accessories on base breeds
Monitors, ear tags, sprayed markers, bum IDs and nose rings are wired up for the base-game breeds (Holstein, Brown Swiss, Limousin, Angus, Hereford) via a hook into RLRM's bridge override path.

## Installation
1. Place `FS25_CowBreedsRLRM.zip` in your `mods/` folder.
2. Make sure `FS25_RealisticLivestockRM` is enabled (v1.2.4.0+ recommended).
3. (Optional) Place `FS25_AnimalPackage_vanillaEdition.zip` in the same folder for the extra five vanilla breeds.
4. (Optional) `FS25_The_Mechet.zip` in the same folder for Mechet's four custom breeds — auto-detected at runtime.

If adding to an existing save game, refresh the animal dealer in settings so the new breeds show up straight away — otherwise wait a few in-game days.

## Compatibility
- Save-game safe: existing animals on a save before installing this pack will keep their breed; new breeds become purchasable from the dealer once you refresh.
- Pre-v1.0.4 saves (when subType identifiers used the lowercase `_pack` suffix, or no suffix at all) are auto-migrated on load by `Script/Migration.lua` — no manual action needed.
- The "Hereford" entry in the animal dealer is this pack's `HEREFORD_PACK`. RLRM's own bundled Hereford still exists and remains usable on existing saves with its stock RLRM appearance.
- Multiplayer supported.
- The bridge writes nothing to your `mods/` folder — when shipped zipped, it loads the right pre-built synth bundle (`_synth/`, `_synth_mechet/`, or `_synth_mechet_only/`) read-only from inside the pack.
- Save-compatible with the [FS25_Witcombe](https://www.farming-simulator.com/) map: Witcombe's Jersey breed renders correctly via the foreign-bridge vai remap (no Witcombe-specific synth needed).

## License
This mod is released under the GPL-3 license. See the [LICENSE](LICENSE) file for details.

## Credit
- [rittermod](https://github.com/rittermod) — full layout of the mod and the base bridge architecture.

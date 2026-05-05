> [!NOTE]
> Ritter version of [FS25 Realistic Livestock](https://github.com/rittermod/FS25_RealisticLivestockRM) is needed for this to work.

<img src="images/icon1.png">


## FS25_CowBreedsRLRM
With the help of Ritter in creating the base structure of the mod, we are able to introduce 12 new cow breeds to the FS25_RealisticLivestockRM mod. This is a companion mod to work with FS25_Realistic_livestock. This mod adds new breeds with corresponding textures for each one. The 3D models of the base game cows are reused, so the 3D assets may appear larger or smaller than the actual breed of cow.

## Requires
- [FS25_RealisticLivestockRM](https://github.com/rittermod/FS25_RealisticLivestockRM) — required.
- [FS25_AnimalPackage_vanillaEdition](https://www.farming-simulator.com/) — *optional*. When also loaded, the Vanilla Edition Bridge surfaces an extra five vanilla breeds (see below).

## Features

### Twelve new breeds (always on)
Values adjusted to represent each breed — Holstein gives the most milk while Charolais and Angus gain the most weight for beef production.

**Four new dairy breeds**
- Red Holstein
- Ayrshire
- Jersey
- Guernsey

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
If `FS25_AnimalPackage_vanillaEdition` is also loaded, five additional vanilla breeds are surfaced as bridge entries with full GS01–GS04 growth-stage support:
- Holstein (Vanilla)
- Red Holstein (Vanilla)
- Brown Swiss (Vanilla)
- Limousin (Vanilla)
- Angus (Vanilla)

The bridge auto-disables if you don't have the vanilla mod installed.
To opt out manually, create an empty file at:
`<UserProfile>/Documents/My Games/FarmingSimulator2025/modSettings/CowBreedsRLRM_VanillaBridge.disabled`

### Custom Highland textures
The Highland Cattle adult, calf and baby use a pack-local i3d wrapper plus fresh 4K BC7 diffuse textures, so the Highland look has been updated without modifying any base-game files.

### Water Buffalo
Water Buffalo adult, calf and baby are bundled and remapped through the pack atlases so they render with the correct buffalo models.

### Visual accessories on base breeds
Monitors, ear tags, sprayed markers, bum IDs and nose rings are wired up for the base-game breeds (Holstein, Brown Swiss, Limousin, Angus, Hereford) via a hook into RLRM's bridge override path.

## Installation
1. Place `FS25_CowBreedsRLRM.zip` in your `mods/` folder.
2. (Optional) Place `FS25_AnimalPackage_vanillaEdition.zip` in the same folder if you want the extra five vanilla breeds.
3. Make sure `FS25_RealisticLivestockRM` is also enabled.

If adding to an existing save game, refresh the animal dealer in settings so the new breeds show up straight away — otherwise wait a few in-game days.

## Compatibility
- Save-game safe: existing animals on a save before installing this pack will keep their breed; new breeds become purchasable from the dealer once you refresh.
- Multiplayer supported.
- The Vanilla Edition Bridge writes nothing to your `mods/` folder — when shipped zipped, it loads its bundle read-only from inside the pack.

## License
This mod is released under the GPL-3 license. See the [LICENSE](LICENSE) file for details.

## Credit
- [rittermod](https://github.com/rittermod) — full layout of the mod and the base bridge architecture.

# Patch34 ReaPack

**English** · [Русский](README_RU.md)

Personal ReaPack repository for REAPER scripts and JSFX by [Aleksei Vorobev / Patch34](https://github.com/patch-34).

## Installation

1. Install [ReaPack](https://reapack.com/) in REAPER.
2. Open **Extensions → ReaPack → Import repositories…** and add:

   `https://raw.githubusercontent.com/patch-34/patch34-reapack/main/index.xml`

3. Open **Extensions → ReaPack → Browse packages** and select the required script or JSFX.
4. Install and synchronize packages. The same interface provides updates.

## Packages

Seven new ReaScripts are staged in the `Scripts/` directory: Delete Nearest Marker to Cursor, Duplicate Selected Items to Next Measure, Play 2s Before Next Marker or Region, Find and Recolor Glued Items, Focus Blanket, REAPER Timeline Screensaver and Region Time Counter Mini.

`Effects/` contains Raw Six, a six-voice JSFX signal generator. Its package also installs the associated track template. Existing packages, including Region Time Counter (full), ReaNotepad and Podcast HTML/DOCX Script Viewer, remain independent and unchanged.

## Publishing

The index is generated automatically by `.github/workflows/reapack.yml` on pushes to `main`. Do not edit `index.xml` manually. When merging this change, confirm that the publishing workflow succeeds and that the generated index contains the new packages.

## Credits

Author: [Aleksei Vorobev / Patch34](https://github.com/patch-34).

See each package repository for its documentation and license.

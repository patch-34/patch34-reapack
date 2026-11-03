# Patch34 Scripts

**English** · [Русский](README_RU.md)

Lua ReaScripts and JSFX for REAPER — editing tools, workflow utilities, project navigation, and sound design experiments.

## About

**Patch34 Scripts** is a collection of Lua ReaScripts and JSFX for REAPER, developed by sound designer Aleksei Vorobev.

The collection includes tools for audio editing, timeline navigation, project organization, workflow automation, and experimental sound design.

Each tool is developed as an independent utility, with a focus on clear functionality, straightforward controls, and integration into everyday REAPER workflows.

**Author:** [Aleksei Vorobev / Patch34](https://github.com/patch-34)

## Installation

1. Install [ReaPack](https://reapack.com/) in REAPER.
2. Open **Extensions → ReaPack → Import repositories…** and add:

   `https://raw.githubusercontent.com/patch-34/patch34-reapack/main/index.xml`

3. Open **Extensions → ReaPack → Browse packages** and select the required script or JSFX.
4. Install and synchronize packages. The same interface provides updates.

## Packages

The `Scripts/` directory includes Delete Nearest Marker to Cursor, Duplicate Selected Items to Next Measure, Play 2s Before Next Marker or Region, Find and Recolor Glued Items, Focus Blanket, REAPER Timeline Screensaver, Region Time Counter Mini, Region Time Counter, ReaNotepad, and Podcast HTML/DOCX Script Viewer.

The `Effects/` directory includes Raw Six, a six-voice JSFX signal generator. Its package also installs the associated track template.

For usage instructions and licensing terms, see each tool's repository.

## Publishing

The index is generated automatically by `.github/workflows/reapack.yml` on pushes to `main`. Do not edit `index.xml` manually. After updating packages, confirm that the publishing workflow succeeds and that the resulting index contains the expected package versions.

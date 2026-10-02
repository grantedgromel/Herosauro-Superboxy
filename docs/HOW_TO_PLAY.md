# As Aventuras de Herosauro & Super Boxy: how to play

**Play in the browser:** https://grantedgromel.github.io/Herosauro-Superboxy/

Chrome, Edge or Safari on a laptop, iPad or Android tablet. The first load is
about 25 MB; later visits are cached. Every push to a `claude/**` branch or
`main` rebuilds and republishes it within about two minutes.

## The flow

Toca para começar → the bookshelf (three books) → 1 or 2 players → the story
pages, read aloud → the level → the last pages → a sticker on the book.

1. **O Gigante do Douro**: stop Adamastor on the Ponte D. Luís.
2. **O Tesouro do Dragão**: free Draco from the four ropes, knock the goblins
   over (footballs work!) and win back the six cups.
3. **Os Turistas Panda**: fix the eight broken houses for the Bambosa family,
   then find their four suitcases.

With **1 player** the other brother joins, played by the computer. With
**Ajudas** on (the default) nobody can lose: a hero who runs out of hearts
floats in a bubble and pops back. If a child stands still, a gold arrow shows
where to go and the goal is spoken aloud.

The gear on the bookshelf holds: Português / English, Ajudas, Narração,
Menos movimento (less shaking, no flashes), music and sound volume, credits.

## Controls

| | move | jump | attack | power |
|---|---|---|---|---|
| player 1, keyboard | arrows or WASD | Space | J, Q or left click | K, E or right click |
| player 2, keyboard | numpad 8 4 5 6 | numpad 0 | numpad 7 | numpad 9 |
| gamepads | first pad = player 1, second pad = player 2 | A | X | Y |
| tablet | drag anywhere on the left half | big buttons on the right | | |

Esc or the pause button: Continue, Settings, Back to the book.

## Putting the book's pictures in

The reader draws each page itself until the real illustrations exist. Page
ids follow the book: `d05` is page 5 of the Estádio do Dragão story, which is
`#5.png` in that Drive folder. To add them:

1. Download the Drive folders `#1: Adamastor`, `#2: Estadio do Dragao` and
   `#3: Panda Tourists`.
2. Upload their PNGs to this repository under `incoming_art/<chapter>/`
   (chapters: `adamastor`, `dragao`, `pandas`), or run
   `python3 tools/import_story_art.py <folder> <chapter>` from
   `herosauro-superboxy/` yourself.
3. The importer writes 1600 px WebP files to `assets/story/<chapter>/`, which
   the reader picks up automatically. Its mapping table (top of the script)
   says which Drive file is which page; adjust it if a guess is wrong.

## Your own voice

Narration uses the device's built-in voice. To replace it with a parent
reading the book, record one file per page and drop it at
`herosauro-superboxy/assets/story/voice/<pt|en>/<page id>.ogg`
(for example `voice/pt/d05.ogg`). A recording always wins over the device
voice, and it makes the book speak on browsers that have no Portuguese voice.

## Known limits

- The bridge chapter is the heaviest to draw; on an older tablet it may run
  slower than the other two.
- Narration depends on the browser having a Portuguese or English voice.
- The text is the final book, with a few spelling slips corrected
  (`docs/story/SOURCE.md` lists them).

## For developers

`docs/story/ADAPTATION.md` is the design contract, `ARCHITECTURE.md` the
engine rules. Checks: `tools/parsecheck.tscn`, every `scripts/**/_*probe.tscn`,
`tools/playtest.tscn`, `tools/kidbot/run_all.sh` (a clumsy-child bot that
plays each chapter to the end), and `tools/web_qa/play.mjs` (plays the real
web export in headless Chromium).

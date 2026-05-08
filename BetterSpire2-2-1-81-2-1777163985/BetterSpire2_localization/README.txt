BetterSpire2 Localization
=========================

This folder contains translation files for the BetterSpire2 UI.

The mod automatically picks the file matching your game's language setting.
You can also override the language from the F1 settings menu (Language dropdown).

EDITING A TRANSLATION
---------------------
To improve a translation, open the .json file for your language in any text
editor (save as UTF-8) and edit the VALUES. Do NOT change the keys.

Example:
  "setting.card_size": "Card Size"
                       ^^^^^^^^^^^
                       This is what you edit. Keep the key on the left alone.

After saving, restart the game or switch the mod language off and back on
in the F1 settings to reload.

SUPPORTED LANGUAGE FILENAMES
----------------------------
Filename must exactly match one of these codes (3 letters + .json):

  eng.json  - English
  zhs.json  - Chinese (Simplified)
  jpn.json  - Japanese
  kor.json  - Korean
  deu.json  - German
  fra.json  - French
  esp.json  - Spanish (Latin America)
  spa.json  - Spanish (Spain)
  ita.json  - Italian
  ptb.json  - Portuguese (Brazil)
  rus.json  - Russian
  pol.json  - Polish
  tha.json  - Thai
  tur.json  - Turkish

FALLBACK BEHAVIOR
-----------------
If your language file is missing a key, the English value is used instead.
If the whole file is missing or invalid, eng.json is used. If eng.json is
also missing, built-in English is used.

SHARING YOUR TRANSLATION
------------------------
If you improve a translation and want it included in the next release:
  - Nexus Mods: post your edited .json in the mod's comments
  - GitHub:     https://github.com/ open an issue or PR on the repo
  - Discord:    share via the mod's community channel

The translations in this folder were initially generated with AI assistance.
Native-speaker improvements are very welcome.

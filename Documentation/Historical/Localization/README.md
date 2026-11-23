# Localization: how it came to be

How keys are looked up in the languages TUI ships. Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [Which language a key is read in](<Which language a key is read in.md>) | Keys are looked up language by language, through the languages the user prefers, up to the first TUI ships (A14, decided 2026-10-05).  |
| [Script, region and the C locale](<Script, region and the C locale.md>) | A key is read under a language's full tag, then its bare one (`pt-BR`, `pt`), and Traditional Chinese is not Simplified (O-06 (a), 2026-11-21); `LC_ALL=C` means English (O-07 (b), 2026-11-21). |

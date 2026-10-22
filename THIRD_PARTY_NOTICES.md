# Third-Party Open Source Notices

Positron is licensed under the [MIT License](LICENSE) and incorporates or adapts work from the following open-source projects:

---

## 1. NotProton (`steam-bridge/engine`, `compat_run.sh`)
- **Upstream**: <https://github.com/NotProtonNot/NotProton>
- **License**: MIT License
- **Notes**: Portions of the macOS Steam compatibility hook engine and launch script originate from NotProton and have been extended in Positron with multi-runner discovery, per-game preset profiles, toggleable runtime fixes, external ExFAT/APFS shadow prefixes, and standalone game support.

---

## 2. Dobby (`vendor/dobby`)
- **Upstream**: <https://github.com/jmpews/Dobby>
- **License**: Apache License 2.0 (see [`vendor/dobby/LICENSE`](vendor/dobby/LICENSE))

---

## 3. cJSON (`steam-bridge/vendor/cJSON.c`, `steam-bridge/vendor/cJSON.h`)
- **Upstream**: <https://github.com/DaveGamble/cJSON>
- **License**: MIT License
- **Copyright**: Copyright (c) 2009-2017 Dave Gamble and cJSON contributors

---

## 4. Witcher 3 CrossOver DX12 & HDR Fixes (`Resources/fixes/witcher3`)
- **Upstreams**:
  - <https://github.com/tholtman1-del/witcher3-crossover-fix> (`ffxproxy.c`, `amd_fidelityfx_loader_dx12.dll`)
  - <https://github.com/tholtman1-del/witcher3-mac-hdr-fix> (`hdrfix.c`, `dinput8.def`, `dinput8.dll`)
- **License**: MIT License
- **Copyright**: Copyright (c) 2026 tholtman1-del

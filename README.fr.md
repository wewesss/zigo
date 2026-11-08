# zigo

> Validateur de données façon Zod pour Lua 5.1-5.4 et LuaJIT.

[English](./README.md) · Français

## Qu'est-ce que zigo ?

zigo garde le côté Lua de chaque frontière : tout ce qui entre dans Lua (résultat SQL, retour FFI, paquet réseau, config, input utilisateur) passe par un schéma qui le vérifie et rend une valeur sûre. Zéro dépendance, bundle single-file, même famille que [matchigo-lua](https://github.com/wewesss/matchigo-lua).

**Statut : pré-alpha, squelette.** Le dépôt ne contient que l'arborescence (`zigo/init.lua` qui expose `_VERSION`, build, tests, bench, CI). L'API de schémas n'est pas encore implémentée.

Design et architecture : [docs/DESIGN.md](./docs/DESIGN.md).

## Commandes

Depuis la racine du projet :

```sh
lua tests/run.lua          # tests sur les sources
lua build.lua              # bundle vers dist/zigo.lua et dist/zigo.min.lua
lua tests/run.lua dist     # tests sur le bundle
lua bench/run.lua          # bench (demande dist/ et un clone de matchigo-lua)
```

Le bench charge matchigo-lua depuis `MATCHIGO_PATH` (défaut `./matchigo-lua`) :

```sh
git clone --depth 1 https://github.com/wewesss/matchigo-lua.git matchigo-lua
```

Les résultats sont écrits dans `bench/results/runtime-<version>.md`.

## Licence

[MIT](./LICENSE) - Copyright (c) 2026 Wesley Cormier (SUP2Ak).

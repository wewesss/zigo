# zigo

> Validateur de données façon Zod pour Lua 5.1-5.4 et LuaJIT.

[English](./README.md) · Français

## Qu'est-ce que zigo ?

zigo garde le côté Lua de chaque frontière : tout ce qui entre dans Lua (résultat SQL, retour FFI, paquet réseau, config, input utilisateur) passe par un schéma qui le vérifie et rend une valeur sûre. API fluente immuable, erreurs structurées et déterministes, codegen du chemin valide, limites réseau, entiers 64 bits, UTF-8, cdata et sentinelles NULL. Zéro dépendance, bundle single-file, même famille que [matchigo-lua](https://github.com/wewesss/matchigo-lua) : un schéma zigo est directement un pattern matchigo.

**Statut : 1.0.0.** Testé sur Lua 5.1, 5.2, 5.3, 5.4 et LuaJIT 2.1.

## Installation

```sh
luarocks install zigo
```

Ou poser `zigo.lua`, tiré de l'[archive de release](https://github.com/wewesss/zigo/releases), sur le `package.path`.

## Exemple

```lua
local z = require("zigo")

local User = z.object({
    name = z.utf8():min(1):max(32),
    age = z.integer():between(0, 150):optional(),
    role = z.enum({ "admin", "user" }),
}):strict()

local ok, user, err = User:safeParse({ name = "", role = "root" })
print(ok) --> false
print(err:format())
--> name: Expected length of at least 1, got 0
--> role: Expected one of: "admin", "user", got "root"
```

## Documentation

- [Guide (English)](./docs/en/guide.md) · [Guide (Français)](./docs/fr/guide.md)
- [Design et architecture](./docs/DESIGN.md)
- [Résultats benchmark](./bench/results/README.fr.md)
- [Changelog](./CHANGELOG.md) (anglais)

## Développement

```sh
lua tests/run.lua          # tests sur les sources
lua build.lua              # bundle vers dist/zigo.lua et dist/zigo.min.lua
lua tests/run.lua dist     # tests sur le bundle
lua bench/run.lua          # bench (demande dist/ et un clone de matchigo-lua)
```

Le test d'intégration matchigo et le bench chargent matchigo-lua depuis `MATCHIGO_PATH` (défaut `./matchigo-lua` pour le bench) :

```sh
git clone --depth 1 https://github.com/wewesss/matchigo-lua.git matchigo-lua
MATCHIGO_PATH=./matchigo-lua lua tests/run.lua
```

## Licence

[MIT](./LICENSE) - Copyright (c) 2026 Wesley Cormier (SUP2Ak).

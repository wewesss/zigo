# zigo

[![CI](https://github.com/wewesss/zigo/actions/workflows/ci.yml/badge.svg)](https://github.com/wewesss/zigo/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/wewesss/zigo)](https://github.com/wewesss/zigo/releases/latest) [![LuaRocks](https://img.shields.io/luarocks/v/SUP2Ak/zigo?color=blue)](https://luarocks.org/modules/SUP2Ak/zigo) [![lang](https://img.shields.io/badge/lang-Lua%205.1%2B%20%2F%20LuaJIT-green)](https://github.com/wewesss/zigo) [![runtime deps](https://img.shields.io/badge/runtime%20deps-0-brightgreen)](https://github.com/wewesss/zigo) [![license](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

> "Validateur de données façon Zod pour Lua 5.1-5.4 et LuaJIT."

📖 [English](./README.md) · Français

[Démarrage rapide](./docs/fr/guide.md#2-démarrage-rapide) · [Primitives](./docs/fr/guide.md#3-primitives) · [Conteneurs](./docs/fr/guide.md#9-conteneurs) · [Unions](./docs/fr/guide.md#10-unions-et-récursion) · [Erreurs](./docs/fr/guide.md#12-erreurs) · [Limites réseau](./docs/fr/guide.md#13-limites-réseau) · [Interop matchigo](./docs/fr/guide.md#17-interop-matchigo) · [Performance](./docs/fr/guide.md#18-performance)

---

## 🧠 Qu'est-ce que zigo ?

zigo garde le côté Lua de chaque frontière : tout ce qui entre dans Lua (résultat SQL, retour FFI, paquet réseau, config, input utilisateur) passe par un schéma qui le vérifie et rend une valeur sûre. API fluente immuable, erreurs structurées et déterministes, codegen du chemin valide, limites réseau, entiers 64 bits, UTF-8, cdata et sentinelles NULL. Zéro dépendance, bundle single-file, même famille que [matchigo-lua](https://github.com/wewesss/matchigo-lua) : un schéma zigo est directement un pattern matchigo.

**Statut : 1.0.0.** Testé sur Lua 5.1, 5.2, 5.3, 5.4 et LuaJIT 2.1.

---

## 🚀 Quickstart

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

Une union validée par tag, aiguillée par une table de hachage :

```lua
local z = require("zigo")

local Packet = z.discriminatedUnion("kind",
    z.object({ kind = z.literal("ping"), id = z.integer() }),
    z.object({ kind = z.literal("chat"), text = z.utf8():max(200) })
)

print(Packet:is({ kind = "ping", id = 1 })) --> true

local _, _, unknown = Packet:safeParse({ kind = "pong" })
print(unknown:format()) --> kind: Expected discriminator one of: "ping", "chat", got "pong"

local _, _, bad = Packet:safeParse({ kind = "chat", text = 5 })
print(bad:format()) --> text: Expected utf8, got number

print((pcall(z.discriminatedUnion, "kind", z.object({ kind = z.string() })))) --> false
```

La suite dans le [guide](./docs/fr/guide.md), dont l'[interop matchigo](./docs/fr/guide.md#17-interop-matchigo).

---

## 📦 Installation

### LuaRocks

```sh
luarocks install zigo
```

### Télécharger depuis la release

Téléchargez `zigo-<tag>.zip` (par exemple `zigo-v1.0.0.zip`) depuis la [dernière release](https://github.com/wewesss/zigo/releases/latest). Il contient un dossier `zigo-<tag>/` avec :

```
zigo.lua          <- distribution bundle lisible (avec en-tête)
zigo.min.lua      <- distribution minifiée sur une ligne (même code)
zigo-type/        <- définitions de types LuaLS / EmmyLua (zigo.d.lua)
LICENSE
README.md
```

Posez `zigo.lua` (ou `zigo.min.lua`) sur votre `package.path`, ou chargez-le directement :

```lua
package.path = "path/to/zigo-v1.0.0/?.lua;" .. package.path
local z = require("zigo")

local z2 = dofile("path/to/zigo-v1.0.0/zigo.lua")
```

Pour la complétion et le hover dans [lua-language-server](https://github.com/LuaLS/lua-language-server), posez le dossier `zigo-type/` dans votre workspace, ou ajoutez-le à `Lua.workspace.library` dans les réglages VSCode (la clé est `workspace.library` dans un `.luarc.json`) :

```json
{
  "Lua.workspace.library": ["path/to/zigo-v1.0.0/zigo-type"]
}
```

### Depuis les sources

```sh
git clone https://github.com/wewesss/zigo.git
cd zigo
lua build.lua              # -> dist/zigo.lua et dist/zigo.min.lua
lua tests/run.lua          # tests sur les sources
lua tests/run.lua dist     # tests sur le bundle
```

Le bundle lisible fait environ 3 600 lignes (120 Ko), le minifié 80 Ko (`wc -c dist/*.lua`, `wc -l dist/zigo.lua`).

Testé sur **Lua 5.1, 5.2, 5.3, 5.4** et **LuaJIT 2.1**. Zéro dépendance.

---

## ✨ Fonctionnalités

- **Cœur** : nœuds de schéma immuables, `parse` / `safeParse` (`ok, value, err`) / `is`, `string`, `number`, `integer`, `boolean`, `literal`, `enum`, `any`, `unknown`, `never`, `object`, `array`, `:optional()`, `:min()` / `:max()` / `:between()` / `:len()`.
- **Erreurs** : erreurs structurées à codes stables, `err:format()`, `err:flatten()`, messages anglais remplaçables (`z.setMessages`, `z.messages`).
- **Codegen** : le chemin valide est compilé avec `load` en une seule fonction plate, avec repli automatique sur des closures (`z.config({ codegen = false })`). Les schémas purs n'allouent rien sur un appel valide.
- **Schémas impurs** : `:default()`, `:transform()`, `:refine()`, `:pipe()`, `:strip()`, `ctx:addIssue()`, `z.coerce.*` strict.
- **Conteneurs** : `union`, `discriminatedUnion` (dispatch par hachage), `tuple` avec `:rest()`, `record`, `lazy` pour les schémas récursifs.
- **Limites réseau** : `maxDepth` (64), `maxKeys` (10000), `maxErrors` (100), `abortEarly`, réglées par `z.config` ou `schema:limits()`.
- **Types de frontière** : `u8` ... `u32`, `i8` ... `i32`, `int64` (avec `fromString`), `bytes`, `utf8` (RFC 3629 strict), `cdata` et `notNullPtr` (LuaJIT), `null` / `:nullable()` avec une sentinelle NULL configurable, `userdata`, `instanceOf`, `func`.
- **Outillage** : annotations LuaCATS dans `types/zigo.d.lua`, interop directe avec [matchigo-lua](https://github.com/wewesss/matchigo-lua).

→ Référence complète : [`docs/fr/guide.md`](./docs/fr/guide.md)

---

## 📚 Documentation

- [Guide (English)](./docs/en/guide.md) · [Guide (Français)](./docs/fr/guide.md)
- [Design et architecture](./docs/DESIGN.md)
- [Résultats benchmark](./bench/results/README.fr.md)
- [Changelog](./CHANGELOG.md) (anglais)

---

## 🛠️ Build & tests

```sh
lua tests/run.lua                # tests sur les sources
lua tests/run.lua --no-codegen   # même suite, closures seulement
lua build.lua                    # bundle vers dist/zigo.lua et dist/zigo.min.lua
lua tests/run.lua dist           # tests sur le bundle
lua bench/run.lua                # bench (demande dist/ et un clone de matchigo-lua)
```

Le test d'intégration matchigo et le bench chargent matchigo-lua depuis `MATCHIGO_PATH` (défaut `./matchigo-lua` pour le bench) :

```sh
git clone --depth 1 https://github.com/wewesss/matchigo-lua.git matchigo-lua
MATCHIGO_PATH=./matchigo-lua lua tests/run.lua
```

---

## 🤝 Contribuer

Lisez [CONTRIBUTING.md](./CONTRIBUTING.md) (en anglais) avant d'ouvrir une pull request. Les règles de communauté sont dans [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md), et les signalements de sécurité passent par [SECURITY.md](./SECURITY.md).

---

## ❤️ Support

Si zigo vous aide :

👉 [Star le repo](https://github.com/wewesss/zigo) · [Ouvrir une issue](https://github.com/wewesss/zigo/issues) · [Projet frère : matchigo-lua](https://github.com/wewesss/matchigo-lua)

---

## 📜 Licence

[MIT](./LICENSE) - Copyright (c) 2026 Wesley Cormier (SUP2Ak).

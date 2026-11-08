# Guide zigo

[English](../en/guide.md) · Français

zigo 1.0.0 valide les données du côté Lua d'une frontière (lignes SQL, retours FFI, paquets réseau, config, input utilisateur) : un schéma vérifie la valeur et rend une valeur sûre. Lua 5.1 à 5.4 et LuaJIT 2.1, zéro dépendance.

1. [Installation](#1-installation) · 2. [Démarrage rapide](#2-démarrage-rapide) · 3. [Primitives](#3-primitives) · 4. [Littéraux et types spéciaux](#4-littéraux-et-types-spéciaux) · 5. [Entiers](#5-entiers) · 6. [Chaînes et octets](#6-chaînes-et-octets) · 7. [NULL, nullable et optional](#7-null-nullable-et-optional) · 8. [Types Lua et FFI](#8-types-lua-et-ffi) · 9. [Conteneurs](#9-conteneurs) · 10. [Unions et récursion](#10-unions-et-récursion) · 11. [Modificateurs](#11-modificateurs) · 12. [Erreurs](#12-erreurs) · 13. [Limites réseau](#13-limites-réseau) · 14. [Codegen](#14-codegen) · 15. [Différences entre runtimes](#15-différences-entre-runtimes) · 16. [Annotations LuaCATS](#16-annotations-luacats) · 17. [Interop matchigo](#17-interop-matchigo) · 18. [Performance](#18-performance)

## 1. Installation

LuaRocks :

```sh
luarocks install zigo
```

Bundle single-file : télécharger l'archive de release `zigo-<tag>.zip` depuis les [releases GitHub](https://github.com/wewesss/zigo/releases). Elle contient `zigo.lua` (lisible), `zigo.min.lua` (même code, minifié) et `zigo-type/` (annotations LuaCATS). Poser l'un des deux fichiers sur le `package.path`, ou le charger directement :

```lua skip
local z = require("zigo")
local z2 = dofile("path/to/zigo.lua")
```

Sources : cloner le dépôt et ajouter sa racine au `package.path`. `lua build.lua` régénère `dist/zigo.lua` et `dist/zigo.min.lua`.

```lua skip
package.path = "path/to/zigo/?.lua;path/to/zigo/?/init.lua;" .. package.path
local z = require("zigo")
```

## 2. Démarrage rapide

```lua
local z = require("zigo")

local User = z.object({
    name = z.string():min(1),
    age = z.integer():between(0, 150):optional(),
    role = z.enum({ "admin", "user" }),
}):strict()

local ok, user, err = User:safeParse({ name = "ann", role = "admin" })
print(ok) --> true
print(user.name) --> ann
print(err) --> nil
```

`safeParse` ne lève jamais d'erreur sur une mauvaise entrée et rend trois valeurs : `ok, value, err`. En cas de succès, `err` vaut `nil`. En cas d'échec, `value` vaut `nil` et `err` est un objet erreur.

```lua
local z = require("zigo")

local User = z.object({
    name = z.string():min(1),
    role = z.enum({ "admin", "user" }),
}):strict()

local ok, value, err = User:safeParse({ name = "", role = "root", extra = 1 })
print(ok) --> false
print(value) --> nil
print(err:format())
--> name: Expected length of at least 1, got 0
--> role: Expected one of: "admin", "user", got "root"
--> extra: Unrecognized key
```

Les trois points d'entrée de tout schéma :

| Appel | Rend | Sur une entrée invalide |
| --- | --- | --- |
| `schema:safeParse(v)` | `ok, value, err` | `false, nil, err` |
| `schema:parse(v)` | `value` | lève l'objet erreur (utiliser `pcall`, le reconnaître avec `z.isError`) |
| `schema:is(v)` | `boolean` | `false` |

```lua
local z = require("zigo")

local Age = z.integer():min(0)
print(Age:is(3)) --> true
print(Age:parse(3)) --> 3

local ok, e = pcall(Age.parse, Age, -1)
print(ok) --> false
print(z.isError(e)) --> true
print(tostring(e))
--> ZigoError: 1 issue(s)
--> <root>: Expected value of at least 0, got -1
```

Règles valables partout :

- Les schémas sont immuables : chaque modificateur rend un nouveau nœud et ne change jamais la source. Un schéma se partage sans risque.
- La compilation est paresseuse (au premier usage) et cachée sur le nœud. Construire les schémas une fois, au chargement, jamais dans un handler de requête.
- Aucune coercition implicite : `"12"` n'est pas un entier. La coercition n'existe que via `z.coerce.*` ([section 11](#11-modificateurs)).
- Même entrée, mêmes issues, même ordre, sur tous les runtimes.
- Un schéma sans `default`, `transform`, `refine`, `pipe`, `coerce` ni `strip` est pur : un appel valide n'alloue rien et `safeParse` rend la valeur même que vous avez passée.

## 3. Primitives

| Constructeur | Accepte | Modificateurs |
| --- | --- | --- |
| `z.string()` | une chaîne | `:min(n) :max(n) :between(lo, hi) :len(n)` sur la longueur en octets |
| `z.number()` | tout nombre sauf NaN (les infinis passent) | `:min(n) :max(n) :between(lo, hi)` |
| `z.integer(opts?)` | un nombre de valeur entière, jamais NaN ni infini ; `3.0` passe | `:min(n) :max(n) :between(lo, hi)` |
| `z.boolean()` | `true` ou `false` | aucun |

Les bornes sont inclusives. `len` vérifie une taille exacte. Les arguments de `min`, `max`, `between` et `len` sont contrôlés à la construction, et `len` demande un entier positif ou nul. `integer({ strict = true })` refuse `3.0` en Lua 5.3 et 5.4 (voir la [section 15](#15-différences-entre-runtimes)).

```lua
local z = require("zigo")

print(z.string():min(2):max(8):is("zigo")) --> true
print(z.string():len(3):is("zigo")) --> false
print(z.number():between(0, 1):is(0.5)) --> true
print(z.number():is(0 / 0)) --> false
print(z.integer():is(3.5)) --> false
print(z.integer():is(7)) --> true
print(z.boolean():is("true")) --> false
```

```lua lua53
local z = require("zigo")

print(z.integer():is(3.0)) --> true
print(z.integer({ strict = true }):is(3.0)) --> false
```

Les bornes, `strict`, `strip` et `rest` doivent venir avant le premier `transform`, `refine` ou `pipe` ; après, ils lèvent une erreur.

## 4. Littéraux et types spéciaux

| Constructeur | Accepte |
| --- | --- |
| `z.literal(v)` | exactement `v` : une chaîne, un nombre (pas NaN) ou un booléen |
| `z.enum(list)` | une valeur d'une liste non vide de chaînes, de nombres ou de booléens |
| `z.any()` | toute valeur, `nil` compris |
| `z.unknown()` | toute valeur, `nil` compris (mêmes contrôles que `any`) |
| `z.never()` | rien |

```lua
local z = require("zigo")

print(z.literal("ok"):is("ok")) --> true
print(z.literal(1):is(2)) --> false
print(z.enum({ "a", "b" }):is("c")) --> false
print(z.any():is(nil)) --> true
print(z.unknown():is({})) --> true
print(z.never():is(1)) --> false
```

## 5. Entiers

### Entiers à taille fixe

`z.u8()`, `z.u16()`, `z.u32()`, `z.i8()`, `z.i16()` et `z.i32()` suivent la règle de `integer()` (`3.0` passe, `{ strict = true }` le refuse) et ajoutent la plage du type : `u8` de 0 à 255, `u16` de 0 à 65535, `u32` de 0 à 4294967295, `i8` de -128 à 127, `i16` de -32768 à 32767, `i32` de -2147483648 à 2147483647. `:min`, `:max` et `:between` resserrent cette plage. Une valeur qui n'est pas un entier donne `invalid_type` ; une valeur hors plage donne `too_small` ou `too_big`.

```lua
local z = require("zigo")

print(z.u8():is(255)) --> true
print(z.u8():is(256)) --> false
print(z.u8():max(100):is(101)) --> false

local _, _, err = z.i8():safeParse(-129)
print(err:format()) --> <root>: Expected value of at least -128, got -129
```

### int64

`z.int64()` accepte ce que le runtime sait tenir comme entier 64 bits :

- Lua 5.3 et 5.4 : tout entier natif, et les flottants de valeur entière jusqu'à 2^53 ;
- LuaJIT : le cdata `int64_t` (`5LL`), et les nombres de valeur entière jusqu'à 2^53 ; le cdata `uint64_t` (`5ULL`) est refusé ;
- Lua 5.1 et 5.2 : les nombres de valeur entière jusqu'à 2^53 (un nombre plus grand ne se distingue plus de ses voisins).

`z.int64({ fromString = true })` accepte aussi une chaîne décimale (`-?%d+`, sans espace ni signe `+`) et rend une forme fixe par runtime : un entier natif en 5.3 et 5.4, un cdata `int64_t` sous LuaJIT, un nombre jusqu'à 2^53 ailleurs. Une chaîne hors plage donne `too_big` ou `too_small`. Tout ce qui n'est pas une chaîne passe tel quel par le contrôle `int64` normal.

```lua
local z = require("zigo")

local Id = z.int64()
print(Id:is(2 ^ 53)) --> true
print(Id:is(1.5)) --> false
print(Id:is("12")) --> false

local FromText = z.int64({ fromString = true })
local ok, id = FromText:safeParse("12")
print(ok) --> true
print(tonumber(id)) --> 12
print(FromText:is("12x")) --> false
```

```lua lua53
local z = require("zigo")

local FromText = z.int64({ fromString = true })
local _, id = FromText:safeParse("9007199254740993")
print(math.type(id)) --> integer
print(id) --> 9007199254740993

local ok, _, err = FromText:safeParse("9223372036854775808")
print(ok) --> false
print(err.issues[1].code) --> too_big
```

```lua luajit
local z = require("zigo")
local ffi = require("ffi")

local FromText = z.int64({ fromString = true })
local _, id = FromText:safeParse("9007199254740993")
print(tostring(id)) --> 9007199254740993LL
print(ffi.istype("int64_t", id)) --> true
print(z.int64():is(ffi.new("int64_t", 5))) --> true
print(z.int64():is(ffi.new("uint64_t", 5))) --> false
```

```lua lua51
local z = require("zigo")

local FromText = z.int64({ fromString = true })
print(FromText:is("9007199254740992")) --> true

local ok, _, err = FromText:safeParse("9007199254740993")
print(ok) --> false
print(err.issues[1].code) --> too_big
```

## 6. Chaînes et octets

`z.bytes()` a les mêmes contrôles que `z.string()` et dit l'intention : des données binaires, des tailles en octets. `z.string()` ne vérifie pas l'encodage.

`z.utf8()` n'accepte que de l'UTF-8 valide au sens de la RFC 3629 (ni formes trop longues, ni surrogates, rien au-delà de U+10FFFF). Le verdict est le même sur tous les runtimes. Pour `utf8`, `:min`, `:max`, `:between` et `:len` comptent des caractères, pas des octets. Une séquence invalide donne `invalid_type` avec `got = "bytes"`.

```lua
local z = require("zigo")

print(z.utf8():min(1):max(3):is("héé")) --> true
print(z.string():max(3):is("héé")) --> false
print(z.utf8():is("\255")) --> false
print(z.bytes():len(2):is("\0\255")) --> true

local _, _, err = z.utf8():safeParse("\255")
print(err:format()) --> <root>: Expected utf8, got bytes
```

## 7. NULL, nullable et optional

Lua n'a pas de valeur pour le `NULL` SQL ni pour le `null` JSON : les bibliothèques utilisent une sentinelle (`cjson.null`, `ngx.null`, `vim.NIL`, ou une table à vous). zigo garde les deux idées séparées :

- `:optional()` accepte `nil` (une clé absente).
- `:nullable(sentinel)` accepte la sentinelle, comparée par `rawequal`, et `parse` la rend telle quelle. Il n'accepte pas `nil`.
- `z.null(sentinel)` n'accepte que la sentinelle.

```lua
local z = require("zigo")

local NULL = setmetatable({}, { __tostring = function() return "NULL" end })

local Row = z.object({
    id = z.integer(),
    nickname = z.string():nullable(NULL),
    bio = z.string():optional(),
})

print(Row:is({ id = 1, nickname = NULL })) --> true
print(Row:is({ id = 1, nickname = "bo", bio = "hi" })) --> true
print(Row:is({ id = 1 })) --> false
print(Row:is({ id = 1, nickname = NULL, bio = NULL })) --> false
```

`z.config({ null = NULL })` fixe la sentinelle par défaut, ce qui permet d'appeler `z.null()` et `:nullable()` sans argument. Un schéma capture sa sentinelle quand il est construit. Une sentinelle peut être n'importe quelle valeur sauf `nil` et NaN. L'ensemble des sentinelles est global : une sentinelle table, userdata ou cdata est nommée `null` dans les messages de tous les schémas ; ne pas choisir un objet partagé comme `io.stdout`.

```lua
local z = require("zigo")

local NULL = {}
z.config({ null = NULL })

print(z.null():is(NULL)) --> true
print(z.null():is(nil)) --> false
local ok, v = z.string():nullable():safeParse(NULL)
print(v == NULL) --> true
```

## 8. Types Lua et FFI

| Constructeur | Accepte |
| --- | --- |
| `z.func()` | une fonction |
| `z.userdata(mt?)` | un userdata (pas un cdata LuaJIT) ; avec `mt`, son `getmetatable` doit être exactement `mt` |
| `z.instanceOf(mt)` | une table ou un userdata dont le `getmetatable` est exactement `mt` ; aucune remontée par `__index`, donc une sous-classe ne passe pas |
| `z.cdata(ctype)` | LuaJIT seulement : un cdata pour lequel `ffi.istype(ctype, v)` est vrai ; le type est résolu au premier appel |
| `z.notNullPtr(ctype)` | LuaJIT seulement : pareil, `ctype` doit être un type pointeur et le pointeur ne doit pas être NULL |

Hors LuaJIT, `cdata` et `notNullPtr` se construisent quand même et refusent toute valeur avec `invalid_type`.

```lua
local z = require("zigo")

local Point = {}
Point.__index = Point
local p = setmetatable({ x = 1 }, Point)

print(z.instanceOf(Point):is(p)) --> true
print(z.instanceOf(Point):is({ x = 1 })) --> false
print(z.func():is(print)) --> true
print(z.userdata():is(io.stdout)) --> true
print(z.userdata(getmetatable(io.stdout)):is(io.stdout)) --> true
```

```lua luajit
local z = require("zigo")
local ffi = require("ffi")

ffi.cdef("typedef struct { int x; } point_t;")
local obj = ffi.new("point_t", 1)
local p = ffi.cast("point_t *", obj)
local null = ffi.cast("point_t *", nil)

local Ptr = z.cdata("point_t *")
local NonNull = z.notNullPtr("point_t *")
print(Ptr:is(p)) --> true
print(Ptr:is(null)) --> true
print(NonNull:is(p)) --> true
print(NonNull:is(null)) --> false

local _, _, err = NonNull:safeParse(null)
print(err:format()) --> <root>: Expected non-null point_t *, got NULL
```

Sous LuaJIT, un pointeur NULL est égal à `nil`. `:optional()` sur les autres types, et les contrôles de trous des tableaux et des tuples, le voient donc comme absent ; seuls `cdata` et `notNullPtr` font la différence.

## 9. Conteneurs

### object

`z.object(shape, opts?)` prend une table de clés chaînes vers des schémas. Les champs sont vérifiés dans l'ordre alphabétique de leurs clés (fixé à la construction), ce qui rend les erreurs déterministes. Une clé absente arrive à son schéma comme `nil`.

| Mode | Clés inconnues | Coût |
| --- | --- | --- |
| passthrough (défaut) | conservées | aucune copie |
| `:strict()` | erreur `unrecognized_key` | aucune copie, une itération de plus |
| `:strip()` | retirées | copie de la table (schéma impur) |

Le dernier appel entre `:strict()` et `:strip()` l'emporte. Pour tout ce qui vient du réseau, préférer `:strict()`.

```lua
local z = require("zigo")

local Shape = z.object({ id = z.integer() })
local input = { id = 1, extra = true }

print(Shape:is(input)) --> true
print(Shape:strict():is(input)) --> false

local ok, same = Shape:safeParse(input)
print(same == input) --> true

local _, stripped = Shape:strip():safeParse(input)
print(stripped.extra) --> nil
print(stripped == input) --> false

local _, _, err = Shape:strict():safeParse(input)
print(err:format()) --> extra: Unrecognized key
```

Par défaut, `object`, `array` et `tuple` lisent les champs avec `rawget`. `{ meta = true }` en second argument les lit par l'indexation normale (`__index`, `__len`).

```lua
local z = require("zigo")

local proxy = setmetatable({}, { __index = { name = "x" } })
print(z.object({ name = z.string() }):is(proxy)) --> false
print(z.object({ name = z.string() }, { meta = true }):is(proxy)) --> true
```

### array

`z.array(item, opts?)` accepte une séquence : sans trou, sans clé autre que `1..n`. `{}` est valide. `:min`, `:max`, `:between` et `:len` bornent la longueur. Une table qui n'est pas une séquence propre donne `invalid_array`.

```lua
local z = require("zigo")

local Tags = z.array(z.string()):max(3)
print(Tags:is({ "a", "b" })) --> true
print(Tags:is({})) --> true
print(Tags:is({ "a", nil, "c" })) --> false
print(Tags:is({ a = "x" })) --> false

local _, _, err = Tags:safeParse({ "a", 2 })
print(err:format()) --> [2]: Expected string, got number
```

### tuple

`z.tuple(items, opts?)` est une liste de longueur fixe, un schéma par position. Les éléments en trop sont refusés, sauf si `:rest(schema)` les vérifie.

```lua
local z = require("zigo")

local Pair = z.tuple({ z.string(), z.integer() })
print(Pair:is({ "a", 1 })) --> true
print(Pair:is({ "a", 1, 2 })) --> false

local Row = Pair:rest(z.boolean())
print(Row:is({ "a", 1, true, false })) --> true
print(Row:is({ "a", 1, true, 1 })) --> false
```

### record

`z.record(key, value)` est une table à nombre de clés libre, dont toutes les clés passent `key` et toutes les valeurs passent `value`. Le schéma de clé doit être pur (ni `default`, ni `transform`, `refine`, `pipe`, `coerce`). Les erreurs sortent avec les clés triées : nombres, puis chaînes, puis booléens.

```lua
local z = require("zigo")

local Scores = z.record(z.string():min(1), z.integer())
print(Scores:is({ ann = 3, bo = 5 })) --> true
print(Scores:is({ [""] = 1 })) --> false

local _, _, err = Scores:safeParse({ ann = "x" })
print(err:format()) --> ann: Expected integer, got string
```

## 10. Unions et récursion

### union

`z.union(a, b, ...)` : la première variante qui passe l'emporte. Si aucune ne passe, l'issue est `invalid_union`, et son champ `unionErrors` porte la liste des issues de chaque variante.

```lua
local z = require("zigo")

local Id = z.union(z.integer(), z.string():min(1))
print(Id:is(7)) --> true
print(Id:is("u7")) --> true
print(Id:is(true)) --> false

local _, _, err = Id:safeParse(true)
local issue = err.issues[1]
print(issue.code) --> invalid_union
print(#issue.unionErrors) --> 2
print(issue.unionErrors[1][1].code) --> invalid_type
```

### discriminatedUnion

`z.discriminatedUnion(key, variants...)` choisit la variante par une table de hachage sur le champ `key`. Chaque variante doit être un `z.object` qui a un littéral simple à `key` (ni optional, ni nullable, ni default), et deux variantes ne peuvent pas partager une valeur ; sinon la construction lève une erreur. Il n'y a aucun repli séquentiel : un discriminant absent ou inconnu donne `invalid_union_discriminator` au chemin `key`, avec les valeurs attendues. Quand le discriminant correspond, on obtient seulement les issues de cette variante.

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

### lazy

`z.lazy(fn)` diffère un schéma, ce qui permet les types récursifs. `fn` est appelée au premier usage et doit rendre un schéma pur. La profondeur est comptée à l'exécution et bornée par `maxDepth` ([section 13](#13-limites-réseau)) : des données cycliques finissent donc en `too_deep` plutôt qu'en débordement de pile.

```lua
local z = require("zigo")

local Tree
Tree = z.object({
    value = z.integer(),
    children = z.array(z.lazy(function() return Tree end)),
})

print(Tree:is({ value = 1, children = { { value = 2, children = {} } } })) --> true

local cyclic = { value = 1 }
cyclic.children = { cyclic }
local _, _, err = Tree:safeParse(cyclic)
print(err.issues[1].code) --> too_deep
```

## 11. Modificateurs

| Modificateur | Effet |
| --- | --- |
| `:optional()` | accepte `nil` |
| `:nullable(sentinel?)` | accepte la sentinelle NULL ([section 7](#7-null-nullable-et-optional)) |
| `:default(x)` | quand l'entrée vaut `nil`, le résultat est `x` tel quel, ou `x()` si `x` est une fonction ; le défaut n'est pas validé |
| `:transform(fn)` | remplace la valeur validée par `fn(value, ctx)` |
| `:refine(fn, opts?)` | `fn(value, ctx)` doit rendre une valeur vraie ; sinon une issue est ajoutée |
| `:pipe(schema)` | passe la valeur courante dans un autre schéma |
| `:limits(opts)` | limites propres au schéma ([section 13](#13-limites-réseau)) |

Les étapes s'exécutent dans l'ordre où elles sont écrites. Chacune reçoit la sortie de la précédente.

```lua
local z = require("zigo")

local Settings = z.object({
    port = z.integer():between(1, 65535):default(8080),
    tags = z.array(z.string()):default(function() return {} end),
    name = z.string():transform(function(s) return s:lower() end),
})

local _, cfg = Settings:safeParse({ name = "Zigo" })
print(cfg.port) --> 8080
print(#cfg.tags) --> 0
print(cfg.name) --> zigo
```

Un défaut qui est une table est partagé entre les appels : passer une fonction pour obtenir une table neuve à chaque fois.

### transform et refine

`refine` prend les options `message`, `code` (défaut `"custom"`) et `path` (une liste ajoutée au chemin courant). Un `transform` signale l'échec avec `ctx:addIssue({ message, code, path })`, les trois champs étant facultatifs ; `refine` peut l'appeler aussi, et tout appel compte comme un échec.

```lua
local z = require("zigo")

local Even = z.integer():refine(function(n)
    return n % 2 == 0
end, { message = "must be even", code = "odd" })

local _, _, err = Even:safeParse(3)
print(err:format()) --> <root>: must be even
print(err.issues[1].code) --> odd

local Port = z.string():transform(function(s, ctx)
    local n = tonumber(s)
    if not n then
        ctx:addIssue({ message = "not a number", code = "nan_port" })
        return nil
    end
    return n
end)

local _, port = Port:safeParse("80")
print(port) --> 80
local _, _, bad = Port:safeParse("x")
print(bad:format()) --> <root>: not a number
```

Deux pièges. `fn` est appelée comme `fn(value, ctx)` : une fonction qui lit un second argument, comme `tonumber`, doit être enveloppée. Et un `transform` doit être sans effet de bord, car après un échec la passe de diagnostic peut le rappeler.

### pipe

```lua
local z = require("zigo")

local Age = z.string()
    :transform(function(s) return tonumber(s) end)
    :pipe(z.integer():between(0, 150))

print(Age:is("42")) --> true
print(Age:is("200")) --> false
print(Age:is("x")) --> false
```

### coerce

`z.coerce.*` convertit, puis valide, avec des règles strictes :

| Constructeur | Convertit |
| --- | --- |
| `z.coerce.number()` | une chaîne sans espace ni caractère de contrôle, par `tonumber` (`"0x10"` et `"1e2"` passent) ; NaN et les infinis sont refusés |
| `z.coerce.integer(opts?)` | pareil, puis le contrôle `integer` |
| `z.coerce.u8()` ... `z.coerce.i32()` | pareil, puis la plage du type |
| `z.coerce.boolean()` | seulement `"true"`, `"false"`, `"1"`, `"0"`, `1`, `0` |
| `z.coerce.string()` | les nombres et les booléens par `tostring` ; les tables et `nil` sont refusés |

Les bornes et `strict` s'appliquent après la conversion. `z.int64({ fromString = true })` est la coercition de `int64` ([section 5](#5-entiers)).

```lua
local z = require("zigo")

print(z.coerce.number():parse("1.5")) --> 1.5
print(z.coerce.integer():parse("42")) --> 42
print(z.coerce.boolean():parse("false")) --> false
print(z.coerce.string():parse(12)) --> 12
print(z.coerce.integer():is("4.5")) --> false
print(z.coerce.number():is(" 7")) --> false
print(z.coerce.u8():is("300")) --> false
```

### Schémas purs et impurs

Un schéma qui utilise `default`, `transform`, `refine`, `pipe`, `coerce` ou `strip` (ou qui en contient un) est impur. Une seule passe valide et construit la sortie : `is` donne donc le même verdict que `safeParse` et exécute vos fonctions. La sortie d'un objet impur est une table neuve. Un schéma pur rend l'entrée intacte et n'alloue rien sur un appel valide.

## 12. Erreurs

`err.issues` est une liste de tables, dans un ordre fixe :

| Champ | Sens |
| --- | --- |
| `path` | liste des clés et indices depuis la racine (`{}` pour la racine) |
| `code` | code stable, voir ci-dessous |
| `expected`, `got` | ce qui était attendu et ce qui a été trouvé ; dépend du code |
| `type` | pour les codes de taille et de plage, le genre (`string`, `integer`, `array`, ...) |
| `exact` | `true` quand l'échec vient de `len` |
| `message` | posé seulement par `refine`, `transform` ou `addIssue` ; il l'emporte sur la table des codes |
| `unionErrors` | pour `invalid_union`, les issues de chaque variante |

| Code | Levé quand | `expected` / `got` |
| --- | --- | --- |
| `invalid_type` | mauvais type | nom du type / type trouvé (`nil`, `float`, `nan`, `null`, `bytes`, ...) |
| `too_small` | sous `min`, plus court que `len`, sous la plage du type | borne / valeur ou longueur |
| `too_big` | au-dessus de `max`, plus long que `len`, au-dessus de la plage du type | borne / valeur ou longueur |
| `invalid_literal` | pas le littéral | le littéral / valeur trouvée |
| `invalid_enum` | hors de la liste | la liste des valeurs / valeur trouvée |
| `invalid_array` | table qui n'est pas une séquence (trou, clé en trop) | `"sequence"` / `"table"` |
| `unrecognized_key` | clé inconnue dans un objet `:strict()` | le chemin se termine par la clé ; pour une clé qui est une fonction, une table, un thread, un userdata ou un cdata, le chemin s'arrête à la table et `got` est le type de la clé |
| `invalid_union` | aucune variante ne passe | `unionErrors` |
| `invalid_union_discriminator` | discriminant absent ou inconnu | liste des valeurs / valeur trouvée |
| `too_deep` | imbrication plus profonde que `maxDepth` | la limite |
| `too_many_keys` | plus de clés que `maxKeys` | la limite |
| `custom` | échec de `refine` ou de `transform` sans code | aucun |

Lire une erreur :

```lua
local z = require("zigo")

local Form = z.object({
    email = z.string():min(5),
    age = z.integer():min(18),
    address = z.object({ zip = z.string():len(5) }),
})

local _, _, err = Form:safeParse({ email = "a", age = 12, address = { zip = "1" } })

local first = err.issues[1]
print(table.concat(first.path, ".")) --> address.zip
print(first.code) --> too_small
print(first.exact) --> true

print(err:format())
--> address.zip: Expected length of exactly 5, got 1
--> age: Expected value of at least 18, got 12
--> email: Expected length of at least 5, got 1

local flat = err:flatten()
print(flat.fieldErrors["age"][1]) --> Expected value of at least 18, got 12
print(#flat.formErrors) --> 0
```

- `err:format(messages?)` rend une ligne `chemin: message` par issue. Les chemins se lisent `a.b[2].c`, et la racine s'écrit `<root>`.
- `err:flatten(messages?)` rend `{ formErrors = {...}, fieldErrors = { ["a.b"] = {...} } }` : les messages de la racine vont dans `formErrors`, les autres dans `fieldErrors` sous leur chemin.
- `tostring(err)` donne `ZigoError: N issue(s)` suivi de `format()`.
- Les messages sont produits à la demande, jamais pendant la validation.

### Traduire les messages

Les messages vivent dans une table `code -> string | function(issue)`. Une chaîne peut employer des marqueurs `{champ}` remplacés par les champs de l'issue (`{expected}`, `{got}`, `{type}`, `{code}`). `err:format(table)` et `err:flatten(table)` utilisent la table donnée pour cet appel, et les codes qui y manquent retombent sur l'anglais intégré. `z.setMessages(table)` remplace des entrées pour tout le processus, et `z.messages` est la table vivante des défauts.

```lua
local z = require("zigo")

local Form = z.object({
    age = z.integer():min(18),
    email = z.string():min(5),
})
local _, _, err = Form:safeParse({ age = 12, email = 7 })

local fr = {
    too_small = "trop petit : {got} (minimum {expected})",
    invalid_type = function(i) return "attendu " .. tostring(i.expected) .. ", reçu " .. tostring(i.got) end,
}

print(err:format(fr))
--> age: trop petit : 12 (minimum 18)
--> email: attendu string, reçu number

z.setMessages(fr)
print(err:format())
--> age: trop petit : 12 (minimum 18)
--> email: attendu string, reçu number
```

## 13. Limites réseau

Quatre limites protègent contre une entrée hostile. Elles sont actives par défaut :

| Option | Défaut | Effet |
| --- | --- | --- |
| `maxDepth` | `64` | niveaux d'imbrication ; au-delà, `too_deep` (cela arrête aussi les données cycliques) |
| `maxKeys` | `10000` | clés d'une table que le validateur parcourt (tableaux, tuples, records, objets `:strict()` et `:strip()`) ; au-delà, `too_many_keys`. Un objet passthrough ne parcourt pas ses clés, la limite ne lui coûte donc rien |
| `maxErrors` | `100` | issues conservées dans une erreur |
| `abortEarly` | `false` | `true` s'arrête à la première issue |

Deux façons de les régler. `z.config({ ... })` change les défauts du processus et vaut pour les schémas compilés ensuite, c'est-à-dire avant leur premier usage. `schema:limits({ ... })` les fixe pour un schéma et ceux qu'il contient (un enfant qui a ses propres `:limits` les garde). La signature de `safeParse` ne change pas. Les valeurs sont des entiers positifs (ou `math.huge`), `abortEarly` un booléen ; une option inconnue lève une erreur.

```lua
local z = require("zigo")

local Items = z.array(z.integer())
local junk = {}
for i = 1, 300 do junk[i] = "x" end

local _, _, err = Items:safeParse(junk)
print(#err.issues) --> 100

local _, _, err5 = Items:limits({ maxErrors = 5 }):safeParse(junk)
print(#err5.issues) --> 5

local _, _, err1 = Items:limits({ abortEarly = true }):safeParse(junk)
print(#err1.issues) --> 1

local Small = z.array(z.integer()):limits({ maxKeys = 3 })
local _, _, tooMany = Small:safeParse({ 1, 2, 3, 4 })
print(tooMany.issues[1].code) --> too_many_keys

local Nested = z.object({ a = z.object({ b = z.integer() }) }):limits({ maxDepth = 1 })
local _, _, tooDeep = Nested:safeParse({ a = { b = 1 } })
print(tooDeep.issues[1].code) --> too_deep
```

```lua
local z = require("zigo")

z.config({ maxDepth = 8, maxErrors = 20 })
local cfg = z.config()
print(cfg.maxDepth) --> 8
print(cfg.maxKeys) --> 10000
print(cfg.codegen) --> true
```

`z.config()` sans argument rend les valeurs courantes (`maxDepth`, `maxKeys`, `maxErrors`, `abortEarly`, `codegen`, `null`). Pour une entrée réseau, combiner des objets `:strict()` avec un `maxKeys` et un `maxDepth` explicites, et poser `abortEarly` si seul un oui ou non compte.

## 14. Codegen

Au premier usage, le test du chemin valide (`_test`) d'un schéma est compilé avec `load` en une seule fonction plate. Les clés et les littéraux passent par `%q` ou par une table de constantes, jamais par une concaténation brute : un nom de clé hostile ne peut donc pas injecter de code. La passe de diagnostic (`_check`) reste toujours en closures, puisqu'elle ne tourne qu'en cas d'échec.

Si `load` est absent ou refuse le code (certaines sandboxes de jeu), zigo retombe seul sur les closures. `z.config({ codegen = false })` force les closures ; cela vaut pour les schémas compilés ensuite. Les verdicts, les erreurs et leur ordre sont les mêmes dans les deux cas (un test de fuzz compare les deux implémentations).

```lua
local z = require("zigo")

z.config({ codegen = false })
local S = z.string():min(1)
print(S:is("a")) --> true
print(z.config().codegen) --> false
```

## 15. Différences entre runtimes

zigo est testé sur Lua 5.1, 5.2, 5.3, 5.4 et LuaJIT 2.1 (matrice CI, sources et bundle, avec et sans codegen). Seuls ces points diffèrent :

| | Lua 5.1 / 5.2 | Lua 5.3 / 5.4 | LuaJIT 2.1 |
| --- | --- | --- | --- |
| `integer({ strict = true })` | pas de distinction entier/flottant : `3.0` passe | refuse `3.0` | comme 5.1 |
| `int64()` accepte | nombres de valeur entière jusqu'à 2^53 | entiers natifs, flottants de valeur entière jusqu'à 2^53 | cdata `int64_t`, nombres de valeur entière jusqu'à 2^53 |
| `int64({ fromString = true })` rend | un nombre jusqu'à 2^53, `too_big` / `too_small` au-delà | un entier natif, `too_big` / `too_small` hors de la plage 64 bits | un cdata `int64_t` (`tostring` donne `123LL`) |
| `cdata`, `notNullPtr` | refusent toute valeur | refusent toute valeur | fonctionnent |
| pointeur NULL égal à `nil` | non | non | oui ([section 8](#8-types-lua-et-ffi)) |

`utf8`, les tableaux, les objets, les erreurs et tous les autres types donnent le même verdict partout.

## 16. Annotations LuaCATS

`types/zigo.d.lua` est un fichier `---@meta` pour [lua-language-server](https://github.com/LuaLS/lua-language-server) : complétion et survol pour `require("zigo")`, les schémas (`zigo.Node`, `zigo.SizedNode`, `zigo.ObjectNode`, `zigo.TupleNode`), les erreurs (`zigo.Error`, `zigo.Issue`) et les options. C'est un fichier de définitions, sans code d'exécution. Un test vérifie que chaque clé publique de `zigo` y est déclarée.

Où le trouver : dans le dépôt (`types/`), dans l'archive de release (`zigo-type/zigo.d.lua`), et dans le dossier du rock (`.../lib/luarocks/rocks-<version de Lua>/zigo/<version>/types/` dans votre arbre LuaRocks). L'ajouter à la bibliothèque du workspace dans `.luarc.json` :

```json
{
  "workspace.library": ["path/to/zigo/types"]
}
```

```lua
local z = require("zigo")

---@type zigo.ObjectNode
local User = z.object({ name = z.string() })
print(User:is({ name = "ann" })) --> true
```

Les annotations restent approximatives : elles décrivent l'API, pas la forme des données validées (il n'y a pas d'équivalent de `z.infer`).

## 17. Interop matchigo

[matchigo-lua](https://github.com/wewesss/matchigo-lua) est la bibliothèque de pattern matching de la même famille. zigo n'en dépend pas. Un nœud zigo expose `_test`, la fonction que matchigo lit en premier quand il construit un pattern : un **schéma est donc un pattern matchigo**. Il marche dans `m.isMatching`, `m.compile`, `m.matcher():with`, dans les shapes, dans `P.intersection`, `P.anyOf` et `P.select`. Le test `tests/matchigo_test.lua` joue ces cas contre le vrai matchigo en CI.

```lua
local z = require("zigo")
local m = require("matchigo")
local P = m.P

local User = z.object({ name = z.string():min(1), age = z.integer():min(0) })
local Ping = z.object({ kind = z.literal("ping") })

print(m.isMatching(User, { name = "ann", age = 3 })) --> true
print(m.isMatching(User, { name = "", age = 3 })) --> false

local route = m.compile({
    { with = Ping, handler = "ping" },
    { with = User, handler = function(v) return v.name end },
    { with = z.integer():min(100), handler = "big" },
    { otherwise = "other" },
})
print(route({ kind = "ping" })) --> ping
print(route({ name = "bo", age = 2 })) --> bo
print(route(150)) --> big
print(route("zz")) --> other

local run = m.matcher()
    :with(Ping, function() return "ping" end)
    :with(User, function(v) return v.age >= 18 end, function() return "adult" end)
    :with(User, function(v) return "user:" .. v.name end)
    :otherwise("none")
print(run({ kind = "ping" })) --> ping
print(run({ name = "cy", age = 30 })) --> adult
print(run({ name = "cy", age = 9 })) --> user:cy
print(run(1)) --> none

local pick = m.compile({
    { with = P.select(User), handler = function(sel) return sel.name end },
    { otherwise = "none" },
})
print(pick({ name = "di", age = 4 })) --> di
print(pick({ name = "", age = 4 })) --> none
```

Les nœuds se combinent aussi dans les patterns matchigo :

```lua
local z = require("zigo")
local m = require("matchigo")
local P = m.P

local User = z.object({ name = z.string():min(1), age = z.integer():min(0) })

local pat = { user = User, tag = "x" }
print(m.isMatching(pat, { user = { name = "a", age = 1 }, tag = "x" })) --> true
print(m.isMatching(pat, { user = { name = "a", age = -1 }, tag = "x" })) --> false

local either = P.anyOf(z.string(), z.boolean())
print(m.isMatching(either, false)) --> true
print(m.isMatching(either, 1)) --> false

local both = P.intersection(z.number(), P.gte(10))
print(m.isMatching(both, 11)) --> true
```

Trois points à connaître :

- `P.union` construit un ensemble de valeurs littérales, donc `P.union(z.string(), z.boolean())` ne correspond jamais. Utiliser `P.anyOf` pour combiner des schémas.
- matchigo ne lit que le verdict : avec un schéma impur (`transform`, `default`), le handler reçoit toujours la valeur d'origine. Appeler `schema:parse(v)` dans le handler si la sortie compte.
- zigo a `discriminatedUnion` pour une union validée par étiquette ; utiliser matchigo pour aiguiller une fois la valeur connue comme valide.

```lua
local z = require("zigo")
local m = require("matchigo")
local P = m.P

print(m.isMatching(P.union(z.string(), z.boolean()), "a")) --> false
print(m.isMatching(P.anyOf(z.string(), z.boolean()), "a")) --> true

local Upper = z.string():transform(function(s) return s:upper() end)
local seen
local f = m.compile({
    { with = Upper, handler = function(v) seen = v return "ok" end },
    { otherwise = "no" },
})
print(f("abc")) --> ok
print(seen) --> abc
```

## 18. Performance

Les mesures sont dans [bench/results](../../bench/results/README.fr.md), un fichier par runtime (Lua 5.4 et LuaJIT 2.1 sont publiés), avec la méthode : le schéma de référence, l'imbrication, les grands tableaux et une union discriminée de 10 variantes, chacun face au code écrit à la main. `bench/run.lua` les reproduit et `bench/budgets.lua` fait respecter les budgets des schémas purs : entrée valide à P50 dans 1,2× d'un code équivalent écrit à la main, et aucune allocation sur le chemin valide. Les chiffres absolus dépendent de la machine ; ne pas se fier à ceux d'un runner CI partagé.

Trois habitudes qui comptent plus que n'importe quelle option : construire les schémas une fois au chargement, préférer les schémas purs sur les chemins chauds (`:strict()` plutôt que `:strip()`), et utiliser `is` quand l'erreur n'est pas nécessaire.

---

Design et architecture : [DESIGN.md](../DESIGN.md) · [Changelog](../../CHANGELOG.md) (anglais) · [Licence](../../LICENSE)

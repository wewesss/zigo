# zigo — design & architecture

> Validateur de données façon Zod pour Lua 5.1 → 5.4 et LuaJIT.
> Famille : [matchigo](https://github.com/wewesss/matchigo-lua) (pattern matching) · classigo (classes CSS) · **zigo** (validation).
> Licence MIT · zéro dépendance · bundle single-file comme matchigo-lua.

---

## 1. Périmètre

**zigo garde le côté Lua de chaque frontière.** Tout ce qui entre dans Lua (résultat SQL, retour FFI C/Rust/ASM/Lurlang, paquet réseau, config, input utilisateur) passe par un schéma qui le vérifie et rend une valeur sûre.

Dans le périmètre v1 :
- API fluente immuable façon Zod (`z.object`, `z.string():min(3)`, `:optional()`…)
- `parse` / `safeParse` / `is`
- erreurs structurées avec chemin, déterministes
- types « frontière » que Lua représente mal : entiers 64 bits, `cdata` LuaJIT, sentinelles NULL, `bytes` vs `utf8`, `userdata`
- limites anti-abus réseau (profondeur, nombre de clés, nombre d'erreurs)
- interop directe avec matchigo (un schéma *est* un pattern)

Hors périmètre (explicitement) :
- pas d'IDL, pas de génération de code vers d'autres langages, pas de format binaire
- pas de validation côté Rust/C : chaque langage valide ce qu'il reçoit
- pas de `z.infer` complet : les annotations LuaCATS resteront approximatives, on ne le promet pas

---

## 2. Principes non négociables

1. **Parse, don't validate** : `parse` rend une valeur ; le code en aval ne revérifie rien.
2. **Hot path valide = 0 allocation** sur un schéma « pur » (sans transform/default/strip). Assertion dans les tests, pas une intention.
3. **Erreurs déterministes** : même entrée → mêmes erreurs dans le même ordre. Jamais de `pairs` dans un chemin qui produit des erreurs ; les clés d'objet sont triées à la construction.
4. **Schémas immuables** : chaque modificateur rend un nouveau nœud. Un schéma peut être partagé entre coroutines/threads de jeu sans risque.
5. **Compilé une fois** : la compilation est paresseuse (au 1er usage) puis cachée sur le nœud. Construire un schéma dans un handler est un bug de l'utilisateur, documenté comme tel.
6. **Aucune coercition implicite** : `"12"` n'est pas un entier. Coercition uniquement via `z.coerce.*`.
7. **Chaque optimisation est justifiée par un bench** dans `bench/results/`. Pas de bench, pas de merge.

---

## 3. Architecture

```
 API fluente (z.*)          ──▶  nœud immuable = descripteur (données pures)
                                   │  flags calculés à la construction :
                                   │  pure, hasTransform, hasDefault, maxDepth…
                                   ▼
                     ┌──── compilateurs (paresseux, cachés sur le nœud) ────┐
                     │                                                       │
          _test (bool)                    _check (diagnostic)        _parse (sortie)
   codegen via load() ─ hot path    closures, path en pile,    seulement si nœud impur :
   fallback closures si load()      errs créé paresseusement   copie + transform/default
   indisponible (sandbox)           exécuté SEULEMENT en échec
                     │                                                       │
                     └───────────────────────────┬───────────────────────────┘
                                                 ▼
                     safeParse(v) :  if _test(v) then
                                        return true, (pure and v or _parse(v))
                                     end
                                     return false, nil, _check(v, path, 0, nil)
```

### Pourquoi deux passes (test puis check)

Le cas courant est l'entrée valide. On le traite avec la fonction la plus rapide possible (booléenne, sans chemin, sans table d'erreurs). Le walker de diagnostic ne tourne qu'en cas d'échec. Les mesures (§6) montrent que c'est le bon compromis : le single-pass est meilleur sur l'invalide mais plus lent sur le valide.

Pré-filtre dans `_check` : avant de descendre dans un enfant conteneur (`object`, `array`, `tuple`, `record`, `union`, `discriminatedUnion`), le walker lui applique son `_test` compilé (codegen si actif, `_testD` avec la profondeur courante si les limites sont suivies) et saute l'enfant s'il passe, puisqu'un `_test` vrai garantit zéro issue. Seules les branches en échec sont parcourues par les closures de diagnostic ; l'ordre, les chemins, le plafond `maxErrors` et `abortEarly` ne changent pas. Le pré-filtre est désactivé pour les sous-arbres qui contiennent un `lazy` ou un `:limits()` propre (leur `_test` repart de la profondeur 0 alors que `_check` reçoit la profondeur de l'appelant), et quand `profondeur + maxDepth de l'enfant` dépasse la limite d'un `_test` non suivi. Les nœuds impurs gardent leur chemin (les callbacks ne s'exécutent qu'une fois). `tests/fuzz_test.lua` compare les issues avec et sans pré-filtre sur une graine fixe.

### Pourquoi codegen pour `_test`

Mesure clé du prototype : **en LuaJIT, des closures composées sont ~10× plus lentes qu'un if-chain écrit à la main** (464 ns contre 42 ns). La boucle `for i = 1, n do tests[i](v[keys[i]]) end` est un site d'appel polymorphe que le JIT ne spécialise pas. Le code généré (une seule fonction plate, champs déroulés) **égale voire bat le code écrit à la main** (33 ns). C'est aussi l'approche de `api7/jsonschema`.

Règles du codegen :
- les clés et les littéraux passent **toujours** par `%q` ou par la table de constantes `K[...]`. Jamais de concaténation brute (risque d'injection de code via un nom de clé)
- les fonctions utilisateur (`refine`, `transform`) ne sont pas inlinées : elles passent par `K[i]`
- fallback automatique vers les closures si `load` / `loadstring` est absent ou interdit (sandboxes de jeu)
- les unions discriminées génèrent un dispatch par table de hachage sur la clé discriminante (même idée que le fast-path de matchigo)

### Pourquoi `_check` reste en closures

C'est un chemin rare : il ne justifie pas un second générateur de code à maintenir. Le chemin courant est une **pile mutable partagée** (push/pop, aucune allocation), copiée uniquement quand une erreur est émise.

### Arborescence

```
zigo/
  init.lua            -- API publique z.*
  node.lua            -- constructeur de nœud, immutabilité, flags, cache de compilation
  errors.lua          -- codes, format, flatten, table de messages remplaçable
  limits.lua          -- limites réseau (maxDepth, maxKeys, maxErrors, abortEarly)
  null.lua            -- sentinelle NULL par défaut et registre des sentinelles
  types/              -- un fichier par famille : primitives (string, number, integer, boolean,
                      -- literal, enum, any, unknown, never), fixed (u8…i32), int64,
                      -- boundary (bytes, utf8), native (null, func, userdata, instanceOf,
                      -- cdata, notNullPtr), array, object, tuple, record, union, lazy, coerce
  compile/
    context.lua       -- contexte de _parse (ctx:addIssue)
    codegen.lua       -- _test via load()
    closures.lua      -- _test fallback + _check
    parse.lua         -- _parse (copie, transform, default, strip)
  util/compat.lua     -- 5.1/5.2/5.3/5.4/JIT (math.type, load, unpack, int64, UTF-8)
types/                -- annotations LuaCATS (zigo.d.lua)
docs/                 -- DESIGN.md, en/guide.md, fr/guide.md
tests/  bench/  build.lua  dist/
```

---

## 4. API publique

```lua
local z = require("zigo")

local User = z.object({
    id      = z.int64(),                         -- number entier ≤ 2^53, cdata int64 (LuaJIT)
    name    = z.utf8():min(3):max(32),           -- longueur en caractères, UTF-8 vérifié
    age     = z.integer():between(0, 150):optional(),
    role    = z.enum({ "admin", "user", "guest" }),
    tags    = z.array(z.string():max(16)):max(10):default({}),
    address = z.object({ city = z.string():min(1), zip = z.string():len(5) }),
}):strict()

local ok, user, err = User:safeParse(input)   -- ne lève jamais
local user          = User:parse(input)       -- lève un objet erreur (__tostring)
local bool          = User:is(input)          -- _test seul, aucune allocation
```

### Retours
- `safeParse` → `ok, value, err` (tuple, pas de table résultat ; aucune allocation en succès)
- `err.issues` = liste de `{ path = {"address","zip"}, code = "too_small", expected = 5, got = 1, message? }`
- `err:flatten()`, `err:format(locale?)` ; les messages lisibles sont produits **à la demande**, jamais pendant la validation

### Primitives et modificateurs
`string`, `utf8`, `bytes`, `number`, `integer`, `int64`, `boolean`, `func`, `literal`, `enum`, `any`, `unknown`, `never`, `null(sentinel)`
`object`, `array`, `tuple`, `record(k, v)`, `union`, `discriminatedUnion(key, …)`, `lazy(fn)`
`:optional()`, `:nullable()` (accepte la sentinelle NULL configurée), `:default(x | fn)`, `:refine(fn, opts)`, `:transform(fn)`, `:pipe(schema)`
Hors 1.0 : `z.string():email()`, `intersection` et `:describe(txt)` ne sont pas livrés.
`z.coerce.integer()`, `z.coerce.number()`, `z.coerce.boolean()`, `z.coerce.string()`

### Objets : clés inconnues
| Mode | Effet | Coût |
|---|---|---|
| `passthrough` (**défaut**) | les clés inconnues restent | 0 copie |
| `:strict()` | les clés inconnues sont une erreur | 0 copie, une itération en plus |
| `:strip()` | les clés inconnues sont retirées | **copie de la table** (nœud impur) |

Écart volontaire avec Zod, dont le défaut est `strip` : en Lua, `strip` impose une copie à chaque appel et casserait la règle 0 allocation. Recommandation documentée : `:strict()` pour tout ce qui vient du réseau.

### Types frontière (le différenciateur)
| Frontière | Primitive |
|---|---|
| SQL | `z.null(cjson.null)` / `z.null(ngx.null)`, `z.int64()` (accepte string numérique avec `{ fromString = true }`), `:nullable()` distinct de `:optional()` |
| FFI C / Rust / ASM / Lurlang | `z.cdata("struct foo*")` (`ffi.istype`), `z.notNullPtr("struct foo*")` (ctype obligatoire, pointeur non NULL), `z.int64()`, `z.u8()…z.i32()…z.u32()` (bornes vérifiées), `z.bytes():len(n)` |
| Réseau | `z.bytes()` / `z.utf8()`, options globales `{ maxDepth, maxKeys, maxErrors, abortEarly }` |
| Lua | `z.integer()` (via `math.type` en 5.3+, `v % 1 == 0` ailleurs), `z.array()` refuse les trous, `z.userdata(mt)`, `z.instanceOf(mt)` |

### Relation avec matchigo : interop oui, dépendance non

Mesuré (§6, union et schéma de référence) : utiliser matchigo comme moteur interne **ne fait gagner du runtime dans aucun cas**.
- Comme moteur de `_test` : de 2,2× plus lent (Lua 5.4) à 6,7× plus lent (LuaJIT) que le codegen.
- Comme moteur d'union (une règle par variante) : de 5× (LuaJIT) à 13× (Lua 5.4) plus lent que le codegen + table de hachage, parce que le fast-path O(1) de matchigo ne s'applique qu'aux valeurs littérales, pas à une clé discriminante dans un objet.
- Même en utilisant le fast-path littéral sur `v.kind` : jamais mieux qu'une simple table `map[v.kind]`, et 1,7× plus lent en LuaJIT et en 5.4 (un appel de fonction en plus).
- Coût : le bundle matchigo fait 71 Ko et 2 243 lignes (DSL, BigInt, Map, Set), pour rien d'utile au validateur.

Décision : **zigo est autonome, sans aucune dépendance**. Pas de variantes « lite » et « avec matchigo » : un seul bundle. Ce qu'on reprend de matchigo, ce sont les *idées* (prédicats construits une fois, fast-path par hachage, framework de bench), pas le code.

### Interop matchigo
`buildTest` de matchigo-lua lit `pat._test` avant tout le reste : **un nœud zigo qui expose `_test` est un pattern matchigo, sans dépendance**. `_test` est fourni via `__index` paresseux (compile au premier accès, puis `rawset`), pour que matchigo capture directement la fonction finale.
Vérifié par `tests/matchigo_test.lua`, joué en CI contre le vrai matchigo-lua (chargé depuis `MATCHIGO_PATH`, test sauté sans ce chemin) : `m.isMatching`, `m.compile` (fast-path littéral compris), `m.matcher():with` avec garde, `P.select` avec ou sans label, et un nœud zigo dans une shape, `P.intersection` ou `P.anyOf`. Deux points à retenir : `P.union` construit un ensemble de valeurs littérales, donc `P.union(z.string(), z.boolean())` ne correspond jamais et il faut `P.anyOf` pour combiner des schémas ; matchigo ne lit que le verdict de `_test`, donc avec un schéma impur le handler reçoit la valeur d'origine.

```lua
m.matcher()
    :with(LoginPacket, function(p) ... end)
    :with(ChatPacket,  function(p) ... end)
    :otherwise(reject)
```

---

## 5. Pièges Lua à couvrir (chacun = au moins un test)

- `NaN`, `±inf`, `-0` ; entiers > 2^53 en 5.1/LuaJIT (perte de précision silencieuse)
- `1LL` / `1ULL` LuaJIT : `type()` renvoie `"cdata"`, pas `"number"`
- `3.0` en 5.3+ : `math.type` → `"float"`. Décision : `integer()` accepte les floats à valeur entière, option `{ strict = true }` pour les refuser
- tableaux à trous : `#t` n'est pas fiable, `array()` vérifie avec un `next()` borné
- `{}` : tableau vide ou objet vide ? Les deux schémas l'acceptent
- tables avec métatable (`__index`, `__len`) : la validation utilise `rawget`/`rawlen` par défaut, option `{ meta = true }` pour l'accès normal
- cycles dans les données : protégés par `maxDepth`
- `#s` compte des octets, pas des caractères : `utf8():min()` compte des caractères
- noms de clés hostiles dans le codegen : `"]] os.exit() --"`, `"\0"`, très longues chaînes
- NULL sous LuaJIT : un cdata pointeur NULL vérifie `== nil`. `:optional()` sur les autres types et les contrôles de trous des tableaux/tuples le traitent donc comme absent ; seuls `z.cdata` et `z.notNullPtr` (qui utilisent `rawequal`) le distinguent. Non corrigé, pour garder le chemin valide des schémas existants sans `rawequal` supplémentaire
- registre des sentinelles NULL : il est global. Une sentinelle table/userdata/cdata posée par `z.config` ou `z.null(s)` / `:nullable(s)` est nommée « null » dans les messages et le `got` de tous les schémas ; ne pas prendre un objet partagé comme `io.stdout` pour sentinelle

---

## 6. Performance

### Mesures du prototype (référence de départ)

Schéma de référence : objet à 7 champs, 1 objet imbriqué, 1 tableau, 1 enum, 1 champ optionnel. 64 entrées variées (anti-repliement par le JIT). P99 = P99 **par lot** (lots de 200 appels en PUC, de 50 en LuaJIT).

| Runtime | Variante | Valide P50 | Valide P99 | Invalide P50 | Invalide P99 | Octets/appel (inv.) |
|---|---|---:|---:|---:|---:|---:|
| LuaJIT 2.1 | if-chain main | 42 ns | 62 ns | — | — | — |
| LuaJIT 2.1 | matchigo-lua isMatching | 222 ns | 678 ns | — | — | — |
| LuaJIT 2.1 | two-pass closures | 464 ns | 1032 ns | 936 ns | 3903 ns | 486 |
| LuaJIT 2.1 | single-pass | 357 ns | 855 ns | 564 ns | 3073 ns | 398 |
| LuaJIT 2.1 | **codegen two-pass** | **33 ns** | **51 ns** | 464 ns | 3120 ns | 486 |
| Lua 5.4 | if-chain main | 715 ns | 1010 ns | — | — | — |
| Lua 5.4 | **codegen two-pass** | **550 ns** | **685 ns** | 2195 ns | 4120 ns | 456 |
| Lua 5.4 | two-pass closures | 930 ns | 1080 ns | 2370 ns | 4565 ns | 456 |
| Lua 5.1 | if-chain main | 680 ns | 1140 ns | — | — | — |
| Lua 5.1 | **codegen two-pass** | **705 ns** | **1215 ns** | 2965 ns | 6720 ns | 572 |
| Lua 5.1 | two-pass closures | 1290 ns | 2295 ns | 3530 ns | 7610 ns | 572 |

Cold path (construction + compilation + 1er appel) :

| Runtime | Closures P50 / P99 | Codegen P50 / P99 |
|---|---:|---:|
| LuaJIT 2.1 | 5.7 / 93 µs | 28.6 / 169 µs |
| Lua 5.4 | 13 / 48 µs | 61 / 114 µs |
| Lua 5.1 | 23 / 195 µs | 79 / 321 µs |

Union discriminée, 10 variantes sur `kind` (`bench/union.lua`), P50 / P99 en ns, entrées valides :

| Variante | Lua 5.1 | Lua 5.4 | LuaJIT 2.1 |
|---|---:|---:|---:|
| if/elseif main | 230 / 525 | 165 / 290 | 18 / 25 |
| closures, essai séquentiel | 560 / 1065 | 400 / 680 | 65 / 222 |
| **codegen + `map[v.kind]` (autonome)** | **200 / 415** | **140 / 240** | **33 / 41** |
| matchigo `compile`, une règle par variante | 1420 / 3780 | 1815 / 3735 | 166 / 835 |
| matchigo fast-path sur `v.kind` + codegen | 230 / 355 | 245 / 440 | 56 / 162 |

0 octet/appel partout (< 1 en LuaJIT, bruit du timer FFI).

Conclusions :
0. **`discriminatedUnion` = table de hachage sur la clé + test codegen par variante.** C'est la seule forme qui reste au niveau du code écrit à la main sur les trois runtimes, en P50 comme en P99.
1. **Codegen pour `_test`**, closures en fallback. Sur LuaJIT c'est le facteur ×14 ; sur PUC, ×1,7 à ×1,8.
2. **Two-pass** : le valide est servi par la fonction la plus rapide ; l'invalide coûte un walk de plus, acceptable.
3. **Le chemin invalide alloue ~400–570 octets par appel** (tables d'erreurs et chemins). Sur le réseau, un attaquant contrôle ce chemin : `abortEarly` et `maxErrors` sont obligatoires en v1, pas des options futures.
4. **Cold path : 30–80 µs en P50, jusqu'à 320 µs en P99** avec codegen. D'où la compilation paresseuse et cachée, et la règle « jamais dans un handler ». Piste v2 : compilation par paliers (closures d'abord, codegen après N appels) si le cold path pose problème au démarrage.
5. Seul cas où matchigo bat zigo : le **fallback closures sous LuaJIT** (222 ns contre 464 ns). C'est à corriger dans les closures de zigo (moins de niveaux d'appel, champs déroulés pour les petits objets), pas une raison de dépendre de matchigo.
6. Effet de bord utile : matchigo-lua a le même plafond en LuaJIT (222 ns contre 42 ns). Le codegen de `_test` pourrait lui être appliqué aussi.

### Budgets v1 (bloquants en CI bench)
- Schéma de référence, entrée valide : P50 ≤ 1,2× le if-chain écrit à la main, sur chaque runtime
- 0 octet/appel sur entrée valide pour un schéma pur (moyenne < 0,5 sur 20 000 appels, bruit JIT compris)
- `abortEarly` sur invalide : ≤ 1 table d'erreur allouée
- Aucune régression > 10 % en P50 ou > 25 % en P99 sans justification dans le commit

---

## 7. Benchmarks — méthodologie

Reprendre `bench/framework.lua` de matchigo-lua (sink anti-élimination, entrées variées, sidecar `.stats`, agrégation en matrice) et ajouter :

- **Timer** : `ffi clock_gettime(CLOCK_MONOTONIC)` en LuaJIT ; `os.clock` en PUC (résolution ~1 µs, donc mesure **par lots**). Le P99 publié est un P99 par lot ; l'indiquer dans chaque tableau.
- **Hot** : warmup 5 000 appels (les traces JIT sont formées), puis ≥ 3 000 échantillons. Rapporter P50, P90, P99, max.
- **Cold** : construction + compilation + 1er appel, répété ≥ 2 000 fois avec un schéma neuf à chaque fois. Rapporter P50 et P99 séparément pour la construction et pour la compilation.
- **GC** : octets/appel mesurés GC arrêté ; P99 mesuré GC actif (c'est lui qui fait le P99 en production). Variante `collectgarbage("generational")` en 5.4.
- **Matrice** : 5.1, 5.2, 5.3, 5.4, LuaJIT 2.1 (et LuaJIT `-joff` pour simuler un JIT désactivé).
- **Comparaisons** : if-chain main (borne basse), matchigo-lua, tableshape, chotto, api7/jsonschema (codegen aussi : le vrai concurrent sur la perf).

Scénarios :
| # | Scénario | Ce qu'il mesure |
|---|---|---|
| S1 | primitive seule (`string():min(3)`) | coût fixe d'un appel |
| S2 | schéma de référence | cas typique |
| S3 | imbrication profondeur 8 | coût du chemin et de la récursion |
| S4 | tableau de 1 000 objets | débit, boucles JIT |
| S5 | union discriminée, 10 variantes | dispatch par hachage contre essai séquentiel |
| S6 | invalide tôt / invalide tard | coût du court-circuit |
| S7 | payload adversarial (10 000 erreurs potentielles) | `maxErrors`, `abortEarly`, allocations |
| S8 | schéma impur (`default`, `transform`, `strip`) | coût de la copie |
| S9 | 200 schémas définis au démarrage, 10 utilisés | intérêt de la compilation paresseuse |

---

## 8. Tests

- **Unitaires par type** : valide / invalide / limites (§5) pour chaque primitive et modificateur
- **Équivalence (property / fuzz, graine fixe)** : pour des schémas et données générés aléatoirement, `codegen._test(x) == closures._test(x) == (_check(x) == nil)`. C'est **le** test critique, puisqu'il y a deux implémentations d'une même sémantique.
- **Déterminisme** : mêmes erreurs, même ordre, sur 100 exécutions et sur tous les runtimes
- **Zéro allocation** : assertion GC arrêté sur le chemin valide des schémas purs
- **Immutabilité** : un modificateur ne change jamais le nœud source
- **Sécurité du codegen** : clés hostiles, littéraux avec `]]`, `\0`, chaînes de 1 Mo
- **Fallback** : suite complète relancée avec `load` désactivé
- **Interop matchigo** : `m.isMatching`, `m.compile` et `m.matcher():with(schema, …)`
- **Bundle** : `lua tests/run.lua dist` comme matchigo-lua
- CI : matrice 5.1 → 5.4 + LuaJIT, tests + bench rapide (`--fast`) à chaque PR

---

## 9. Roadmap

| Phase | Contenu | Sortie | État |
|---|---|---|---|
| P0 | nœuds immuables, primitives, `object`/`array`/`optional`, two-pass closures, format d'erreur, tests unitaires + déterminisme | `safeParse` fonctionnel | livrée |
| P1 | codegen `_test` + fallback, test d'équivalence fuzz, bench S1–S4 + matrice | budgets §6 tenus | livrée |
| P2 | `default`, `transform`, `refine`, `pipe`, `coerce`, `strip`, `_parse` | schémas impurs | livrée |
| P3 | `union`, `discriminatedUnion`, `tuple`, `record`, `lazy`, limites réseau, S5–S9 | prêt pour le réseau | livrée |
| P4 | types frontière : `int64`, `cdata`, `null(sentinel)`, `bytes`/`utf8`, entiers à taille fixe | le différenciateur | livrée |
| P5 | LuaCATS `*.d.lua`, bundle, docs FR/EN, rockspec, interop matchigo documentée | release 1.0 | livrée (1.0.0, 2026-11-09) |

---

## 10. Décisions ouvertes

- [x] Nom : `zigo` (décidé le 2026-11-08, remplace validigo)
- [x] Namespace : `z` (décidé le 2026-11-08, clin d'œil à Zod ; une lettre par lib, `m`/`P` pour matchigo)
- [x] Nom `zigo` libre sur LuaRocks (vérifié le 2026-11-09)
- [x] Défaut des clés inconnues : `passthrough`, `:strict()` à la demande (2026-11-08)
- [x] `integer()` accepte `3.0` en 5.3+ par défaut, `{ strict = true }` pour refuser (2026-11-08)
- [x] Messages d'erreur : codes stables + anglais intégré, table de messages remplaçable (2026-11-08)
- [x] Budgets §6 : bloquants en local (`bench/budgets.lua`), informatifs en CI (2026-11-08)
- [x] Schémas impurs (P2) : passe unique `_parse` (validation + sortie dans l'ordre de la chaîne), `default` rendu tel quel ou `fn()`, échec de transform via `ctx:addIssue`, `coerce` strict, `strip`/`strict` le dernier gagne, `_parse` en closures, S8 informatif (2026-11-08)
- [x] P3 : `union` première variante gagnante + `invalid_union` (issues de chaque variante), `discriminatedUnion` par hachage sans repli + `invalid_union_discriminator`, `tuple` strict + `:rest()`, `record` trié dans `_check` seulement, limites `z.config` + `:limits()` actives par défaut (64 / 10000 / 100), `maxKeys` sur les tables déjà parcourues, `lazy` appelé via `K` et borné par `maxDepth` ; jalons P3a puis P3b (2026-11-08)
- [ ] Compilation par paliers en v2 : seulement si S9 montre un vrai problème

---

## 11. Règles pour les sessions de travail (agent)

- Lancer `tests/run.lua` sur **tous** les runtimes installés avant chaque commit ; un échec sur un seul runtime bloque
- Toute modification de `compile/` s'accompagne d'un bench avant/après, collé dans le message de commit
- Ne jamais introduire `pairs` dans un chemin qui produit des erreurs ou de l'ordre observable
- Ne jamais construire de code Lua par concaténation de valeurs utilisateur : passer par `%q` ou `K[...]`
- Le prototype de référence (`bench/proto.lua`) reste dans le dépôt comme témoin de régression

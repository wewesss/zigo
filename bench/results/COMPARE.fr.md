# zigo face aux autres validateurs Lua

[English](./COMPARE.md) · Français

`bench/compare.lua` mesure zigo à côté de trois bibliothèques de validation Lua tierces, sur les mêmes jeux de données. Cette page décrit la méthode, les versions épinglées, l'installation des bibliothèques et ce que chacune peut ou ne peut pas exprimer. **Aucun chiffre mesuré n'est commité pour l'instant** : ils seront publiés après l'optimisation du cœur, à partir d'un run complet. Un run écrit localement `bench/results/compare-<runtime>.md`, fichier ignoré par git.

## Ce qui est comparé

Les jeux de données viennent de `bench/fixtures.lua`, ceux de `bench/core.lua` :

| id | jeu de données |
|---|---|
| S1 | `string():min(3)` |
| S2 | schéma de référence : 7 champs, objet imbriqué, tableau, enum, entier optionnel borné |
| S3 | imbrication sur 8 niveaux |
| S4 | tableau de 1000 objets |
| S5 | union discriminée, 10 variantes |

Pour chaque jeu, deux ensembles d'entrées sont mesurés, en cyclant sur 64 entrées (8 pour S4) afin d'empêcher le repliement de constantes sous LuaJIT :

- entrées valides ;
- entrées invalides, dont le premier champ déclaré est invalide (S1 : chaîne trop courte, S2 : `id` hors bornes, S3 : `n` externe non entier, S4 : première ligne invalide, S5 : discriminant inconnu).

Lignes, dans cet ordre :

1. if-chain écrit à la main (la référence, la même que `bench/core.lua`) ;
2. zigo `:is` ;
3. zigo `:safeParse` ;
4. l'appel de vérification public de chaque bibliothèque. tableshape a deux lignes : interprété (`check_value` sur le type) et compilé (`tableshape.codegen`, puis `check_value`).

Le chronométrage, la gestion du GC et le suivi des allocations sont ceux de `bench/framework.lua` (lots calibrés, P50 et P99 sur les échantillons, octets alloués par appel).

## Contrôle d'acceptation

Avant la mesure, chaque ligne est exécutée sur toutes les entrées valides, sur la liste d'invalides du jeu et sur l'ensemble « premier champ invalide ». La référence écrite à la main sert d'oracle : une ligne qui classe une entrée autrement est signalée sur la console, dans la colonne `agrees with baseline`, dans la colonne `guarantees` (préfixe `MISMATCH`) et dans une section finale « Acceptance mismatches ». Un écart n'arrête pas le run et la ligne est quand même mesurée, mais la comparaison n'est pas à armes égales : cette bibliothèque n'applique pas toutes les garanties du jeu.

## Réserves sur les garanties

Les schémas expriment les mêmes garanties que zigo partout où la bibliothèque le permet : longueurs de chaînes, bornes d'entiers, enums, champs optionnels, objets imbriqués acceptant les clés inconnues (le défaut de zigo), tableaux d'une longueur donnée.

- **Trous et clés parasites dans les tableaux.** Les tableaux zigo refusent les trous et les clés hors séquence, comme la référence. tableshape parcourt les tableaux avec `ipairs` et ne le vérifie pas ; lshape accepte certaines de ces entrées selon la borne de table du runtime. Les deux apparaissent en lignes `MISMATCH` pour S2 et S4. lua-resty-ljsonschema les refuse (il classe une table Lua en tableau d'après la forme de ses clés).
- **Entiers.** tableshape n'a pas de type entier borné ; les schémas utilisent `types.range` plus un prédicat `types.custom` (`v % 1 == 0`). lshape et lua-resty-ljsonschema ont des types entiers natifs.
- **Longueur des chaînes.** lua-resty-ljsonschema compte des caractères UTF-8, les autres des octets. Les jeux sont en ASCII, les résultats concordent.
- **Union discriminée (S5).** Seul lshape en a une native. tableshape (`one_of`) et lua-resty-ljsonschema (`anyOf`) essaient les variantes dans l'ordre, comme le fait un validateur JSON Schema. C'est une différence de ce que propose la bibliothèque, pas un défaut du schéma.
- **Rapport d'erreurs.** Les lignes mesurent l'appel de vérification normal de la bibliothèque. Les lignes d'entrées invalides incluent donc ce que la bibliothèque fait pour construire son résultat d'échec (zigo `:safeParse` construit des issues, tableshape construit un message).
- **Runs rapides.** `--fast` utilise 5 échantillons et un échauffement court. Sa sortie est un test de fumée, pas un benchmark.

## Versions épinglées

| bibliothèque | version | source |
|---|---|---|
| tableshape | 2.8.0-1 | `luarocks install tableshape` |
| lua-resty-ljsonschema | 1.2.0-2 (avec net-url 1.2-1) | `luarocks install lua-resty-ljsonschema` |
| lua-cjson | 2.1.0.10-1 (requis par lua-resty-ljsonschema pour son métaschéma) | `luarocks install lua-cjson` |
| lshape | 0.3.0, commit `135946790268d51ebbe6f86507722054a8c6ed69` | `git clone https://github.com/ynishi/lshape` |

Écartées après un test de fumée :

- `jsonschema` (api7) 0.9.13-0 : dépend de `lrexlib-pcre`, un module C qui exige les en-têtes PCRE ; il ne s'est pas installé sur la machine de test (Windows, MinGW). lua-resty-ljsonschema est le fork maintenu qui évite cette dépendance.
- chotto (aiya000, commit `3f1a22eed5c6344344e7df4e2af101ca3de81cbc`) : ni longueur minimale, ni bornes numériques, ni mode strict, donc impossible d'exprimer S1 ou S2.

## Installer les bibliothèques

Les bibliothèques ne sont jamais copiées dans le dépôt. Installez-les dans un dossier temporaire (ici `$TREE`) et pointez le benchmark dessus :

```sh
TREE=/chemin/vers/scratch/rocks
luarocks --tree "$TREE" install tableshape
luarocks --tree "$TREE" install lua-resty-ljsonschema
luarocks --tree "$TREE" install lua-cjson          # module C, demande un compilateur C
git clone https://github.com/ynishi/lshape /chemin/vers/scratch/lshape
git -C /chemin/vers/scratch/lshape checkout 135946790268d51ebbe6f86507722054a8c6ed69
```

`lua-cjson` est compilé pour la version de Lua que cible `luarocks`. Pour LuaJIT, compilez `cjson` contre les en-têtes et la bibliothèque d'import de LuaJIT et gardez ce `cjson.dll` / `cjson.so` dans un dossier distinct, utilisé pour le run LuaJIT seulement. Sans `cjson`, les lignes lua-resty-ljsonschema sont ignorées avec un avertissement.

## Lancer

Compilez zigo, puis pointez le benchmark sur les bibliothèques. `ZIGO_COMPARE_PATH` est ajouté à `package.path` et `ZIGO_COMPARE_CPATH` à `package.cpath` (les deux sont facultatifs, gabarits `?` standard séparés par `;`) :

```sh
lua build.lua

export ZIGO_COMPARE_PATH="$TREE/share/lua/5.4/?.lua;$TREE/share/lua/5.4/?/init.lua;/chemin/vers/scratch/lshape/?.lua;/chemin/vers/scratch/lshape/?/init.lua"
export ZIGO_COMPARE_CPATH="$TREE/lib/lua/5.4/?.so"   # ?.dll sous Windows

lua bench/compare.lua --fast      # run smoke, non autoritatif
lua bench/compare.lua             # run complet
luajit bench/compare.lua          # run complet sous LuaJIT (mettre le cjson compilé pour LuaJIT dans ZIGO_COMPARE_CPATH)
```

Une bibliothèque introuvable est ignorée avec un avertissement et ne fait jamais échouer le run. `bench/run.lua` et `bench/budgets.lua` ne lisent pas ces variables et restent inchangés ; la comparaison ne fait pas partie des budgets de performance.

La sortie va dans `bench/results/compare-<runtime>.md` (`compare-5.4.md`, `compare-luajit-2.1.md`, ...), un fichier par runtime.

# Résultats benchmark zigo

[English](./README.md) · Français

Sortie de `bench/run.lua`, un fichier par runtime : `runtime-<version>.md` (`5.1`, `5.4`, `luajit-2.1`, ...). `.stats/*.lua` contient les sidecars bruts et n'est pas commité.

Scénarios S1-S4 (`bench/core.lua`, données dans `bench/fixtures.lua`) : if-chain écrit à la main, codegen zigo et closures zigo. La référence écrite à la main a les mêmes garanties que le schéma : ses vérifications de tableau refusent aussi les trous et les clés parasites. `bench/budgets.lua` tient S2 à P50 <= 1,2x cette référence et < 0,5 o/appel.

Scénario union : union discriminée de 10 variantes (`bench/union.lua`), qui compare un `if/elseif` écrit à la main (U0), des closures séquentielles (U1), du codegen avec hash sur `kind` (U2), `compile` de matchigo sur des shapes (U3) et le fast-path littéral de matchigo plus codegen (U4).

> [!IMPORTANT]
> Les microbenchmarks à inputs cyclés ne mesurent que l'overhead par appel. Ne vous fiez pas aux chiffres absolus d'un runner CI partagé.

Reproduire depuis la racine du projet :

```sh
lua build.lua
lua bench/run.lua          # run complet
lua bench/run.lua --fast   # run smoke
```

Le scénario union lit matchigo-lua depuis `MATCHIGO_PATH` (défaut `./matchigo-lua`).

# La Gardienne — Chapitre 1 : Le sous-sol

Jeu d'horreur 3D à la première personne, style *escape game* / *Granny*, qui tourne directement dans le navigateur
(ordinateur **et** téléphone). Graphismes réalistes : meubles et objets **photoscannés** (vrais objets numérisés),
matériaux PBR, ombres douces en temps réel, éclairage d'ambiance pré-calculé et post-traitement « caméra » (grain,
vignettage, aberration chromatique). Tous les sons sont générés par code.

## L'histoire

Tu te réveilles à 3 h du matin dans le salon d'un sous-sol. La porte en haut de l'escalier est verrouillée.
Quelque chose dort juste au-dessus… **la Gardienne**. Elle entend tout.

1. Explore le sous-sol et lis la note sur la table basse.
2. La lumière saute : trouve une lampe de poche.
3. Rétablis le courant dans la buanderie… mais le bruit va la réveiller. **Cache-toi** dans le placard sous l'escalier.
4. Trouve les 4 chiffres du code du coffret (canard, cheval, horloge, télé — attention, la télé fait du bruit !).
5. Prends la clé, monte l'escalier et sauve-toi.

Tu as **3 nuits** : si elle t'attrape, tu recommences la nuit suivante en gardant tes objets.

## Contrôles

| Action | Ordinateur | Téléphone |
|---|---|---|
| Se déplacer | W A S D / flèches | joystick (pouce gauche) |
| Regarder | souris | glisser à droite de l'écran |
| Interagir | E ou clic gauche (maintenir si demandé) | bouton main |
| Lampe de poche | F | bouton lampe |
| S'accroupir | C ou Ctrl | bouton accroupi |
| Courir | Maj (bruyant !) | bouton courir (maintenir) |
| Pause | Échap ou P | bouton pause |

Conseil : joue **avec des écouteurs**, dans le noir, et tiens ton téléphone **à l'horizontale**.

## Lancer le jeu

Le jeu est en HTML/JavaScript, sans installation. Il faut seulement le servir avec un petit serveur web local
(les navigateurs bloquent les modules JavaScript ouverts directement depuis un fichier) :

```bash
# depuis le dossier du projet
python3 -m http.server 8080
# puis ouvre http://localhost:8080 dans Chrome, Edge, Firefox ou Safari
```

Ou bien active **GitHub Pages** sur ce dépôt (Settings → Pages → branche) pour y jouer depuis ton téléphone.

Paramètres utiles dans l'adresse : `?quality=low|medium|high|ultra`, `?autostart` (saute le menu), `?debug`.

## Technique

- Moteur : [three.js](https://threejs.org) r170 (WebGL 2), modules ES sans étape de compilation.
- Rendu : tone mapping filmique, GTAO (occlusion ambiante), bloom léger, MSAA, ombres PCF douces,
  environnement pré-calculé (CubeCamera + PMREM) pour la lumière indirecte et les reflets.
- Qualité automatique : *Basse* sur téléphone, *Haute* sur ordinateur, ajustée selon les images par seconde.
- IA de la Gardienne : ouïe (bruit), vue (champ de vision, lumière, accroupi), navigation A*, poursuite, fouille, placard.
- Sons 100 % procéduraux (Web Audio) : pas de pas selon la surface, grincements, berceuse fredonnée, battements de cœur…
- Architecture détaillée : [ARCHITECTURE.md](ARCHITECTURE.md). Crédits des assets (CC0) : [assets/CREDITS.md](assets/CREDITS.md).

```
index.html            page + import map
src/main.js           démarrage
src/core/             boucle de jeu, chargement, entrées, réglages
src/config/layout.js  plan du niveau (toutes les positions)
src/render/           rendu + post-traitement
src/world/            architecture, éclairage, meubles et objets
src/player/           joueur à la première personne
src/game/             interactions, inventaire, scénario et énigmes
src/entity/           la Gardienne (modèle procédural + IA)
src/audio/            moteur audio procédural
src/ui/               menus, HUD, notes, cadenas
assets/               modèles 3D (GLB) et textures PBR
tools/shot.cjs        test automatique + captures d'écran (Playwright)
```

## Pourquoi pas Unreal ou Unity ?

Les gros jeux Steam utilisent souvent Unreal Engine (C++) ou Unity (C#). Ce projet utilise les mêmes techniques de
rendu (PBR, ombres, post-traitement) mais en WebGL, pour qu'il soit jouable immédiatement sur n'importe quel appareil,
sans rien installer. Le plan du niveau et la logique du jeu sont séparés du moteur, ce qui permettrait de le porter
vers Unity ou Unreal plus tard.

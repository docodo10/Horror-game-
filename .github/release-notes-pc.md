## La Gardienne — Chapitre 1 : Le sous-sol (PC Windows)

**Télécharger :** clique sur `LaGardienne-Windows.zip` ci-dessous (dans « Assets »).

1. Décompresse le .zip (clic droit → « Extraire tout »).
2. Double-clique sur `LaGardienne.exe`.
3. Si Windows affiche « Windows a protégé votre ordinateur » : « Informations complémentaires » → « Exécuter quand même » (le jeu n'est pas signé numériquement).

**Dans cette version :** le sous-sol complet (textures 2K salies, taches, usure), la Gardienne et son intelligence, le menu dans la vieille télé, le son 3D, un simple point blanc au centre qui s'allume quand on peut toucher un objet (l'objet regardé s'éclaire aussi), et la **garderie** abandonnée derrière la porte au bas de l'escalier : salle de jeux géante, toboggans sur lesquels on glisse, piscine à balles, tunnel pour se cacher.

**Performance :** la qualité est sur **AUTO** : pendant le chargement, le jeu mesure ta carte graphique sur les scènes les plus lourdes et choisit le meilleur réglage qu'elle tient (plus de changement de qualité en pleine partie). Plein écran exclusif et image nette par défaut (pas de flou, pas de distorsion ; les effets de lentille se réactivent dans Options → page 3).
**Moins de saccades :** les ombres ne sont plus recalculées à chaque image, la garderie n'est plus dessinée à travers le mur du sous-sol, et le chargement prépare à l'avance tout ce qui apparaît plus tard (chaque pièce, chaque objet, la Gardienne) pour éviter les gels quand on tourne la tête ou qu'on entre dans un nouvel endroit. Le chargement est un peu plus long.
**F3** affiche le compteur : images/seconde, pire image, temps CPU / GPU, carte graphique, résolution. Si ça saccade encore, essaie `LaGardienne - DirectX 12.bat` (souvent plus fluide sur AMD).

Écran noir ou plantage : lance `LaGardienne - DirectX 12.bat`. PC lent : `LaGardienne - mode compatibilite.bat`.

Configuration conseillée : Windows 10/11 64 bits, carte graphique compatible Vulkan ou DirectX 12.

Moteur Godot 4.5 · textures et modèles Poly Haven / ambientCG (CC0) · sons Red Library (CC0).

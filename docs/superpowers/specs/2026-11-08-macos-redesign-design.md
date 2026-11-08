# Refonte visuelle de l'app macOS — identité commune avec Linux/Windows

Date : 2026-11-08
Statut : relu (builder check fait), en attente de validation utilisateur

## Intention

L'app macOS (Swift/AppKit, `Sources/ColimaBar`) « ne fait pas Mac / pas jolie ».
La version Linux/Windows (Tauri, `tauri/src`) a une interface soignée, et c'est
elle que montre le banner GitHub (`docs/banner.png`) sous l'étiquette
« macOS native ». Aujourd'hui l'app Mac réelle ne ressemble pas à ce qu'on
promet.

Objectif : **une seule identité visuelle pour les trois plateformes**, avec une
app Mac qui reste native (Swift) et se comporte en vraie app macOS.

Référence visuelle : `docs/banner.png`, `docs/desktop-compose.png`,
`docs/desktop-containers-dark.png`, `docs/desktop-logs.png`, et le code
`tauri/src/styles.css` + `tauri/src/app.js`. Maquettes du brainstorming :
`.superpowers/brainstorm/30761-1794133029/content/` (layout, menubar, darkmode).

## Objectifs

1. Fenêtre Dashboard Mac reprenant l'identité Tauri : en-tête indigo, mêmes
   couleurs, mêmes badges, même tableau groupé par stack, même panneau de détail.
2. Navigation par **barre latérale à gauche** (choix validé), pas d'onglets.
3. Remplacer le menu déroulant de la barre de statut par un **mini-panneau**
   (popover) aux couleurs de la marque.
4. **Mode sombre automatique** qui suit macOS.
5. Ne perdre **aucune** fonctionnalité Mac existante.

## Non-objectifs

- Pas de changement dans `ColimaBarCore` au-delà de ce que l'UI exige, sauf
  les trois actions de parité Tauri listées plus bas (Remove, Prune images,
  Inspect) et la taille disque. Pas d'autre nouvelle fonctionnalité métier.
- Pas de modification de l'app Tauri.
- Pas de migration de l'app Mac vers Tauri / WebView.
- Pas de nouvelle langue : on garde FR/EN via `L.t(fr, en)`.

## Anti-objectifs (échec même si « ça marche »)

- Une interface qui a l'air d'une page web dans une fenêtre : sélection,
  défilement, clavier, menus contextuels, redimensionnement doivent se comporter
  comme une app Mac.
- Mode sombre cassé (texte illisible, fonds blancs résiduels, couleurs codées
  en dur qui ne basculent pas).
- Couleurs ou badges qui divergent de la version Tauri.
- Une fonctionnalité du menu ou du Dashboard actuel qui disparaît.

## Contraintes

- Swift Package Manager, pas de projet Xcode. `swift build`, `make install`.
- Cible macOS 13 (`Package.swift`) : SwiftUI autorisé, mais seulement les API
  macOS 13 (ex. `NavigationSplitView` OK, `@Observable` non → `ObservableObject`).
- Aucune dépendance externe.
- Les tests existants (`swift run ColimaBarTests` / `make test`) doivent passer.
- L'app reste une app de barre de statut (pas d'icône Dock permanente, comme
  aujourd'hui).

## Ce qui a été décidé

### Choix techniques
- **Swift natif conservé** (option A). La nouvelle fenêtre Dashboard et le
  mini-panneau sont écrits en **SwiftUI**, hébergés dans AppKit
  (`NSHostingController` / `NSHostingView`). `AppDelegate`, `ColimaManager` et
  la boucle de polling ne changent pas de rôle.

### Jetons de design (source unique côté Mac)
- Les couleurs reprennent **exactement** `tauri/src/styles.css`, en clair **et**
  en sombre (bloc `@media (prefers-color-scheme: dark)`) : `--indigo #3B4CCA`,
  `--navy #121A4A`, `--teal`, `--orange`, `--bg`, `--surface`, `--surface-2`,
  `--border`, `--text`, `--text-2`, `--text-3`, `--accent`, `--accent-soft`,
  `--row-hover`, `--row-selected`, `--green/-soft`, `--amber/-soft`,
  `--red/-soft`, rayon 10 px.
- Ces jetons vivent dans `Theme` (déjà présent, `Sources/ColimaBar/Theme.swift`)
  et sont résolus dynamiquement clair/sombre ; aucune vue n'utilise de couleur
  codée en dur en dehors de `Theme`.
- Police : police système (SF Pro) ; police mono système pour IDs, ports, logs.
- Icônes : SF Symbols.

### Fenêtre Dashboard
- **En-tête** pleine largeur, dégradé indigo → navy, identique en clair et en
  sombre : logo lama, « Colima » + « Bar » en dégradé teal → orange, ligne
  « profil · CPU · RAM · disque », pastille d'état (« Colima · Running » etc.),
  jauges CPU et RAM avec valeurs, boutons Stop/Start Colima, Rafraîchir,
  Réglages (roue dentée).
- **Barre latérale** sous l'en-tête, deux groupes :
  - *Docker* : Compose, Containers, Images, Volumes, Networks (avec compteurs
    comme sur Tauri : Compose 2, Containers 8).
  - *Colima* : Logs, Snapshots.
- **Roue dentée** → Réglages (contenu actuel de « Settings » et du sous-menu
  « Instance » : changement de profil, config CPU/RAM/disque, langue,
  démarrage auto…) + « À propos » + « Quitter ».
- **Compose / Containers** : reprennent la vue Tauri — recherche, boutons
  « Open Portainer » et « Prune Docker… », tableau Name / Image / Status /
  Ports / CPU / RAM, lignes de stack repliables avec résumé (« 2 containers »,
  badge « All running » / « 3/4 running »), section « Standalone containers »,
  pastilles d'état, badges colorés (healthy, Running, exited), ports cliquables
  (ouvrent `http://localhost:<port>`).
- **Panneau de détail** à droite pour le conteneur sélectionné : nom + image,
  boutons Start/Stop/Restart/Logs/Shell/Env, mini-graphes CPU et mémoire,
  Status/Ports/Compose/ID, politique de redémarrage, Inspect et Remove.
- **Images / Volumes / Networks** : listes comme sur Tauri (et comme les
  onglets actuels de `ContainersPanelViewController`), avec leurs actions
  existantes (pull/delete image, prune volumes, prune networks) + **Prune
  images** (nouveau, voir parité).
- **Modules Mac existants conservés** et restylés avec les jetons :
  explorateur de volumes (`VolumeBrowserViewController`), éditeur Compose
  (`ComposeEditorViewController`), logs filtrés (`EnhancedLogsViewController`),
  snapshots (`SnapshotViewController`), variables d'env
  (`EnvVarsViewController`), réglages (`SettingsPanelViewController`).
- **Placement des deux outils propres au Mac** (décision utilisateur :
  actions contextuelles, la barre latérale reste identique à la structure
  Tauri) :
  - *Explorateur de volumes* : bouton « Parcourir » sur un volume de la section
    Volumes (et entrée de menu contextuel) → ouvre l'explorateur dans la zone
    de contenu, avec retour à la liste.
  - *Éditeur Compose* : action « Éditer le compose » sur une ligne de stack de
    la section Compose (bouton de la ligne / menu contextuel / panneau de
    détail quand une stack est sélectionnée) → ouvre l'éditeur dans la zone de
    contenu, avec retour au tableau.

### Parité d'actions avec Tauri (décision utilisateur : on les ajoute)
- Ajouter dans `ColimaBarCore` / `ColimaManager`, avec tests dans
  `Tests/ColimaBarTests` :
  - **Remove** d'un conteneur (`docker rm`, confirmation côté UI ; conteneur
    en marche : proposer arrêt + suppression ou `rm -f` après confirmation
    explicite).
  - **Prune images** (`docker image prune`, confirmation côté UI).
  - **Inspect** affiché dans l'app (sortie JSON de `docker inspect`, vue
    lecture seule en police mono avec copie), à la place de l'ouverture du
    Terminal.
- Le panneau de détail a alors les mêmes boutons que Tauri.

### Mini-panneau de la barre de statut
- Le clic sur l'icône lama ouvre un popover SwiftUI à la place du `NSMenu`.
- Haut : bandeau indigo (logo, « Colima·Bar », pastille d'état, jauges CPU/RAM).
- Milieu : stacks Compose et conteneurs isolés avec badges d'état.
- Bas : Démarrer/Arrêter Colima, Rafraîchir, **Ouvrir le Dashboard** (bouton
  principal, raccourci ⌘D conservé), Réglages (roue dentée).
- Clic sur une stack/un conteneur → ouvre le Dashboard sélectionné dessus.
- Pendant démarrage/arrêt : jauges grisées, bouton désactivé avec indicateur
  d'activité.
- Avertissements actuels (Portainer absent → installer, mise à jour Colima
  disponible → mettre à jour, dernière erreur) : bandeau discret dans le panneau.
- « Quitter » et « À propos » : dans le menu de la roue dentée.

### Mode sombre
- Fenêtre et panneau suivent le réglage clair/sombre de macOS en direct.
- En-tête/bandeau indigo et couleurs de marque inchangés dans les deux modes ;
  seuls fonds, textes, bordures et badges utilisent leur variante sombre (celle
  de Tauri).

## Inventaire des fonctions à préserver (menu actuel → nouvelle place)

Source : `StatusBarController.swift`.

| Fonction actuelle | Nouvelle place |
|---|---|
| État Colima + infos profil, usage CPU/RAM | bandeau du panneau + en-tête Dashboard |
| Démarrer / Arrêter Colima | panneau + en-tête Dashboard |
| Ouvrir le Dashboard (⌘D) | panneau |
| Sous-menu Containers / panneau containers | liste du panneau + Dashboard |
| Sous-menu Instance (changer de profil) | Réglages (roue dentée) |
| Portainer : installer / ouvrir | bandeau d'avertissement du panneau + bouton Dashboard |
| Prune Docker | bouton Dashboard (Compose/Containers) |
| Réglages | roue dentée |
| Mise à jour Colima disponible / upgrade | bandeau d'avertissement du panneau |
| Dernière erreur | bandeau d'avertissement du panneau |
| Logs / Shell d'un conteneur (Terminal) | panneau de détail du Dashboard |
| À propos, Quitter | menu de la roue dentée |
| Notifications de crash conteneur | inchangé |

## Choix faits par Claude (à vérifier)

- **Disque dans l'en-tête** : afficher la taille réelle de la VM. Décoder le
  champ `disk` de `colima list --json` dans `ColimaListEntry`, l'exposer dans
  `ColimaAppState`, mettre à jour les tests du parseur. Repli si absent :
  `ColimaConfig.desiredDiskGB`.
- **Ouvrir le Dashboard sur une stack/un conteneur** depuis le panneau :
  sélectionne la section Compose (stack) ou Containers (conteneur isolé) et la
  ligne correspondante, panneau de détail ouvert.

## Laissé au constructeur

- Réécrire chaque module existant en SwiftUI ou l'héberger tel quel
  (`NSViewControllerRepresentable`) puis le restyler : au choix, module par
  module, tant que le rendu respecte les jetons et le mode sombre.
- Barre de titre : standard (comme le banner) ou fusionnée avec l'en-tête
  (feux tricolores sur le bandeau).
- Découpage en vues SwiftUI, modèle observable alimenté par
  `ColimaAppState` (aujourd'hui poussé via `update(state:)`).
- Historique des mini-graphes (taille du tampon, fréquence) à partir de
  `containerStats` ; `SparklineView` existant réutilisable ou remplacé.
- Taille par défaut / minimale de la fenêtre et du popover.
- Ordre de livraison (ex. jetons → en-tête+sidebar → Compose/Containers →
  panneau → autres modules).

## Vérification attendue

- `swift build` et `make test` passent.
- `make open` puis captures d'écran de la fenêtre (chaque section) et du
  panneau, **en clair et en sombre**, comparées à `docs/banner.png` et aux
  captures Tauri.
- Parcours manuel de chaque ligne du tableau d'inventaire ci-dessus.

# Refonte visuelle macOS — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Donner à l'app macOS (Swift) la même identité visuelle que l'app Tauri : fenêtre Dashboard SwiftUI (en-tête indigo + barre latérale), mini-panneau de barre de statut, mode sombre automatique, sans perte de fonctionnalité.

**Architecture:** La logique testable (taille disque, actions Remove/Prune images/Inspect, regroupement par stack, historique des métriques) va dans `ColimaBarCore` avec tests. L'UI SwiftUI vit dans `Sources/ColimaBar/UI/`, hébergée par AppKit (`NSHostingController`, `NSPopover`). Un `AppStore: ObservableObject` unique remplace le passage de `ColimaAppState` par callbacks ; les modules AppKit existants (explorateur de volumes, éditeur Compose, logs, snapshots, env, réglages) sont hébergés via `NSViewControllerRepresentable` et restylés avec les jetons.

**Tech Stack:** Swift 5.9, SwiftPM (pas de projet Xcode), AppKit + SwiftUI macOS 13, runner de tests maison (`Tests/ColimaBarTests/main.swift`, pas XCTest).

**Spec:** `docs/superpowers/specs/2026-11-08-macos-redesign-design.md`

## Global Constraints

- Cible `.macOS(.v13)` : API SwiftUI macOS 13 uniquement (`ObservableObject`/`@Published`, pas `@Observable` ; `NavigationSplitView` OK).
- Aucune dépendance externe. Build : `swift build` ; tests : `make test` ; install : `make open`.
- Couleurs = valeurs exactes de `tauri/src/styles.css` (`:root` pour le clair, bloc `@media (prefers-color-scheme: dark)` pour le sombre). Aucune couleur codée en dur hors de `Sources/ColimaBar/Theme.swift`.
- En-tête/bandeau : dégradé indigo `#3B4CCA` → navy `#121A4A`, identique en clair et en sombre. « Bar » en dégradé teal `#12A894` → orange `#F26B1D`.
- Textes via `L.t(fr, en)` (FR/EN). Police système ; police mono système pour IDs, ports, logs, JSON.
- L'app reste `LSUIElement` (pas d'icône Dock permanente).
- Chaque fonction de la table « Inventaire des fonctions à préserver » du spec reste accessible.
- Tests ajoutés dans `Tests/ColimaBarTests/*.swift` et appelés depuis `Tests/ColimaBarTests/main.swift`.

## Review Focus

1. **Colima arrêté ou état `.unknown`** : fenêtre et panneau affichent un état vide lisible (« Colima est arrêté » + bouton Démarrer), jauges grisées, aucune action Docker activée, pas de crash. → test `test_groupContainers_empty` (Task 3) + vérif manuelle Task 11.
2. **Conteneur sans stats (exited)** : CPU/RAM affichés « — » et non « 0 % » ; les totaux de stack n'additionnent que les conteneurs présents dans les stats. → `test_groupContainers_missingStats` (Task 3).
3. **Remove d'un conteneur en marche** : confirmation explicite, puis `docker rm -f` ; une erreur Docker est affichée, rien n'est supprimé silencieusement. → `test_removeContainer_force_usesDashF`, `test_removeContainer_failure_propagatesMessage` (Task 2).
4. **Conteneur qui disparaît ou est recréé** : son historique de métriques est purgé, pas de graphe fantôme ni de fuite mémoire. → `test_metricHistoryStore_prune` (Task 3).
5. **Bascule clair/sombre fenêtre ouverte** : tout bascule en direct, aucun fond blanc résiduel. → étape grep « pas de couleur en dur » + captures clair/sombre (Task 11).

---

### Task 1: Taille disque réelle dans l'état

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaState.swift` (`ColimaListEntry`, `ColimaAppState`)
- Modify: `Sources/ColimaBarCore/ColimaManager.swift` (`fetchStateSync`)
- Test: `Tests/ColimaBarTests/ColimaStateTests.swift`, `Tests/ColimaBarTests/main.swift`

**Interfaces:**
- Produces: `ColimaListEntry.disk: Int64?` (octets, optionnel pour compat) ; `ColimaAppState.diskGB: Double?` (nouveau paramètre `diskGB: Double? = nil` de l'init, après `memoryGB`).

- [ ] **Step 1: Tests**

```swift
func test_parseListJSON_disk() {
    let json = #"{"name":"default","status":"Running","cpus":2,"memory":4294967296,"disk":64424509440}"#
    checkEqual(ColimaManager.parseListJSON(json)?.disk, 64_424_509_440, "disk bytes decoded")
}
func test_parseListJSON_noDisk_stillParses() {
    let json = #"{"name":"default","status":"Running","cpus":2,"memory":4294967296}"#
    checkNotNil(ColimaManager.parseListJSON(json), "entry without disk still parses")
}
func test_fetchStateSync_diskGB() {
    // mock `colima list --json` (running, disk 64424509440) comme test_fetchStateSync_running_*,
    // autres appels docker -> sortie vide exitCode 0
    checkEqual(state.diskGB, 60.0, "diskGB = disk / 1_073_741_824")
}
```
Ajouter les 3 appels dans `main.swift`.

- [ ] **Step 2:** `make test` → les 3 nouveaux tests échouent (compilation ou FAIL).
- [ ] **Step 3:** Implémenter : `disk: Int64?` dans `ColimaListEntry` ; `diskGB` dans `ColimaAppState` ; `fetchStateSync` passe `entry.disk.map { Double($0) / 1_073_741_824 }`.
- [ ] **Step 4:** `make test` → tout passe.
- [ ] **Step 5:** Commit `feat(core): expose VM disk size in ColimaAppState`.

---

### Task 2: Actions de parité Tauri (Remove, Prune images, Inspect)

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaManager.swift` (section Actions)
- Create: `Tests/ColimaBarTests/ContainerActionsTests.swift`
- Modify: `Tests/ColimaBarTests/ColimaStateTests.swift` (helper d'attente), `Tests/ColimaBarTests/main.swift`

**Interfaces:**
- Produces (toutes appellent `completion` sur le main thread, comme `pruneDocker`) :
  - `removeContainer(_ name: String, force: Bool, completion: @escaping (Result<Void, Error>) -> Void)` → `docker rm <name>` ou `docker rm -f <name>`
  - `pruneImages(completion: @escaping (Result<String, Error>) -> Void)` → `docker image prune -f`
  - `inspectContainer(_ name: String, completion: @escaping (Result<String, Error>) -> Void)` → `docker inspect <name>` (JSON brut)
  - Échec : `ShellError(message:)` = stderr, sinon message par défaut via `L.t`.
- Produces (tests) : `func waitUntil(timeout: TimeInterval = 2, _ done: () -> Bool)` — fait tourner `RunLoop.main.run(until:)` par pas de 0,01 s.

- [ ] **Step 1: Tests** (mock `MockShellRunner`, clés via `makeKey(_dockerPath, [...])`)

```swift
func test_removeContainer_usesRm()            // args == ["rm","web"], résultat .success
func test_removeContainer_force_usesDashF()   // force: true -> ["rm","-f","web"]
func test_removeContainer_failure_propagatesMessage() // exitCode 1, error "conflict" -> .failure, localizedDescription == "conflict"
func test_pruneImages_args()                  // ["image","prune","-f"], .success(output)
func test_inspectContainer_returnsJSON()      // output "[{\"Id\":\"abc\"}]" -> .success(même chaîne)
```
Chaque test : appeler la méthode, `waitUntil { result != nil }`, puis asserts. Ajouter à `main.swift`.

- [ ] **Step 2:** `make test` → FAIL (méthodes absentes).
- [ ] **Step 3:** Implémenter les 3 méthodes sur le modèle de `pruneDocker` / `startContainer`.
- [ ] **Step 4:** `make test` → PASS.
- [ ] **Step 5:** Commit `feat(core): add remove, prune images and inspect actions`.

---

### Task 3: Regroupement par stack et historique des métriques

**Files:**
- Create: `Sources/ColimaBarCore/ContainerGroups.swift`
- Create: `Sources/ColimaBarCore/MetricHistory.swift`
- Create: `Tests/ColimaBarTests/ContainerGroupsTests.swift`
- Modify: `Tests/ColimaBarTests/main.swift`

**Interfaces:**
- Produces :
  ```swift
  public enum StackStatus: Equatable { case allRunning, partial(running: Int, total: Int), stopped }
  public struct StackGroup: Equatable {
      public let name: String
      public let containers: [DockerContainer]   // triés par nom
      public let status: StackStatus
      public let cpuPercent: Double              // somme des conteneurs présents dans stats
      public let memUsedMiB: Double
  }
  public enum ContainerGrouping {
      public static func group(_ containers: [DockerContainer],
                               stats: [String: ResourceUsage]) -> (stacks: [StackGroup], standalone: [DockerContainer])
  }
  public struct MetricHistory: Equatable {
      public init(capacity: Int = 60)
      public private(set) var values: [Double]
      public mutating func append(_ value: Double)   // garde les `capacity` dernières
  }
  public struct MetricHistoryStore {
      public init(capacity: Int = 60)
      public private(set) var cpu: [String: MetricHistory]   // clé = nom du conteneur
      public private(set) var mem: [String: MetricHistory]   // MiB
      public mutating func record(_ stats: [String: ResourceUsage])  // append + purge des noms absents
  }
  ```
  Stack = `DockerContainer.composeProject` ; stacks triées par nom ; conteneurs sans projet → `standalone` triés par nom.

- [ ] **Step 1: Tests**

```swift
func test_groupContainers_empty()            // ([], [:]) -> stacks vide, standalone vide
func test_groupContainers_stacksAndStandalone() // 2 conteneurs proj "shop", 1 sans label -> 1 stack "shop" (2), 1 standalone
func test_groupContainers_statusPartial()    // shop: 3 running + 1 exited -> .partial(running: 3, total: 4)
func test_groupContainers_statusAllRunning() // -> .allRunning ; tous exited -> .stopped
func test_groupContainers_missingStats()     // stats seulement pour 1 des 2 -> cpu/mem = ceux du seul présent
func test_metricHistory_capacity()           // capacity 3, append 1..5 -> values == [3,4,5]
func test_metricHistoryStore_prune()         // record(["a","b"]) puis record(["a"]) -> cpu.keys == ["a"], cpu["a"].values.count == 2
```

- [ ] **Step 2:** `make test` → FAIL.
- [ ] **Step 3:** Implémenter les deux fichiers.
- [ ] **Step 4:** `make test` → PASS.
- [ ] **Step 5:** Commit `feat(core): add stack grouping and metric history`.

---

### Task 4: Jetons de design et composants de base

**Files:**
- Modify: `Sources/ColimaBar/Theme.swift`
- Create: `Sources/ColimaBar/UI/Components.swift`

**Interfaces:**
- Produces dans `Theme` :
  - `enum Tokens` : une propriété `NSColor` dynamique par variable CSS — `bg, surface, surface2, border, text, text2, text3, accent, accentSoft, rowHover, rowSelected, green, greenSoft, amber, amberSoft, red, redSoft` — via `NSColor(name:dynamicProvider:)` (clair si `appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua`). Valeurs exactes de `tauri/src/styles.css` (clair `:root`, sombre bloc `@media`).
  - `extension Color` : mêmes noms (`Color.tkBg`, `.tkSurface`, …, préfixe `tk`) via `Color(nsColor:)`.
  - `Theme.Brand` conserve `indigo/teal/orange`, ajoute `navy` (#121A4A) ; `static let headerGradient: LinearGradient` (indigo → navy) ; `static let wordmarkGradient: LinearGradient` (teal → orange) ; `static let radius: CGFloat = 10`.
- Produces dans `Components.swift` (SwiftUI) :
  - `BrandWordmark(size: CGFloat)` — « Colima » + « Bar » en dégradé.
  - `BrandLogo(size: CGFloat)` — `NSApp.applicationIconImage` arrondi.
  - `StatusDot(color: Color)` ; `StatePill(state: ColimaRunningState)` (« Colima · Running / Stopped / Starting… »).
  - `StatusBadge(text: String, kind: BadgeKind)` avec `enum BadgeKind { case success, warning, danger, neutral }` (fond `*Soft`, texte couleur pleine) + `static func forContainer(_ c: DockerContainer) -> StatusBadge` (healthy/unhealthy/Running/exited…) et `forStack(_ s: StackStatus)` (« All running », « 3/4 running », « Stopped »).
  - `HeaderGauge(label: String, value: String, fraction: Double)` (barre fine sur bandeau).
  - `PortChip(port: Int)` — mono, fond `accentSoft`, clic → `NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!)`.
  - `Sparkline(values: [Double], color: Color)` — tracé + remplissage dégradé.
  - `MetricText(_ value: Double?, format: …)` → « — » si `nil`.

- [ ] **Step 1:** Implémenter `Theme` + `Components.swift` (rien n'est encore branché). Ne pas supprimer `SparklineView.swift` ici : encore utilisé jusqu'à la Task 10.
- [ ] **Step 2:** `swift build` → OK.
- [ ] **Step 3:** Commit `feat(ui): design tokens matching Tauri (light/dark) and base components`.

---

### Task 5: AppStore et câblage de l'état

**Files:**
- Create: `Sources/ColimaBar/UI/AppStore.swift`
- Modify: `Sources/ColimaBar/AppDelegate.swift`, `Sources/ColimaBar/StatusBarController.swift` (exposer `onStateUpdate` vers le store, garder la détection de crash), `Sources/ColimaBar/DashboardWindowController.swift` (recevoir le store)

**Interfaces:**
- Consumes : `ColimaManager` (existant + Task 1/2), `ContainerGrouping`, `MetricHistoryStore`.
- Produces :
  ```swift
  enum DashboardSection: String, CaseIterable, Identifiable { case compose, containers, images, volumes, networks, logs, snapshots }
  enum ContentRoute: Equatable { case section, volumeBrowser(volume: String), composeEditor(stack: String) }
  final class AppStore: ObservableObject {
      init(manager: ColimaManager)
      @Published private(set) var state: ColimaAppState
      @Published private(set) var history: MetricHistoryStore
      @Published var section: DashboardSection
      @Published var route: ContentRoute
      @Published var selectedContainer: String?    // nom
      @Published var selectedStack: String?
      @Published var search: String
      @Published var transition: String?           // libellé pendant start/stop, nil sinon
      @Published var updateVersion: String?
      @Published var lastError: String?
      var groups: (stacks: [StackGroup], standalone: [DockerContainer]) { get }  // filtré par `search`
      func apply(_ state: ColimaAppState)          // met à jour state + history.record(state.containerStats)
      func startColima(); func stopColima(); func refresh()
      func start(_ name: String); func stop(_ name: String); func restart(_ name: String)
      func remove(_ name: String, force: Bool); func pruneDocker(); func pruneImages()
      func inspect(_ name: String, completion: @escaping (String) -> Void)
      func installPortainer(); func openPortainer(); func upgradeColima()
      func reveal(container: String?, stack: String?) // section + sélection, utilisé par le panneau
  }
  ```
  Les actions reprennent la logique actuelle de `StatusBarController` (start/stop Colima avec `onTransition`, Portainer, upgrade, prune) ; erreurs → `lastError` + notification existante `AppDelegate.showError`.
- `AppDelegate` crée un seul `AppStore` et le passe à `StatusBarController` et `DashboardWindowController`.

- [ ] **Step 1:** Implémenter `AppStore` et le câblage ; `DashboardWindowController.update(state:)` disparaît au profit de `store.apply`.
- [ ] **Step 2:** `swift build` → OK ; `make test` → PASS (Core intact).
- [ ] **Step 3:** `make open` : le menu actuel fonctionne toujours (start/stop, états).
- [ ] **Step 4:** Commit `refactor(ui): single AppStore observable state`.

---

### Task 6: Fenêtre Dashboard — en-tête, barre latérale, navigation

**Files:**
- Create: `Sources/ColimaBar/UI/Dashboard/DashboardRootView.swift`, `HeaderView.swift`, `SidebarView.swift`, `Hosted.swift`
- Modify: `Sources/ColimaBar/DashboardWindowController.swift` (`NSHostingController(rootView: DashboardRootView().environmentObject(store))`, taille par défaut ~1180×760, min ~900×560)
- Delete: `Sources/ColimaBar/DashboardViewController.swift`, `Sources/ColimaBar/SidebarViewController.swift`

**Interfaces:**
- Consumes : `AppStore`, `DashboardSection`, `ContentRoute`, composants Task 4.
- Produces :
  - `HeaderView` : logo, `BrandWordmark`, ligne « \(instance) · \(cpus) CPU · \(mem) GB · \(disk) GB disk » (`diskGB` sinon `ColimaConfig.desiredDiskGB`), `StatePill`, `HeaderGauge` CPU (`usage.cpuPercent`) et RAM (`memUsedFormatted / memTotalGiB`), bouton Stop/Start Colima, Rafraîchir, menu roue dentée (Réglages… → Task 9, À propos, Quitter).
  - `SidebarView` : groupes « Docker » (Compose + nb stacks, Containers + nb conteneurs, Images, Volumes, Networks) et « Colima » (Logs, Snapshots), SF Symbols, sélection `store.section`.
  - `struct HostedVC<VC: NSViewController>: NSViewControllerRepresentable` (`make: () -> VC`, `update: (VC) -> Void`) pour héberger les modules AppKit.
  - `final class ModuleControllers` (dans `Hosted.swift`, une instance détenue par `AppStore` sous `store.modules`) : `lazy var logs: EnhancedLogsViewController`, `snapshots: SnapshotViewController`, `composeEditor: ComposeEditorViewController`, `volumeBrowser: VolumeBrowserViewController` — instances uniques pour garder leur état entre navigations ; `AppStore.apply` appelle leurs `updateContainers(state.containers)` comme l'ancien `DashboardViewController`.
  - `DashboardRootView` : `VStack { HeaderView; NavigationSplitView { SidebarView } detail: { contenu selon section/route } }` ; sections non encore faites → `Text` placeholder (remplacé Tasks 7-9).
  - État Colima arrêté/unknown : contenu Docker remplacé par une vue vide « Colima est arrêté » + bouton Démarrer.

- [ ] **Step 1:** Implémenter. Le raccourci ⌘D et `showDashboard()` restent.
- [ ] **Step 2:** `swift build` → OK.
- [ ] **Step 3:** `make open`, ouvrir le Dashboard : en-tête et barre latérale conformes à `docs/banner.png`, en clair puis en sombre (Réglages Système → Apparence).
- [ ] **Step 4:** Commit `feat(ui): SwiftUI dashboard shell with brand header and sidebar`.

---

### Task 7: Compose et Containers + panneau de détail

**Files:**
- Create: `Sources/ColimaBar/UI/Dashboard/ContainersTableView.swift`, `ContainerDetailView.swift`, `InspectSheet.swift`
- Modify: `DashboardRootView.swift` (brancher `.compose`, `.containers`, `.composeEditor`)

**Interfaces:**
- Consumes : `AppStore.groups`, `history`, actions ; `HostedVC` ; `ComposeEditorViewController` (existant), `EnvVarsViewController` (existant), `ComposeProject`/`DockerComposeService.findComposeFile`.
- Produces :
  - Barre d'outils : champ recherche (`store.search`), « Open Portainer » (ou « Installer Portainer » si `!portainerExists`), « Prune Docker… » (confirmation).
  - `ContainersTableView(mode: .grouped | .flat)` : colonnes Name / Image / Status / Ports / CPU / RAM ; `.grouped` = lignes de stack repliables (résumé « N containers », `StatusBadge.forStack`, totaux) puis « Standalone containers » ; `.flat` = tous les conteneurs. Nom du service (`labelValue(forKey: "com.docker.compose.service")`) en gris après le nom. Ports = `PortChip` par `hostPortNumbers`. CPU/RAM via `MetricText` (`nil` si absent des stats). Sélection → `store.selectedContainer` / `selectedStack`. Menu contextuel stack : « Éditer le compose » (→ `route = .composeEditor(stack:)`), Start/Stop. Implémentation au choix : `Table` hiérarchique si dispo en macOS 13, sinon `List` + `DisclosureGroup` avec colonnes en `Grid`.
  - `ContainerDetailView` : nom + image ; boutons Start/Stop/Restart/Logs (→ `section = .logs` + `store.modules.logs.showLogs(for:)`)/Shell (Terminal comme aujourd'hui)/Env (sheet hébergeant `EnvVarsViewController`) ; `Sparkline` CPU et mémoire depuis `history` ; Status/Ports/Compose (« projet / service »)/ID (12 car., mono) ; Picker politique de redémarrage (`no, always, unless-stopped, on-failure`, via `setRestartPolicy`) ; Inspect (→ `InspectSheet`, JSON mono, bouton Copier) ; Remove (rouge, `confirmationDialog` ; si running : texte d'avertissement et `force: true`).
  - Stack sélectionnée : détail de stack avec « Éditer le compose », Start/Stop de tous les conteneurs.
  - `.composeEditor(stack:)` : `HostedVC { store.modules.composeEditor }` (positionné sur la stack) + bouton « ← Retour » qui remet `route = .section`.

- [ ] **Step 1:** Implémenter.
- [ ] **Step 2:** `swift build` → OK ; `make test` → PASS.
- [ ] **Step 3:** `make open` : comparer à `docs/desktop-compose.png` et `docs/desktop-containers-dark.png` ; tester Remove sur un conteneur jetable (`docker run -d --name tmp nginx`), Inspect, Env, ports cliquables, édition compose + retour.
- [ ] **Step 4:** Commit `feat(ui): compose/containers table and detail panel`.

---

### Task 8: Images, Volumes, Networks

**Files:**
- Create: `Sources/ColimaBar/UI/Dashboard/ImagesView.swift`, `VolumesView.swift`, `NetworksView.swift`
- Modify: `DashboardRootView.swift` (brancher les 3 sections + `.volumeBrowser`)

**Interfaces:**
- Consumes : `ColimaManager.fetchImages/deleteImage/pullImage/pruneImages/fetchVolumes/pruneVolumes/fetchNetworks/pruneNetworks` via `AppStore` (ajouter les wrappers nécessaires à `AppStore`), `VolumeBrowserViewController` (existant).
- Produces :
  - `ImagesView` : tableau Repository / Tag / ID (mono) / Size / Created ; Pull (champ nom), Delete (confirmation), « Prune images… » (confirmation).
  - `VolumesView` : tableau Name / Driver / Size / Used by ; « Prune volumes… » ; bouton « Parcourir » et menu contextuel → `route = .volumeBrowser(volume:)`.
  - `NetworksView` : tableau Name / Driver / Scope / ID ; « Prune networks… ».
  - `.volumeBrowser(volume:)` : `HostedVC { store.modules.volumeBrowser }` (positionné sur le volume) + « ← Retour ».
  - Chargement au premier affichage + bouton Rafraîchir de l'en-tête ; état vide si Colima arrêté.

- [ ] **Step 1:** Implémenter.
- [ ] **Step 2:** `swift build` → OK.
- [ ] **Step 3:** `make open` : chaque liste se charge, actions OK, Parcourir/Retour OK, clair et sombre.
- [ ] **Step 4:** Commit `feat(ui): images, volumes and networks sections`.

---

### Task 9: Logs, Snapshots, Réglages restylés

**Files:**
- Modify: `Sources/ColimaBar/EnhancedLogsViewController.swift`, `SnapshotViewController.swift`, `SettingsPanelViewController.swift`, `VolumeBrowserViewController.swift`, `ComposeEditorViewController.swift`, `EnvVarsViewController.swift` — remplacer couleurs/polices par `Theme.Tokens` + police système/mono ; aucun changement de comportement.
- Create: `Sources/ColimaBar/UI/SettingsWindowController.swift`
- Modify: `DashboardRootView.swift` (`.logs`, `.snapshots`)

**Interfaces:**
- Consumes : `HostedVC`, `AppStore`, `manager.listInstances`, `ColimaConfig.activeInstanceName`.
- Produces :
  - Sections `.logs` et `.snapshots` = `HostedVC { store.modules.logs }` / `{ store.modules.snapshots }` (Task 6).
  - `SettingsWindowController.shared.show(store:)` : fenêtre hébergeant `SettingsPanelViewController` (rappels identiques à l'ancien `wireSettingsCallbacks`) + en tête un Picker « Instance » (liste `listInstances`, bascule comme `switchInstance` actuel). Ouverte par la roue dentée (en-tête et panneau).

- [ ] **Step 1:** Restyler les 6 VC ; implémenter la fenêtre Réglages.
- [ ] **Step 2:** `swift build` → OK.
- [ ] **Step 3:** `make open` : Logs (filtres), Snapshots (créer/restaurer sur liste), Réglages (changer d'instance, langue, démarrage auto), en clair et en sombre.
- [ ] **Step 4:** Commit `feat(ui): restyle logs, snapshots and settings with design tokens`.

---

### Task 10: Mini-panneau de la barre de statut

**Files:**
- Create: `Sources/ColimaBar/UI/StatusPopoverView.swift`
- Modify: `Sources/ColimaBar/StatusBarController.swift` (remplacer `NSMenu` + popover conteneurs par un `NSPopover` SwiftUI ; garder icône, badge, détection de crash, notifications)
- Delete: `Sources/ColimaBar/ContainersPanelViewController.swift`, `Sources/ColimaBar/SparklineView.swift`, `Sources/ColimaBar/LogsWindowController.swift` si plus référencé (vérifier par `grep`)

**Interfaces:**
- Consumes : `AppStore` (dont `reveal`, `transition`, `updateVersion`, `lastError`), composants Task 4, `SettingsWindowController`.
- Produces : `StatusPopoverView` (largeur ~340) :
  - Bandeau `Theme.Brand.headerGradient` : logo, `BrandWordmark`, `StatePill`, `HeaderGauge` CPU et RAM (grisées si `transition != nil` ou non running).
  - Bandeaux d'avertissement (discrets, cliquables) : Portainer absent → « Installer Portainer », `updateVersion` → « Mettre à jour Colima \(v) », `lastError` → message + fermer.
  - Liste « Stacks & containers » (scroll, hauteur max ~260) : stacks avec `StatusBadge.forStack`, puis standalone ; clic → `store.reveal(...)` + ouvre le Dashboard + ferme le popover. Vide si Colima arrêté (« Colima est arrêté »).
  - Pied : Start/Stop Colima (désactivé + `ProgressView` pendant `transition`), Rafraîchir, bouton principal « Ouvrir le Dashboard » (`.keyboardShortcut("d")`), roue dentée (Réglages…, À propos, Quitter).
  - `popover.behavior = .transient` ; clic sur l'icône = toggle.

- [ ] **Step 1:** Implémenter, supprimer le code mort, `grep -rn "ContainersPanelViewController\|SparklineView\|LogsWindowController" Sources` → aucune référence restante.
- [ ] **Step 2:** `swift build` → OK ; `make test` → PASS.
- [ ] **Step 3:** `make open` : parcourir **chaque ligne** du tableau d'inventaire du spec depuis le panneau/Dashboard.
- [ ] **Step 4:** Commit `feat(ui): branded status bar popover replaces menu`.

---

### Task 11: Vérification visuelle finale

**Files:** aucun nouveau (corrections ponctuelles seulement).

- [ ] **Step 1:** `grep -rnE 'NSColor\(srgbRed|NSColor\(red|Color\(red|#colorLiteral|NSColor\.(white|black)|Color\.(white|black)' Sources/ColimaBar | grep -v Theme.swift` → seules occurrences tolérées : texte blanc sur le bandeau indigo (documenter chaque cas restant ou le passer par `Theme`).
- [ ] **Step 2:** `make test` → PASS ; `make open`.
- [ ] **Step 3:** Captures (`screencapture -l <windowid>` ou ⌘⇧4) de : panneau, Compose, Containers, Images, Volumes, Parcourir, Networks, Logs, Snapshots, Réglages — **en clair puis en sombre** ; basculer l'apparence fenêtre ouverte et vérifier le changement en direct. Comparer à `docs/banner.png` et aux captures Tauri.
- [ ] **Step 4:** Colima arrêté (`colima stop`) : panneau et Dashboard affichent l'état vide, aucune action Docker active ; redémarrer depuis le panneau.
- [ ] **Step 5:** Commit des corrections `fix(ui): visual polish after review`.

# ColimaBar Évolutions — Design Spec

**Date :** 2026-05-22  
**Statut :** Approuvé  
**Approche :** Incrémentale (Dashboard → Volume → Compose → Logs → Snapshot)

---

## Contexte

ColimaBar est une app macOS AppKit native (Swift SPM, CLT-only, pas de Xcode).  
Structure existante : `ColimaBarCore` (logique, Foundation) + `ColimaBar` (UI, AppKit).  
Toute exécution de commande passe par `ShellRunner.swift` existant.

---

## Architecture : Transition Multi-Fenêtres

### Objectif

Ajouter un Dashboard `NSWindow` persistant en complément du popover existant. Le popover conserve son rôle de vue rapide ; le Dashboard offre les modules avancés.

### Nouveaux fichiers — `Sources/ColimaBar/`

**`DashboardWindowController.swift`**  
`NSWindowController` singleton instancié lazily dans `AppDelegate`.  
`windowShouldClose` retourne `false` (la fenêtre se cache, l'app ne quitte pas).  
Taille initiale : 900×600pt, titre "ColimaBar Dashboard".

**`DashboardViewController.swift`**  
`NSSplitViewController` avec deux sous-vues :
- Sidebar gauche : 180pt fixe, `SidebarViewController`
- Zone contenu droite : expansible, swappée selon sélection sidebar

**`SidebarViewController.swift`**  
`NSTableView` avec 5 entrées (icône SF Symbol + label) :
| Index | Label | VC cible |
|---|---|---|
| 0 | Containers | `ContainersPanelViewController` (existant, réutilisé) |
| 1 | Volumes | `VolumeBrowserViewController` |
| 2 | Compose | `ComposeEditorViewController` |
| 3 | Logs | `EnhancedLogsViewController` |
| 4 | Settings | `SettingsPanelViewController` (existant, réutilisé) |

### Modifications fichiers existants

**`AppDelegate.swift`**  
Ajouter : `lazy var dashboardWindowController = DashboardWindowController()`  
`applicationShouldTerminateAfterLastWindowClosed` reste `false`.

**`StatusBarController.swift`**  
Ajouter bouton "Ouvrir le Dashboard" dans le popover → `appDelegate.dashboardWindowController.showWindow(nil)`.

---

## Module 1 : Volume Browser (Priorité 1)

### Objectif

Naviguer dans le filesystem d'un conteneur Running et transférer des fichiers via `docker cp`.

### Service Core — `DockerExecService.swift`

```swift
struct FileEntry { let name: String; let size: String; let permissions: String; let isDirectory: Bool }

class DockerExecService {
    func listFiles(container: String, path: String) async throws -> [FileEntry]
    // docker exec <container> ls -la <path> — parse chaque ligne
    
    func copyFromContainer(container: String, remotePath: String, localURL: URL) async throws
    // docker cp <container>:<remotePath> <localURL.path>
    
    func copyToContainer(container: String, localURL: URL, remotePath: String) async throws
    // docker cp <localURL.path> <container>:<remotePath>
}
```

Vérifie `container.status == "running"` avant toute op. Lance `DockerExecError.containerNotRunning` sinon.

### UI — `VolumeBrowserViewController.swift`

- `NSPopUpButton` en haut → liste des conteneurs Running (rafraîchie à l'ouverture du Dashboard)
- `NSOutlineView` (navigation arborescente), chemin initial `/`
- Breadcrumb path en haut (chemin courant cliquable)
- Double-clic sur dossier → descend ; bouton ← pour remonter
- Bouton **Download** → `NSSavePanel` → `copyFromContainer`
- Bouton **Upload** → `NSOpenPanel` → `copyToContainer`
- Si aucun conteneur Running : vue vide avec message "Aucun conteneur en cours d'exécution"
- Si conteneur sélectionné passe à l'état non-Running : alerte + désactivation des boutons

---

## Module 2 : Éditeur Docker-Compose (Priorité 2)

### Objectif

Localiser, éditer et redémarrer un projet Compose sans quitter l'app.

### Service Core — `DockerComposeService.swift`

```swift
class DockerComposeService {
    func findComposeFile(for container: DockerContainer) -> URL?
    // Lit labels: com.docker.compose.project.working_dir + com.docker.compose.project.config_files
    
    func saveAndRestart(composeFilePath: String, projectDir: String) async throws
    // Écrit le contenu, puis : colima ssh -- docker compose -f <path> up -d --build
}
```

Si labels absents → retourne `nil` (le VC affiche un message explicite).

### UI — `ComposeEditorViewController.swift`

- `NSPopUpButton` en haut → liste des projets Compose détectés (groupés par label `com.docker.compose.project`)
- `NSTextView` monospace (`NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)`)
- Indicateur "● Modified" dans la barre titre si dirty (contenu ≠ disque)
- Bouton **Save & Restart** → `NSAlert` confirmation → `saveAndRestart`
- Si `findComposeFile` retourne `nil` pour le projet sélectionné : label "Aucun fichier docker-compose détecté pour ce projet Compose" + bouton désactivé
- Si aucun projet Compose : vue vide avec message "Aucun projet Docker Compose détecté"

---

## Module 3 : Analyseur de Logs Intelligent (Priorité 3)

### Objectif

Améliorer `LogsWindowController` existant avec highlighting, recherche live et action "Expliquer l'erreur".

### Logique Pure — `LogFilter.swift`

```swift
struct AttributedLogLine { let text: String; let color: NSColor? }

struct LogFilter {
    static func apply(lines: [String], query: String) -> [AttributedLogLine]
    // Filtre les lignes par query (case-insensitive)
    // Colorise: ERROR → .systemRed, WARN → .systemOrange, SUCCESS → .systemGreen
}
```

Struct pure, testable sans infra Docker.

### UI — `EnhancedLogsViewController.swift`

Étend (ou remplace) `LogsWindowController` :
- `NSSearchField` en haut → filtre live via `LogFilter`
- `NSTextView` avec `NSAttributedString` pour les couleurs
- Bouton **"Expliquer l'erreur"** : collecte les 20 dernières lignes contenant ERROR, compose `"Les erreurs suivantes sont apparues dans mes logs Docker :\n<lignes>\nPeux-tu m'expliquer ces erreurs ?"`, copie dans `NSPasteboard.general`

---

## Module 4 : Snapshots Colima (Priorité 4)

### Objectif

Créer et restaurer des sauvegardes datées de la VM Colima.

### Service Core — `SnapshotService.swift`

```swift
struct ColimaSnapshot { let name: String; let date: Date; let sizeBytes: Int64 }

class SnapshotService {
    func listSnapshots() -> [ColimaSnapshot]
    // Crée ~/.colima/snapshots/ si absent. Parse *.qcow2, tri par date décroissante.
    
    func createSnapshot(name: String) async throws
    // 1. colima stop  2. cp -a ~/.colima/default/disk.qcow2 ~/.colima/snapshots/<name>_<date>.qcow2  3. colima start
    
    func restoreSnapshot(_ snapshot: ColimaSnapshot) async throws
    // 1. colima stop  2. cp -a <snapshot.path> ~/.colima/default/disk.qcow2  3. colima start
    
    func deleteSnapshot(_ snapshot: ColimaSnapshot) throws
    // rm snapshot file
}
```

**Contrainte :** `createSnapshot` et `restoreSnapshot` nécessitent l'arrêt de Colima — le VC informe l'utilisateur et demande confirmation.

### UI — `SnapshotViewController.swift`

- `NSTableView` colonnes : Nom / Date / Taille
- Bouton **"Créer snapshot"** → `NSAlert` avec `NSTextField` pour le nom → `createSnapshot`
- Bouton **"Restaurer"** → `NSAlert` "Colima sera arrêté et redémarré. Continuer ?" → `restoreSnapshot`
- `NSProgressIndicator` (indeterminate) pendant stop/copy/start
- Bouton **"Supprimer"** avec confirmation

---

## Contraintes Transversales

- **ShellRunner** : toute exécution de commande passe par `ShellRunner.swift` sans exception.
- **Séparation Core/UI** : aucun parsing Docker dans les ViewControllers.
- **CLT-only** : pas de dépendance à Xcode, pas de storyboard, tout en code.
- **Instance unique Dashboard** : `NSWindowController` lazily initialisé, jamais recréé.
- **Fermeture fenêtre** : `windowShouldClose` → `false` sur le Dashboard.

---

## Ordre d'implémentation

| Phase | Contenu | PR |
|---|---|---|
| 1 | Architecture Dashboard (NSWindowController + NSSplitView + Sidebar) | #1 |
| 2 | Volume Browser (DockerExecService + VolumeBrowserViewController) | #2 |
| 3 | Compose Editor (DockerComposeService + ComposeEditorViewController) | #3 |
| 4 | Enhanced Logs (LogFilter + EnhancedLogsViewController) | #4 |
| 5 | Snapshots (SnapshotService + SnapshotViewController) | #5 |

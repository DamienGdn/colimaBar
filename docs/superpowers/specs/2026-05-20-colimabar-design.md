# ColimaBar — Design Spec

**Date:** 2026-05-20  
**Statut:** Approuvé  

## Objectif

App macOS native dans la barre de menus (menu bar) remplaçant le workflow manuel Colima + Portainer. Équivalent fonctionnel d'un Docker Desktop minimaliste : démarrer/arrêter Colima, accéder à Portainer, voir l'état système — le tout depuis l'icône menu bar.

## Contexte existant

- `~/Applications/PortainerLauncher.sh` — script bash existant (démarre colima, portainer, ouvre URL)
- `/Applications/Portainer.app` — AppleScript wrapper qui appelle ce script (double-clic seulement)
- Colima 0.10.1 installé via Homebrew (`/opt/homebrew/bin/colima`)
- Container Portainer déjà créé (`docker start portainer`)

## Architecture

App Swift macOS pure, sans Storyboard, `NSStatusItem` programmatique.

```
ColimaBar/
├── ColimaBar.xcodeproj
└── ColimaBar/
    ├── AppDelegate.swift          # LSUIElement=true, crée StatusBarController
    ├── StatusBarController.swift  # NSStatusItem, NSMenu, mise à jour icône/menu
    ├── ColimaManager.swift        # shell commands, parsing état, timer polling
    └── Assets.xcassets/
```

`LSUIElement = true` dans `Info.plist` → pas d'icône Dock, app menu bar uniquement.

## UI — Icône

- SF Symbol `shippingbox.fill` comme image template (adapte dark/light automatiquement)  
- Titre `" ●"` en `NSAttributedString` :  
  - Vert `#00C853` si Colima running  
  - Gris `#888888` si Colima stopped  
- Pas de badge séparé — le dot dans le titre est suffisant et visible

## UI — Menu

### État normal (Portainer installé)

```
[📦●]
│
├── ● Colima : En cours d'exécution     ← NSMenuItem non-cliquable, gras
├── CPUs: 2  |  Mémoire: 4 GB          ← NSMenuItem non-cliquable, gris
├── ───────────────────────────────────
├── ▶ Démarrer Colima                   ← désactivé si running
├── ■ Arrêter Colima                    ← désactivé si stopped
├── ───────────────────────────────────
├── Ouvrir Portainer                    ← ouvre https://localhost:9443
├── ───────────────────────────────────
├── Lancer au démarrage  ✓              ← toggle SMAppService
└── Quitter
```

### État : Portainer non installé

```
[📦●]
│
├── ● Colima : En cours d'exécution
├── CPUs: 2  |  Mémoire: 4 GB
├── ───────────────────────────────────
├── ▶ Démarrer Colima
├── ■ Arrêter Colima
├── ───────────────────────────────────
├── ⚠ Portainer non installé
├── Installer Portainer…                ← lance docker run (voir ci-dessous)
├── ───────────────────────────────────
├── Lancer au démarrage  ✓
└── Quitter
```

"Installer Portainer…" est visible uniquement si Colima est running ET le container `portainer` n'existe pas (`docker ps -a` ne retourne pas `portainer`).

Pendant démarrage/arrêt : items Start/Stop grisés, ligne statut affiche "Démarrage…" / "Arrêt…".

## ColimaManager

### Polling
- Timer `DispatchSourceTimer` toutes les 5 secondes sur queue background
- Commande : `colima status` pour état running/stopped
- Commande : `colima list --json` pour CPU et mémoire alloués
- Callback `@MainActor` pour mise à jour UI

### Commandes

| Action | Commande |
|--------|----------|
| Start | `/opt/homebrew/bin/colima start` |
| Stop | `/opt/homebrew/bin/colima stop` |
| Status | `/opt/homebrew/bin/colima status` |
| List (JSON) | `/opt/homebrew/bin/colima list --json` |
| Start Portainer | `/opt/homebrew/bin/docker start portainer` |
| Check Portainer exists | `/opt/homebrew/bin/docker ps -a --filter name=portainer --format '{{.Names}}'` |
| Install Portainer | voir commande complète ci-dessous |
| Open UI | `open https://localhost:9443` |

**Commande d'installation Portainer :**
```
docker run -d \
  -p 8000:8000 \
  -p 9443:9443 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

Après `colima start` réussi : attendre socket `~/.colima/default/docker.sock` puis vérifier si container `portainer` existe :
- Existe → `docker start portainer` puis `open https://localhost:9443`
- N'existe pas → mettre à jour menu (afficher "⚠ Portainer non installé" + "Installer Portainer…")

### Détection Portainer

Polling toutes les 5s inclut : `docker ps -a --filter name=portainer --format '{{.Names}}'`  
Résultat vide = non installé. Résultat `portainer` = installé (running ou stopped).

### Gestion d'erreurs
- Start/Stop Colima failure : notification macOS via `UNUserNotificationCenter` avec message d'erreur
- Installation Portainer failure : notification avec stderr tronqué à 200 chars
- Docker socket absent (Colima stopped) : skip les checks Docker silencieusement

## Auto-start

`ServiceManagement.SMAppService.mainApp.register()` (macOS 13+).  
Toggle depuis le menu "Lancer au démarrage". État persisté via `SMAppService.mainApp.status`.

**Important :** l'auto-start concerne uniquement l'app ColimaBar elle-même — pas Colima. Colima ne démarre jamais automatiquement : l'utilisateur clique "Démarrer Colima" manuellement. Au lancement de l'app, ColimaBar affiche l'état actuel (icône grise si Colima stopped).

## Binaries paths

Chemins hardcodés : `/opt/homebrew/bin/colima`, `/opt/homebrew/bin/docker`.  
Colima Homebrew Apple Silicon = chemin fiable.

## Configuration CPU/Mémoire

Sous-menu "⚙ Configuration" dans le menu principal.

### Structure

```
├── ⚙ Configuration
│   ├── CPUs (non-cliquable)
│   │   ├── ✓ 2 CPUs   ← valeur actuelle cochée
│   │   ├── 4 CPUs
│   │   └── 6 CPUs
│   ├── ──────────────
│   └── Mémoire (non-cliquable)
│       ├── 2 GB
│       ├── ✓ 4 GB     ← valeur actuelle cochée
│       ├── 8 GB
│       └── 16 GB
```

### Comportement

Presets disponibles : CPUs = [1, 2, 4, 6, 8], Mémoire = [2, 4, 6, 8, 16] GB.  
Valeur courante lue depuis `colima list --json` (déjà parsé dans le polling).  
Valeurs désirées persistées dans `UserDefaults` (`colima.desiredCPUs`, `colima.desiredMemoryGB`).

- Colima **stopped** → sauvegarde la préférence, appliquée au prochain `colima start --cpu N --memory N`
- Colima **running** → redémarre automatiquement : stop + start avec nouvelles valeurs

## Out of scope

- Gestion de profils Colima multiples
- Dashboard de métriques temps réel
- Support Linux/Intel (Apple Silicon only)
- Mise à jour de Portainer (image pull)

# Spécifications Techniques : Évolutions ColimaBar

Ce document définit les spécifications pour les nouvelles fonctionnalités de **ColimaBar**. L'objectif est de transformer l'utilitaire de barre de menus en une application hybride (Popover + Dashboard complet).

---

## 🏗️ Architecture : Transition Multi-Fenêtres

**Objectif :** Faire évoluer l'application vers un système `NSPopover` (vue rapide) + `NSWindow` (Dashboard persistant).

- **Comportement :**
    - Conserver l'icône de barre de menus et son menu contextuel.
    - Ajouter un bouton **"Ouvrir le Dashboard"** dans le Popover.
    - Implémenter une `NavigationSplitView` (ou Sidebar `NSTableView`) pour naviguer entre : *Containers*, *Volumes*, *Compose*, *Logs* et *Settings*.
- **Contraintes techniques :**
    - Utiliser `NSWindowController` pour garantir une instance unique de la fenêtre.
    - La fermeture de la fenêtre ne doit pas quitter l'application.

---

## 📂 Module : Volume Browser & Transfert de Fichiers

**Objectif :** Explorer et manipuler les fichiers à l'intérieur des volumes Docker.

- **Interface :** Vue en liste affichant `Nom`, `Taille`, `Permissions`.
- **Actions :**
    - **Listing :** Exécuter `ls -la` via `docker exec`.
    - **Download :** Déclencher `docker cp <container>:<path> <local_path>` via un `NSSavePanel`.
    - **Upload :** Déclencher `docker cp <local_path> <container>:<path>` via un `NSOpenPanel`.
- **Contrainte :** Vérifier l'état `Running` du conteneur avant toute opération.

---

## 📝 Module : Édition Docker-Compose

**Objectif :** Modifier la configuration sans quitter l'application.

- **Fonctionnalité :**
    - Localiser le fichier `docker-compose.yml` (via les labels Docker du conteneur).
    - Afficher le contenu dans une `NSTextView` (police monospace).
    - **Bouton "Save & Restart" :** Enregistre et lance `colima ssh -- docker-compose up -d --build`.
- **UX :** Indicateur d'état "modifié" (dirty) si des changements ne sont pas sauvegardés.

---

## 🔍 Module : Analyseur de Logs Intelligent

**Objectif :** Améliorer le diagnostic technique.

- **Fonctionnalité :**
    - **Highlighting :** `ERROR` (rouge), `WARN` (orange), `SUCCESS` (vert).
    - **Recherche :** Barre de filtrage "live" sur le flux de texte.
    - **Smart Action :** Bouton "Expliquer l'erreur" (copie les dernières lignes d'erreur dans le presse-papier avec un prompt pré-rédigé).

---

## 📸 Module : Snapshot Rapide (Colima)

**Objectif :** Sauvegarder l'état de la VM Colima.

- **Commande :** Piloter la création de snapshots via `colima ssh`.
- **Action :** Créer un backup daté du fichier de disque dans `~/.colima/`.
- **Restauration :** Lister les snapshots et permettre un "Rollback" (nécessite l'arrêt de la VM).

---

## 💡 Instructions pour Claude Code

> [!IMPORTANT]
> - Respecter scrupuleusement la séparation entre `ColimaBarCore` (Logique) et `ColimaBar` (UI).
> - Toute exécution de commande doit passer par le `ShellRunner.swift` existant.
> - Ne pas ajouter de logique de parsing Docker directement dans les ViewControllers.

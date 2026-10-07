# Proxhawk-tui — une console texte pour Proxmox VE

[English](README.md) | **Français** | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

Version 2.1.0 · licence AGPL-3.0-or-later

`proxhawk-tui` est une version en mode texte de l'interface web de Proxmox VE
(le GUI servi sur le port 8006). Elle en reproduit la disposition, la
navigation et la plupart des panneaux avec des cadres Unicode, des graphiques
en braille, des icônes Nerd Font et des couleurs ANSI, et n'a besoin de rien
qui ne soit déjà installé sur un nœud Proxmox VE.

![Démo de proxhawk-tui : résumé et HA du datacenter, résumé du nœud, réseau, journal système, scripts communautaires et disques, résumé et options d'une VM](docs/demo.gif)

*Données de démonstration.*

## Points forts

- **Même disposition et mêmes menus que l'interface web** (vérifiés sur les
  définitions de menus de Proxmox VE 9) : barre d'en-tête, arbre des
  ressources (vues Serveur / Dossier / Pool / Stockage), menu de navigation
  par objet, barre d'outils, panneau de contenu et panneau
  *Tâches / Journal du cluster*.
- **Lecture et écriture** : chaque tableau de configuration propose
  *Ajouter / Modifier / Supprimer* (`a` / `e` / `d`). Les dialogues sont
  **générés à partir du schéma de l'API** de l'appel qu'ils effectuent : ils
  offrent les mêmes paramètres, choix et valeurs par défaut que les dialogues
  du GUI, y compris les chaînes de propriétés (`net0`, `scsi0`, `rootfs`...)
  modifiées dans des sous-formulaires.
- **Tout le GUI** : Datacenter (cluster, options, stockages de tous types,
  tâches de sauvegarde, réplication, permissions, utilisateurs, jetons d'API,
  2FA, groupes, pools, rôles, domaines, HA et règles d'affinité, SDN avec
  zones, VNets, sous-réseaux, contrôleurs, IPAM, DNS, pare-feu des VNets,
  fabrics, route maps, listes de préfixes, ACME, pare-feu, serveurs de
  métriques, mappages de ressources et de répertoires, modèles de CPU
  personnalisés, notifications), Nœud (réseau avec appliquer/annuler,
  certificats et commandes ACME, DNS, hosts, heure, services, mises à jour,
  dépôts, disques avec GPT/effacement, LVM, LVM-Thin, Répertoire, ZFS,
  **Ceph** avec assistant d'installation, moniteurs, OSD, CephFS, pools), VM
  et conteneurs (matériel/ressources, cloud-init, options, instantanés,
  sauvegardes, restauration, pare-feu, permissions, HA, clonage, modèle,
  migration).
- **Console** : `qm terminal` pour les VM avec port série, **SSH pour les VM
  Linux sans port série** (IP trouvée par l'agent invité, la table de
  voisinage ou un balayage du réseau du pont), `pct enter` pour les
  conteneurs, shell du nœud.
- **Empreinte minimale** : du bash pur + le Perl et `pvesh` fournis avec
  Proxmox VE. `whiptail` (fourni aussi) ou `dialog` pour les dialogues. Pas
  de démon, aucune dépendance, rien d'écrit en dehors de
  `~/.config/proxhawk-tui` et d'un répertoire temporaire.
- **Rapide** : un petit assistant Perl persistant charge l'API une seule fois
  et répond en quelques millisecondes, au lieu de lancer `pvesh` (1 à 2 s) à
  chaque lecture.
- **Testé** : `tools/integration-test.sh` pilote chaque panneau et chaque
  action sur un vrai nœud et vérifie chaque écriture par l'API (voir
  [docs/TESTING.md](docs/TESTING.md)).
- **Modulaire** : chaque panneau est une petite fonction dans `views/` ; les
  thèmes, jeux d'icônes et langues sont de simples fichiers.
- **Clavier et souris**, 256 couleurs, truecolor ou 8 couleurs, icônes Nerd
  Font, Unicode, ASCII pur ou sans icônes. Raccourcis clavier et couleurs
  configurables ; dix thèmes (Dracula, Nord, Gruvbox, Catppuccin, Tokyo
  Night...).
- **34 langues** : anglais, français, espagnol, allemand, chinois simplifié
  et russe complets ; les autres langues du GUI grâce au catalogue officiel
  de Proxmox VE installé sur le nœud (mêmes mots que le GUI). Voir
  [docs/I18N.md](docs/I18N.md).
- **Actions groupées et file d'attente** : marquez des invités avec `Espace`
  dans les grilles de recherche pour les démarrer, les arrêter ou les
  sauvegarder ensemble ; les actions sur un invité occupé sont mises en file.
- **Scriptable** : `proxhawk-tui guests list -o table`,
  `proxhawk-tui guests start 101`, `proxhawk-tui api get /version`...
  (sortie JSON ou tableau, voir [docs/CLI.md](docs/CLI.md)).
- **Plugins** : entrées de menu optionnelles (installateur des
  community-scripts, inventaire Ansible) — voir
  [docs/EXTENDING.md](docs/EXTENDING.md#plugins).

## Prérequis

| Composant | Remarques |
|-----------|-----------|
| Nœud Proxmox VE 7, 8 ou 9 | à lancer en `root` sur le nœud, directement ou avec `sudo` (voir [Qui peut le lancer](#qui-peut-le-lancer)) |
| bash ≥ 4.3 | standard |
| perl + modules Perl de PVE | fournis avec Proxmox VE |
| `whiptail` ou `dialog` | `whiptail` est installé par défaut ; sinon des invites intégrées |
| `less` | optionnel, pour afficher les journaux |
| Un terminal UTF-8, ≥ 80×18 | 256 couleurs recommandées ; une Nerd Font pour les icônes d'origine |

## Installation

### En une ligne (paquet de la dernière version)

Sur un nœud Proxmox VE, en root (ou avec `sudo`), une ligne installe la
dernière version (le `.deb` est vérifié avec sa somme SHA-256 avant que `apt`
ne l'installe) :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdindon/proxhawk-tui/main/install.sh)"
proxhawk-tui
```

Avec sudo : `sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdindon/proxhawk-tui/main/install.sh)"`,
puis `sudo proxhawk-tui`.

Désinstaller : `apt remove proxhawk-tui`. Vous pouvez lire
[install.sh](install.sh) avant de le lancer ; les paquets sont aussi sur la
[page des releases](https://github.com/Mrdindon/proxhawk-tui/releases).

### Avec git clone

La branche `main` contient les versions publiées (tags `vX.Y.Z`) ; `develop`
est le travail en cours.

```bash
apt install git            # si git n'est pas encore installé
git clone https://github.com/Mrdindon/proxhawk-tui.git /opt/proxhawk-tui
cd /opt/proxhawk-tui
./proxhawk-tui             # lancer sur place, ou :
./install.sh               # commande "proxhawk-tui" (lien dans /usr/local/bin)
```

- **Mise à jour** : `proxhawk-tui upgrade` (voir [Mise à jour](#mise-à-jour)).
- **Une version précise** : `git checkout vX.Y.Z` (retour à la dernière : `git checkout main`).
- **Désinstaller** : `./install.sh --uninstall`, puis supprimer le répertoire.
- N'importe quel répertoire convient ; `./install.sh --prefix DIR` place la
  commande ailleurs que dans `/usr/local/bin`.
- Ne mélangez pas les deux méthodes : retirez le paquet
  (`apt remove proxhawk-tui`) avant d'utiliser un clone, ou l'inverse.

### Mise à jour

```bash
proxhawk-tui upgrade --check    # une nouvelle version existe ? (code de sortie 10 si oui)
proxhawk-tui upgrade            # mettre à jour (demande confirmation ; --yes pour l'éviter)
```

`upgrade` détecte comment proxhawk-tui a été installé :

| Installé avec | Ce que fait `upgrade` |
|---|---|
| la ligne d'installation (paquet `.deb`) | télécharge le `.deb` de la dernière version, vérifie sa somme SHA-256 et l'installe avec `apt` (en root ou avec `sudo`) |
| `git clone` | `git fetch`, affiche la nouvelle version et ses commits, puis `git pull --ff-only` de la branche courante (refusé s'il y a des modifications locales) |
| une archive décompressée à la main | indique la version disponible et comment l'installer |

`--version X.Y.Z` installe une version précise (paquet). Relancer la ligne
d'installation met aussi le paquet à jour.

### Qui peut le lancer

proxhawk-tui utilise directement la pile locale de l'API Proxmox VE, comme
`pvesh` (pas de HTTP, pas de ticket) : sur le nœud, il doit tourner en
**root**, directement ou avec `sudo`. Les **permissions Proxmox VE** sont un
niveau distinct : au démarrage, proxhawk-tui demande avec quel utilisateur
Proxmox VE agir (`root@pam`, `alice@pve`...), et les permissions de cet
utilisateur s'appliquent, comme dans le GUI (voir
[Running as another user](docs/CONFIGURATION.md#running-as-another-user)).
Lancer proxhawk-tui depuis un compte Linux non root demanderait l'API en
HTTPS avec un jeton : pas encore pris en charge.

Options utiles :

```bash
proxhawk-tui --glyphs nerd       # icônes Font Awesome du GUI (il faut une Nerd Font
                                 # dans VOTRE terminal, voir docs/CONFIGURATION.md)
proxhawk-tui --theme dark        # aspect « Proxmox Dark »
proxhawk-tui --lang fr           # langue de l'interface (par défaut : automatique)
proxhawk-tui --select qemu/100   # ouvrir directement sur la VM 100
proxhawk-tui --backend pvesh     # ne pas utiliser l'assistant API persistant
```

## Touches essentielles

| Touche | Action |
|-----|--------|
| `↑` `↓` / `j` `k`, `PgUp` `PgDn`, `Home` `End` | se déplacer dans le panneau actif |
| `Tab` / `Shift+Tab` | panneau suivant / précédent (arbre → menu → contenu → tâches) |
| `←` `→` | réduire / développer dans l'arbre, passer d'un panneau à l'autre |
| `Entrée` | ouvrir / agir sur la ligne sélectionnée |
| `/` | rechercher des ressources |
| `v` | changer la vue de l'arbre (Serveur, Dossier, Pool, Stockage) |
| `a` `e` `d` | Ajouter, Modifier, Supprimer dans les tableaux de configuration |
| `s` `h` `c` `H` `m` | Démarrer, menu Arrêter, Console, SSH, Plus (invités) |
| `b` `h` `S` `B` | Redémarrer, Arrêter, Shell, Actions en masse (nœuds) |
| `t` | changer la période des graphiques dans les résumés |
| `l` | basculer *Tâches* / *Journal du cluster* |
| `r` / `F5` | actualiser |
| `F1` / `?` | fenêtre d'aide : touches du panneau actuel |
| `F2` `F3` `F4` | boutons de l'en-tête : Créer une VM, Créer un CT, menu utilisateur (réglages, icônes, langue...) |
| `Espace` `m` `f` | marquer un invité, actions groupées, filtre (grilles de recherche) |
| `w` | URL de la console navigateur (noVNC / xterm.js) d'un invité ou d'un nœud |
| `F6` | suspendre / reprendre l'actualisation automatique |
| `q` / `F10` | quitter |

La liste complète est dans [docs/USAGE.md](docs/USAGE.md).

## Documentation

La documentation détaillée est en anglais.

| Document | Contenu |
|----------|---------|
| [docs/USAGE.md](docs/USAGE.md) | guide de l'utilisateur : écran, navigation, chaque panneau et chaque action |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | fichier de configuration, raccourcis, couleurs, ligne de commande, plugins, thèmes, jeux d'icônes |
| [docs/CLI.md](docs/CLI.md) | commandes non interactives (JSON / tableau) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | modules, flux de données, protocole de l'assistant API, rendu |
| [docs/EXTENDING.md](docs/EXTENDING.md) | ajouter un panneau, une action, un thème ou un jeu d'icônes |
| [docs/I18N.md](docs/I18N.md) | langues, traductions, ajouter une langue |
| [docs/TESTING.md](docs/TESTING.md) | lint, autotest, tests d'écran, tests d'intégration en lecture/écriture |
| [AGENTS.md](AGENTS.md) | guide court pour les agents de code |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | notes internes : choix de conception, comportements de Proxmox VE, procédure de publication |
| [CHANGELOG.md](CHANGELOG.md) | versions |
| [docs/COMPARISON-devnullvoid-pvetui.md](docs/COMPARISON-devnullvoid-pvetui.md) | analyse de devnullvoid/pvetui et idées d'amélioration |

## Organisation du projet

```
proxhawk-tui     point d'entrée (arguments, boucle principale, clavier/souris)
install.sh       installation / désinstallation (paquet depuis GitHub, ou lien)
lib/             modules (terminal, API, widgets, mise en page, actions...)
lib/broker.pl    assistant API persistant (Perl, modules PVE)
views/           un fichier par type d'objet (datacenter, node, qemu, lxc...)
themes/          thèmes de couleurs
plugins/         plugins optionnels (activés dans F4 > Plugins)
lang/            langues (en, fr, es, de, zh_CN, ru + TEMPLATE.sh)
conf/            configuration d'exemple
tests/screens/   scénarios des tests d'écran, réponses API enregistrées, écrans de référence
tools/           lint.sh, selftest.sh, screen-test.sh, integration-test.sh,
                 i18n-extract.sh, i18n-check.sh, make-release.sh, make-deb.sh
docs/            documentation
```

## Limites

- Les consoles graphiques (noVNC, SPICE) ne peuvent pas s'afficher dans un
  terminal : console série, SSH ou `pct enter` les remplacent (`w` donne
  l'URL de la console noVNC pour le navigateur).
- Fonctionne uniquement sur un nœud du cluster (pas encore de connexion
  distante à l'API).
- proxhawk-tui tourne en `root` sur un nœud du cluster (directement ou avec
  `sudo`) : il utilise directement la pile locale de l'API (pas de HTTP, pas
  de ticket), exactement comme `pvesh` ; les permissions Proxmox VE
  appliquées sont celles de l'utilisateur choisi au démarrage.
- Les téléversements (ISO, modèles, snippets) prennent un fichier du nœud
  lui-même.

## Comment il a été fait

proxhawk-tui a été écrit avec [Claude Code](https://claude.com/claude-code),
l'agent de programmation d'Anthropic, dirigé et relu par l'auteur, et testé
sur un vrai nœud Proxmox VE (voir [docs/TESTING.md](docs/TESTING.md)). Les
notes de conception et les leçons apprises sont dans
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) ; [AGENTS.md](AGENTS.md) est le
guide donné aux agents de code qui y travaillent.

## Licence et nom

proxhawk-tui est un logiciel libre sous **licence publique générale GNU
Affero v3.0 ou ultérieure** (voir [LICENSE](LICENSE)), la licence de Proxmox
VE elle-même, dont l'assistant API charge les modules Perl.

Proxmox® est une marque déposée de Proxmox Server Solutions GmbH.
proxhawk-tui est un projet indépendant, ni affilié à Proxmox Server
Solutions GmbH ni approuvé par elle. Il s'appelait *pvetui* (1.0 – 1.1),
puis *pvetty* (1.2 – 1.3) ; les réglages de ces versions sont repris
automatiquement.

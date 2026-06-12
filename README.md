# 🎯 Repère — Retrouve tes potes en festival

App iOS qui permet de retrouver ses amis en festival ou en boîte de nuit **sans réseau mobile**.

Utilise le **GPS** (satellites) + **Bluetooth** (peer-to-peer) pour afficher une flèche directionnelle vers tes potes.

---

## 🚀 Comment obtenir le fichier IPA (sans Mac)

### Étape 1 : Créer un repo GitHub

1. Va sur [github.com](https://github.com) et connecte-toi (ou crée un compte gratuit)
2. Clique sur **"New repository"** (bouton vert en haut à droite)
3. Nom du repo : `repere`
4. Laisse en **Public** (nécessaire pour GitHub Actions gratuit)
5. Clique **"Create repository"**

### Étape 2 : Pousser le code sur GitHub

Ouvre un terminal (PowerShell) dans le dossier `repère` et exécute :

```powershell
cd C:\Users\engue\Desktop\repère

git init
git add .
git commit -m "🎯 Repère v1.0 - Initial commit"
git branch -M main
git remote add origin https://github.com/TON_USERNAME/repere.git
git push -u origin main
```

> ⚠️ Remplace `TON_USERNAME` par ton nom d'utilisateur GitHub.

### Étape 3 : Le build se lance automatiquement !

1. Va sur ton repo GitHub → onglet **"Actions"**
2. Tu verras le workflow **"Build Repere IPA"** en cours d'exécution 🔄
3. Attends ~5 minutes que le build finisse ✅
4. Clique sur le build terminé → section **"Artifacts"**
5. Télécharge **`Repere-IPA`** → c'est ton fichier .IPA ! 🎉

### Étape 4 : Installer sur ton iPhone

Tu as dit que tu as de quoi installer un IPA sur ton iPhone, donc utilise ta méthode habituelle (AltStore, TrollStore, Sideloadly, etc.)

---

## 📱 Comment ça marche

### Principe
1. **Ouvre l'app** → entre ton pseudo
2. **Crée un groupe** → un code à 4 chiffres est généré
3. **Partage le code** à tes potes (avant d'arriver au festival !)
4. **Tes potes rejoignent** le groupe avec le code
5. **La flèche** pointe vers chaque pote avec la distance 🧭

### Technologies utilisées (tout fonctionne sans réseau !)
- **GPS** → satellites (pas besoin de 4G/5G)
- **Bluetooth** → communication peer-to-peer entre iPhones
- **UWB (U1)** → direction ultra-précise quand < 30m (iPhone 11+)
- **Boussole** → orientation du téléphone

---

## 🏗️ Architecture

```
Repere/
├── RepereApp.swift              → Point d'entrée
├── Info.plist                   → Permissions iOS
├── Models/
│   └── Peer.swift               → Modèle d'un ami
├── Managers/
│   ├── LocationManager.swift    → GPS + Boussole
│   ├── MultipeerManager.swift   → Bluetooth P2P
│   └── NearbyInteractionManager.swift → UWB
├── Views/
│   ├── HomeView.swift           → Écran d'accueil
│   ├── RadarView.swift          → Vue principale (flèche)
│   ├── ArrowView.swift          → Composant flèche
│   ├── PeerListView.swift       → Liste des potes
│   └── SettingsView.swift       → Paramètres
└── Utils/
    ├── DirectionCalculator.swift → Calculs direction/distance
    └── HapticManager.swift      → Vibrations
```

---

## ⚠️ Limites connues (V1)

| Limite | Détail |
|---|---|
| Portée Bluetooth | ~70-100m max entre deux iPhones |
| GPS en intérieur | Moins précis en boîte de nuit (fonctionne mieux en festival) |
| UWB | iPhone 11+ uniquement |
| Re-signature | Avec AltStore gratuit, à refaire tous les 7 jours |

---

## 🔮 Idées pour la V2

- [ ] Réseau mesh (A→B→C pour étendre la portée)
- [ ] Mode "point de rendez-vous" (fixer un lieu sur la carte)
- [ ] Partage de messages courts via Bluetooth
- [ ] Mode batterie économie
- [ ] Support Android (via BLE cross-platform)
- [ ] Icône de l'app personnalisée

---

## 📋 Pré-requis

- iPhone avec iOS 16+
- Un moyen d'installer des IPA (AltStore, TrollStore, etc.)
- Un compte GitHub (gratuit)

## 📄 Licence

Projet personnel — Tous droits réservés.

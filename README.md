# GK Crédit Android — Version Flutter

## Identifiants initiaux
- Utilisateur : `admin`
- Mot de passe : `1234`

## Fonctionnalités
- Authentification locale
- SQLite avec création automatique des tables
- Clients
- Articles et stock
- Vente à crédit
- Avance et paiements partiels
- Calcul automatique de la dette
- Échéances et retards
- Reçus PDF / impression / partage
- Rapports
- Export de sauvegarde
- Déconnexion et persistance de session

## Générer l'APK

1. Installer Flutter SDK et Android Studio.
2. Ouvrir le dossier du projet.
3. Dans le terminal :
```bash
flutter create .
flutter pub get
flutter build apk --release
```

L'APK sera normalement généré dans :
`build/app/outputs/flutter-apk/app-release.apk`

## Important
Le projet est livré avec le code Flutter. La compilation de l'APK nécessite Flutter + Android SDK, qui ne sont pas installés dans l'environnement de génération de ce fichier.

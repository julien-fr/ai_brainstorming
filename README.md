# Plateforme simplifiée de Brainstorming IA

## Description

Ce projet est une plateforme simplifiée de débat IA en temps réel conçue pour faciliter des sessions de brainstorming structurées en utilisant plusieurs agents IA. Elle permet aux chercheurs, aux équipes et aux développeurs d'exploiter la puissance de l'IA pour explorer des idées, discuter de concepts et parvenir à un consensus dans un environnement dynamique et interactif.

## Fonctionnalités

- **Débats Multi-agents :** Engagez plusieurs agents IA avec différents modèles (GPT-4o, Gemini, Mistral) et paramètres dans des débats en temps réel.
- **Interaction en Temps Réel :** Suivez les débats et interagissez avec la plateforme en temps réel via les WebSockets.
- **Modération IA et Détection de Consensus :** Bénéficiez d'une modération pilotée par l'IA et d'une détection automatique de consensus pendant les débats.
- **Stockage et Analyse de l'Historique des Débats :** Stockez et analysez les données des débats historiques pour des informations et des examens futurs.
- **Architecture Extensible :** Intégrez facilement de nouveaux modèles d'IA et fonctionnalités grâce à une conception modulaire et extensible.
- **Résumés et Article Final par Email :** Recevez des résumés intermédiaires pendant le débat et un article final complet par email à la fin du débat. L'adresse email de réception est configurable via le fichier `.env`.

## Technologies Utilisées

- **Backend :** Python 3.12, FastAPI
- **Frontend :** Flutter Web
- **Base de données :** SQLite
- **Communication en temps réel :** WebSockets
- **Modèles IA :** OpenAI GPT-4o, Google Gemini & Mistral API (intégrations futures)

## Instructions d'Installation

### Backend

1. Naviguez vers le répertoire `backend` : `cd backend`
2. **Créez un environnement virtuel (recommandé) :** `python3.12 -m venv venv`
3. **Activez l'environnement virtuel :** `source venv/bin/activate`
4. **Copiez le fichier `.env_example` vers `.env` :** `cp .env_example .env`
   - Le fichier `.env` contiendra vos variables d'environnement. Initialement, il est configuré avec des valeurs par défaut ou des placeholders.
5. **Modifiez le fichier `.env` avec vos propres configurations :**
   - Ouvrez le fichier `.env` et remplacez les valeurs par défaut par vos propres clés API, adresses email, etc. Ceci est crucial pour la configuration de l'accès aux APIs externes et aux services d'email pour la réception des résumés de débats.
6. **Installez les dépendances à partir du fichier `requirements.txt` :** `pip install -r requirements.txt`
7. Lancez le serveur backend : `python main.py`

**Note:**
- Le fichier `requirements.txt` à la racine du répertoire `backend` liste toutes les librairies Python nécessaires pour le backend.
- Le fichier `.env_example` sert de modèle pour la configuration des variables d'environnement. Il est important de le copier en `.env` et de le modifier avec vos informations sensibles.

### Frontend

1. Naviguez vers le répertoire `frontend` : `cd ../frontend`
2. **Installez les dépendances Flutter :** `flutter pub get`
   - Cette commande télécharge toutes les dépendances listées dans le fichier `pubspec.yaml` du frontend, qui est essentiel pour que l'application Flutter fonctionne correctement.
3. **Lancez l'application frontend :** `flutter run`
   - Cette commande compile l'application Flutter et la lance. Assurez-vous d'avoir un émulateur ou un appareil connecté pour visualiser l'application.

## Utilisation

Actuellement, la plateforme supporte :

- La création de nouveaux débats.
- La liste des débats existants.
- La sélection et la visualisation des débats.
- La personnalisation des agents (rôle, contexte, modèle et température).

Pour commencer à utiliser la plateforme :

1. Lancez les applications backend et frontend.
2. Accédez au frontend dans votre navigateur web.
3. Créez un nouveau débat.
4. Ajoutez et personnalisez vos agents (rôle, contexte, modèle et température).
5. Configurez l'adresse email de réception des résumés dans le fichier `.env` du backend.

## Contribution

Les contributions sont les bienvenues !
Je veux mettre en place une architecture de coding agent dans laquelle :

* OpenCode tourne LOCALLEMENT sur mon ordinateur Ubuntu.
* Mon repository et tous mes fichiers de code restent LOCALLEMENT sur mon ordinateur.
* Les tools d'OpenCode (read, write, edit, bash, grep, git, tests, Python, etc.) sont exécutés LOCALLEMENT.
* Le LLM est exécuté sur un GPU distant RunPod.
* Le modèle que je veux utiliser est Qwen3.8-27B.
* Le serveur d'inférence doit utiliser vLLM.
* vLLM doit exposer une API OpenAI-compatible.
* OpenCode doit utiliser cette API comme provider distant.
* Le tool calling doit fonctionner correctement.
* Le serveur distant ne doit jamais avoir besoin d'accéder au filesystem de mon ordinateur.

Architecture cible :

```
                     INTERNET
                        │
                        │ OpenAI-compatible API
                        ▼
```

┌───────────────────────────────────────────────┐
│                 RUNPOD POD                    │
│                                               │
│             RTX 5090 32 GB                    │
│                    │                          │
│                  Docker                       │
│                    │                          │
│                   vLLM                        │
│                    │                          │
│               Qwen3.8-27B                     │
│                                               │
└────────────────────▲──────────────────────────┘
│
│ HTTPS
│
┌────────────────────┴──────────────────────────┐
│                 MON PC                        │
│                                               │
│                 OpenCode                      │
│                    │                          │
│        ┌───────────┼────────────┐             │
│        ▼           ▼            ▼             │
│    filesystem     git        terminal        │
│        │           │            │             │
│        └───────────┴────────────┘             │
│                                               │
│          repository LOCAL uniquement          │
└───────────────────────────────────────────────┘

IMPORTANT :
Le serveur RunPod ne doit PAS monter mon repository.
Il ne doit PAS avoir accès à mon filesystem local.
Il ne doit PAS exécuter les tools d'OpenCode.
Il sert uniquement à faire tourner le modèle et à répondre aux requêtes LLM.

==================================================
ÉTAPE 1 — AUDIT ET DOCUMENTATION
================================

Avant toute modification, vérifie les informations actuelles dans les documentations officielles :

* RunPod Pods
* RunPod pricing
* RunPod RTX 5090
* vLLM
* Qwen3.8-27B
* OpenCode
* OpenAI-compatible API de vLLM

Vérifie particulièrement :

1. Le nom exact du modèle Qwen3.8-27B actuellement disponible.
2. La méthode recommandée pour le faire tourner avec vLLM.
3. La compatibilité avec RTX 5090 32 GB.
4. Les paramètres de quantification disponibles et pertinents.
5. Le contexte réellement réaliste avec 32 GB de VRAM.
6. Le parser de reasoning approprié.
7. Le parser de tool calling approprié.
8. Les paramètres vLLM nécessaires au tool calling.
9. La syntaxe actuelle d'un provider OpenAI-compatible dans OpenCode.

NE SUPPOSE PAS que des configurations trouvées dans d'anciens exemples sont encore valables.

Si Qwen3.8-27B nécessite une variante particulière ou une quantification particulière pour tenir sur 32 GB, explique-le clairement.

==================================================
ÉTAPE 2 — CRÉER LE POD RUNPOD
=============================

Je veux utiliser un RunPod Pod avec RTX 5090 32 GB.

Donne-moi les paramètres exacts à choisir dans l'interface RunPod :

* GPU
* image Docker de base
* volume
* taille du disque
* network volume si nécessaire
* ports à exposer
* variables d'environnement
* autres paramètres pertinents

Je veux que les poids du modèle soient conservés entre les redémarrages du Pod.

Ne télécharge pas le modèle à chaque démarrage si cela peut être évité.

==================================================
ÉTAPE 3 — DOCKER + vLLM
=======================

Construis un environnement Docker reproductible.

Je veux au minimum :

runpod-qwen/
├── Dockerfile
├── start.sh
├── .env.example
├── README.md
├── scripts/
│   ├── download_model.sh
│   └── test_api.py
└── tests/
├── test_chat.py
└── test_tool_call.py

Ajoute d'autres fichiers si nécessaire.

Le conteneur doit lancer vLLM avec Qwen3.8-27B.

Détermine correctement les paramètres :

* model
* served-model-name
* dtype
* quantization
* max-model-len
* gpu-memory-utilization
* tensor-parallel-size
* enable-auto-tool-choice
* tool-call-parser
* reasoning-parser
* éventuellement max-num-seqs
* éventuellement max-num-batched-tokens
* autres paramètres nécessaires

Pour chaque paramètre important, explique pourquoi tu l'as choisi.

PRIORITÉS :

1. stabilité
2. tool calling fiable
3. faible latence
4. vitesse de génération
5. contexte suffisamment important pour un coding agent

Ne cherche pas à utiliser artificiellement 262k tokens si cela n'est pas réaliste sur 32 GB.

==================================================
ÉTAPE 4 — TOOL CALLING
======================

C'est un point CRITIQUE.

Je veux vérifier que Qwen3.8-27B + vLLM produit de vrais tool calls structurés compatibles avec l'API OpenAI.

Ne considère PAS le setup comme terminé simplement parce que :

GET /v1/models

et :

POST /v1/chat/completions

fonctionnent.

Crée un test réel avec un tool fictif.

Exemple :

get_weather(city)

Le modèle doit produire un vrai :

tool_calls[]

avec :

* function.name
* function.arguments

et des arguments JSON valides.

Teste également la boucle complète :

1. requête utilisateur
2. définition des tools
3. réponse tool_call du modèle
4. exécution fictive du tool
5. retour du résultat au modèle
6. réponse finale

Si Qwen produit un pseudo-tool-call sous forme de texte, considère le test comme échoué.

Diagnostique et corrige la configuration vLLM.

==================================================
ÉTAPE 5 — TEST DU SERVEUR
=========================

Fournis des commandes permettant depuis mon PC de tester :

GET /v1/models

puis une requête simple :

POST /v1/chat/completions

puis le test de tool calling.

Utilise curl et/ou Python.

L'API doit être protégée par une authentification.

Ne laisse pas une API vLLM complètement ouverte sur Internet.

==================================================
ÉTAPE 6 — RÉSEAU / SÉCURITÉ
===========================

Analyse la meilleure manière de connecter mon PC au Pod.

Compare :

A. port HTTP/HTTPS exposé par RunPod
B. tunnel SSH
C. VPN / Tailscale / WireGuard

Pour un premier setup, recommande la solution la plus simple qui reste raisonnablement sécurisée.

Je veux minimiser les ports exposés.

Le serveur distant ne doit avoir aucun accès entrant vers le filesystem de mon PC.

==================================================
ÉTAPE 7 — CONFIGURATION OPENCODE
================================

Je veux ensuite connecter OpenCode installé sur mon PC à mon serveur vLLM distant.

Fournis la configuration exacte et actuelle d'OpenCode.

Je veux un `opencode.json` complet.

Utilise un provider OpenAI-compatible avec :

* baseURL
* API key via variable d'environnement
* model ID
* capabilities appropriées
* support du tool calling

La configuration doit utiliser Qwen3.8-27B.

IMPORTANT :

OpenCode reste l'agent local.

Le fonctionnement attendu est :

USER
↓
OpenCode local
↓
requête LLM
↓
RunPod / vLLM / Qwen3.8
↓
tool call
↓
OpenCode local
↓
exécution du tool LOCAL
↓
résultat du tool
↓
RunPod / Qwen3.8
↓
réponse
↓
OpenCode local

Le modèle distant ne doit jamais recevoir un accès direct aux tools ou au filesystem.

==================================================
ÉTAPE 8 — TEST AVEC UN VRAI FICHIER LOCAL
=========================================

Une fois l'intégration OpenCode terminée, crée une procédure de test réelle.

Créer localement :

test_project/
└── hello.py

Puis demander à OpenCode quelque chose comme :

"Lis hello.py, explique son fonctionnement puis ajoute une fonction permettant de calculer le carré d'un nombre et écris un test."

Je veux vérifier que :

1. OpenCode lit le fichier LOCAL.
2. Le contenu pertinent est envoyé à Qwen.
3. Qwen génère les tool calls.
4. OpenCode exécute les tools LOCALLEMENT.
5. Le fichier est modifié LOCALLEMENT.
6. Les tests sont exécutés LOCALLEMENT.
7. Qwen reçoit les résultats des tools.
8. Le modèle produit une réponse finale.

Documente précisément ce qui se passe à chaque étape.

==================================================
ÉTAPE 9 — CONFIDENTIALITÉ
=========================

Explique précisément la frontière entre local et distant.

Je veux notamment savoir :

* quels fichiers sont susceptibles d'être envoyés au LLM ;
* quand leur contenu est envoyé ;
* si OpenCode peut envoyer plusieurs fichiers ;
* si le repository entier est envoyé ou seulement le contexte sélectionné ;
* si les commandes shell sont exécutées sur RunPod ou localement ;
* si Git est local ou distant ;
* si les logs vLLM contiennent le contenu des prompts ;
* comment minimiser les logs contenant du code.

Je veux que le README documente clairement ce modèle de sécurité.

==================================================
ÉTAPE 10 — PERFORMANCE
======================

Pour RTX 5090 32 GB + Qwen3.8-27B :

donne-moi une configuration initiale raisonnable pour un coding agent.

Je veux mesurer :

* tokens/s
* TTFT
* latence totale
* VRAM utilisée
* longueur de contexte
* comportement avec plusieurs requêtes simultanées

Crée éventuellement un petit benchmark Python.

Je veux également distinguer :

* prompt processing
* time to first token
* generation speed
* total request time

==================================================
ÉTAPE 11 — MULTI-AGENTS / CONCURRENCE
=====================================

Je souhaite éventuellement utiliser plus tard les subagents d'OpenCode.

Analyse si un seul vLLM sur une RTX 5090 peut gérer plusieurs requêtes simultanées.

Explique :

* continuous batching
* max-num-seqs
* concurrence
* impact sur la latence
* impact sur le contexte
* limites d'une seule RTX 5090

Ne mets PAS en place plusieurs GPUs pour l'instant.

Je veux d'abord un système mono-GPU stable.

==================================================
ÉTAPE 12 — LIVRABLE FINAL
=========================

À la fin, donne-moi :

1. Architecture finale.
2. Tous les fichiers créés avec leur contenu COMPLET.
3. Dockerfile complet.
4. Script de lancement complet.
5. Commandes RunPod exactes.
6. Commandes Docker exactes.
7. Configuration vLLM exacte.
8. Configuration OpenCode exacte.
9. Variables d'environnement nécessaires.
10. Tests API.
11. Test tool calling.
12. Test OpenCode avec fichier local.
13. Procédure de diagnostic.
14. Paramètres de performance.
15. Estimation VRAM.
16. Limite de contexte réaliste.
17. Explication sécurité/confidentialité.

IMPORTANT :

* Ne remplace pas Qwen3.8-27B par un autre modèle sans me prévenir.
* Ne remplace pas vLLM par Ollama.
* Ne déplace pas OpenCode sur RunPod.
* Ne déplace pas mon repository sur RunPod.
* Ne monte pas mon filesystem local dans le Pod.
* Ne fais pas exécuter les tools locaux par le serveur distant.
* Ne laisse pas une API non authentifiée exposée publiquement.
* Ne modifie pas mon installation locale Ubuntu sans me prévenir.

Avant toute modification destructive ou installation sur ma machine locale, demande confirmation.

Pour le serveur RunPod, en revanche, tu peux créer librement les fichiers Docker/configuration nécessaires.

Commence par vérifier les documentations officielles actuelles et fais-moi un court résumé des choix techniques avant de générer les fichiers.


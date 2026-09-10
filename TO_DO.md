Tester la nouvel image docker
-> jupytrer lab à tester après fix sur websocket
-> download des models (erreur de download depuis HF à gérer avec si besoin se créer un compte pour augmenter le taux de succeed)

ls -la /opt/ComfyUI/models/checkpoints/

/opt/download_models.sh

  Fix plus durable que je peux appliquer à download_models.sh :
  1. Ajouter un retry avec backoff sur aria2c (--max-tries=5 --retry-wait=15) pour absorber les 429 automatiquement.
  2. Réduire ARIA2_CONN par défaut (8 → 4) pour moins solliciter HF.
  3. Recommander de définir HF_TOKEN (un simple compte HF gratuit suffit, pas besoin de repo gated) — un token authentifié a un quota bien plus élevé que l'accès anonyme, c'est la vraie
     solution long terme.



- Ajouter SG161222/RealVisXL_V5.0 à la liste des modèles

- Zen Creator Guide: settings, prompts,

- Modèle LoRA
- Telkecharger lora existant ? Civit AI ?
https://civitai.com/models/1098033/realism-lora-by-stable-yogi-pony

- tester Qwen 3.8 + Opencode

mettre à jour la config ~/.config/opencode/opencode.json avec la bonne url associée au pod id 



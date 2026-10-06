---
title: Observabilité étendue
navTitle: Observabilité
part: part2
weight: 3
labels:
  events: Événements
tocLabels:
  rum: Expérience utilisateur
---

Au-delà du monitoring applicatif proprement dit, Neurons couvre également les journaux applicatifs, l'expérience réelle des utilisateurs finaux, et un espace de travail dédié à l'investigation transverse d'un incident.

## Logs {#logs}

L'écran « Logs » donne accès aux journaux applicatifs récents, filtrables par niveau de sévérité (info, warning, error, etc.) et par fenêtre de temps. Il est pensé pour être utilisé en complément des traces : une trace montre le déroulement d'une requête, les logs apportent le détail textuel que l'application a choisi d'écrire à un instant donné.

## Événements (Events) {#events}

L'« Observability Event Center » centralise tous les événements générés par la plateforme : dépassement de seuil sur un service, violation d'une règle de santé, etc. Chaque événement a une sévérité et suit un cycle de vie explicite :

- **Ouvert (open)** — l'événement vient d'être détecté et n'a pas encore été traité.
- **Acquitté (acknowledged)** — quelqu'un a pris en charge l'investigation.
- **Résolu (resolved)** — le problème est réglé ; c'est uniquement à partir de ce moment qu'un événement devient éligible à la purge automatique.
- **Supprimé (suppressed)** — l'événement est explicitement mis de côté, par exemple parce qu'il est connu et sans impact.

Un événement ouvert ou acquitté n'est jamais purgé automatiquement, quel que soit son âge — seule la rétention des événements résolus est configurable.

## Expérience utilisateur (RUM) {#rum}

Cet écran, intitulé « Browser Performance » dans l'interface, mesure l'expérience réelle des visiteurs d'une application web (Real User Monitoring). Il combine plusieurs types d'analyse :

- **Web Vitals** — les indicateurs standards de performance perçue : LCP, INP, CLS, FCP et TTFB, avec percentiles et répartition bon / à améliorer / mauvais.
- **Distribution des temps de chargement** — un histogramme des durées de chargement de page avec ses marqueurs de percentiles.
- **Sessions et rejeu (replay)** — chaque session utilisateur peut être reconstituée sous forme de parcours chronologique, et certaines sessions disposent d'un enregistrement rejouable.
- **Signaux de frustration** — détection automatique des clics de rage, clics morts et clics en erreur, qui trahissent une expérience dégradée même sans erreur technique visible.
- **Répartition géographique et par appareil** — navigateur, système d'exploitation, appareil, ou zone géographique.
- **Corrélation avec les transactions métier** — possibilité de voir quelles transactions métier backend sont déclenchées par une page donnée, et inversement.

## Troubleshoot {#troubleshoot}

L'écran « Troubleshoot » est un espace de travail transverse destiné à l'investigation d'un problème en cours, organisé en quatre onglets :

| Onglet | Ce qu'il montre |
|---|---|
| **Slow Response Times** | Répartition des requêtes par tranche de latence (normal, lent, très lent, bloqué) et principaux contributeurs à ces ralentissements. |
| **Errors** | Signatures d'erreurs dominantes sur la fenêtre sélectionnée, avec leur évolution. |
| **Health Rule Violations** | Règles de santé actuellement en violation, avec le contexte nécessaire à l'investigation. |
| **War Rooms** | Suivi manuel des incidents ouverts, avec génération d'un rapport de postmortem par IA. |
{firstcol="30"}

Un mode « comparaison » permet de confronter la fenêtre de temps actuelle à la fenêtre équivalente précédente, ce qui aide à distinguer une variation normale d'une véritable dégradation. Chaque élément identifié peut être ouvert directement dans les écrans Traces, Errors ou Logs déjà filtrés sur le bon contexte.

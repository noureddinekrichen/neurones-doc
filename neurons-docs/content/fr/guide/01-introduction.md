---
title: Introduction
part: intro
weight: 1
labels:
  flow: Comment les données arrivent
---

## Qu'est-ce que Neurons ? {#quest}

Neurons est une plateforme de surveillance de performance applicative (Application Performance Monitoring). Elle collecte automatiquement les traces, les journaux (logs) et les mesures de performance émis par vos applications, les stocke dans un entrepôt de données unique, puis les transforme en tableaux de bord exploitables : santé des services, transactions métier, expérience des utilisateurs finaux, et alertes.

L'objectif est de répondre à trois questions que toute équipe qui exploite une application se pose en permanence : est-ce que ça fonctionne normalement en ce moment, qu'est-ce qui a changé quand un problème est apparu, et jusqu'où puis-je remonter dans le temps pour comprendre un incident passé.

## Comment les données arrivent dans la plateforme {#flow}

Les applications, sites web et applications mobiles sont instrumentés avec OpenTelemetry, un standard ouvert. Cette instrumentation envoie en continu ce qui se passe à un collecteur (OpenTelemetry Collector), qui transmet ensuite ces données à Neurons.

1. Les applications et navigateurs génèrent des **traces** (le détail d'une requête, étape par étape) et des **logs**.
2. Le Collecteur OpenTelemetry les regroupe et les transmet au service d'ingestion de Neurons.
3. Le service d'ingestion vérifie, nettoie et enregistre ces données presque telles quelles dans l'entrepôt de données — très peu de transformation à ce stade, pour ne rien perdre et rester rapide.
4. Des tâches de fond (*workers*) relisent ensuite ces données en continu pour calculer tout ce qui est affiché dans les tableaux de bord : taux de requêtes, taux d'erreur, temps de réponse, carte des dépendances entre services, transactions métier.
5. Les tableaux de bord interrogent ces résultats déjà calculés plutôt que de recalculer à chaque affichage, ce qui les garde rapides même sur de longues périodes.
{.steps}

{{< callout >}}
La quasi-totalité des courbes et tendances affichées dans les écrans (trafic, latence, erreurs dans le temps) proviennent de ces calculs pré-agrégés, pas d'un recalcul sur les données brutes à chaque ouverture d'écran. C'est ce qui permet à la plateforme de rester réactive même avec des mois d'historique.
{{< /callout >}}

## Concepts clés {#concepts}

Quelques termes reviennent dans toute la plateforme et sont utiles à bien distinguer avant de parcourir les écrans :

| Terme | Signification |
|---|---|
| **Application** | Un logiciel instrumenté dans son ensemble (ex. « VisionApp »). Regroupe un ou plusieurs services. |
| **Service** | Un composant applicatif individuel qui reçoit des requêtes (une API, un microservice). |
| **Trace** | Le parcours complet d'une requête, de son point d'entrée jusqu'à tous les appels qu'elle déclenche. |
| **Span** | Une étape individuelle à l'intérieur d'une trace (un appel HTTP, une requête base de données, etc.). |
| **Transaction métier** | Un point d'entrée métier nommé et suivi dans la durée (ex. « Connexion », « Paiement »), détecté automatiquement à partir du trafic récurrent. |
| **Business Journey** | Un entonnoir de conversion qui relie plusieurs pages et transactions métier entre elles, pour suivre un parcours utilisateur de bout en bout. |
| **Événement** | Une alerte ou un signal généré par la plateforme, avec un cycle de vie (ouvert, acquitté, résolu). |
| **Métrique** | Une mesure agrégée dans le temps — calculée par les workers, pas envoyée directement par les applications. |
| **RED** | Les trois indicateurs de base surveillés pour chaque service : Rate (débit), Errors (erreurs), Duration (durée/latence). |
| **RUM** | Real User Monitoring — la mesure de l'expérience réelle des utilisateurs dans leur navigateur ou application mobile. |
{firstcol="26"}

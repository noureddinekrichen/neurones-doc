---
title: Alerting & Notifications
navTitle: Alerting
part: part3
weight: 4
labels:
  health-rules: Règles de santé
  notifications: Politiques & notifications
  incidents: Incidents & War Rooms
---

Le module Alerting regroupe tout ce qui permet à la plateforme de prévenir une équipe plutôt que de simplement afficher des chiffres : définition de seuils, canaux de notification, et suivi manuel d'incidents. L'écran « Alerting » est organisé en six onglets : Overview, Rules, Alerts, Incidents, Policies, Destinations, Templates.

## Règles de santé (Health Rules) {#health-rules}

Une règle de santé définit un seuil sur un indicateur (par exemple : taux d'erreur au-dessus de 20&nbsp;%, ou latence au-dessus de 1500&nbsp;ms), évalué sur un périmètre donné (application, environnement, service). Quand une règle est en violation, elle génère un événement, visible à la fois dans l'écran Events et dans l'onglet « Health Rule Violations » de Troubleshoot.

{{< callout >}}
Pour éviter les fausses alertes sur un trafic anecdotique, un seuil de volume minimal de requêtes est appliqué avant qu'une règle de latence ou de taux d'erreur ne soit évaluée.
{{< /callout >}}

## Politiques, destinations et modèles {#notifications}

Trois briques travaillent ensemble pour transformer un événement en notification effective :

- **Destinations** — les canaux vers lesquels une notification peut être envoyée : e-mail, webhook Slack, webhook Microsoft Teams, webhook générique, ou appel à une API REST. Chaque destination peut être testée avant d'être utilisée en conditions réelles.
- **Modèles (Templates)** — le contenu et la mise en forme d'une notification, réutilisable d'une politique à l'autre.
- **Politiques (Policies)** — la règle qui relie une condition de déclenchement à une ou plusieurs destinations et à un modèle.

## Incidents et War Rooms {#incidents}

Un incident peut être ouvert manuellement dès qu'une équipe commence à investiguer un problème, indépendamment des événements automatiques. Il regroupe les services concernés, un statut (ouvert / résolu) et des notes libres. L'onglet « War Rooms » de Troubleshoot est l'endroit où ces incidents sont suivis, et propose la génération d'un rapport de postmortem par IA une fois l'incident résolu.

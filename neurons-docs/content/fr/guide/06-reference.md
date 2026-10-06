---
title: Référence
part: ref
weight: 6
---

## API de requêtage {#api}

Neurons expose une API HTTP qui alimente l'ensemble des écrans décrits dans ce document. Chaque appel doit présenter un jeton dans l'en-tête `X-Neurones-Token`, à l'exception d'une poignée d'endpoints techniques.

| Catégorie | Endpoints | Contenu |
|---|---|---|
| Catalogue | 4 | Applications, environnements, agrégats par application. |
| Services | 3 | Liste des services, métriques, carte de service. |
| Traces | 8 | Recherche, filtres, carte de service par traces, détail d'une trace. |
| Logs | 2 | Liste et volume des journaux. |
| RUM | 42 | Vue d'ensemble, Web Vitals, sessions, replay, parcours, erreurs front, géographie. |
| Transactions métier | 20 | Catalogue, configuration, groupes, notifications, carte de flux. |
| Règles de détection BT | 5 | Création, liste, mise à jour, suppression, priorisation. |
| Business Journeys | 6 | Création, liste, détail, mise à jour, suppression, entonnoir. |
| Événements | 15 | Liste, création, comptage, résumé mensuel, rétention, purge, cycle de vie. |
| Gestion externe des événements | 3 | Paramétrage du transfert vers un outil externe. |
| Règles de santé | 7 | Création, liste, détail, évaluation, contexte d'investigation. |
| Incidents | 3 | Création, liste, mise à jour. |
| Alerting | 18 | Vue d'ensemble, destinations, modèles, politiques. |
| Webhooks | 1 | Réception d'alertes de transaction, authentifiée par signature. |
| Collecteur OpenTelemetry | 4 | Enregistrement, récupération et rapport de configuration d'un agent distant. |
| Troubleshoot | 8 | Contributeurs, signatures d'erreurs, comparaison de fenêtres. |
| Base de données | 2 | Statistiques et métriques des appels sortants vers une base de données. |
| Source de données | 2 | Cluster Vertica actif et bascule immédiate. |
| Ingestion (OTLP) | 3 | Réception des traces, logs et métriques au format OpenTelemetry. |
| Exploitation | 2 | Vérification de santé et export Prometheus, sans authentification. |
{mono="2"}

Résumé destiné à situer les capacités de la plateforme ; pour le détail technique de chaque paramètre, consulter la documentation Swagger interactive publiée par le service (chemin `/docs`).
{.ref-note}

## Glossaire {#glossary}

| Terme | Définition |
|---|---|
| **APM** | Application Performance Monitoring — surveillance de la performance des applications. |
| **Span** | Une étape individuelle à l'intérieur d'une trace. |
| **Trace** | L'ensemble des spans d'une requête, reliés entre eux. |
| **RED** | Rate, Errors, Duration — les trois indicateurs de base d'un service. |
| **Rollup** | Un calcul d'agrégation périodique qui résume les données brutes pour un affichage rapide. |
| **Transaction métier** | Un point d'entrée applicatif nommé et suivi, détecté automatiquement. |
| **Business Journey** | Un entonnoir de conversion reliant plusieurs pages et transactions métier. |
| **Health Rule** | Une règle définissant un seuil sur un indicateur, dont la violation génère un événement. |
| **Incident / War Room** | Un suivi manuel, ouvert par une équipe, d'une investigation en cours. |
| **RUM** | Real User Monitoring — mesure de l'expérience réelle des utilisateurs finaux. |
| **Web Vitals** | Indicateurs standards de performance perçue côté navigateur : LCP, INP, CLS, FCP, TTFB. |
| **GeoIP** | Base de correspondance entre adresse IP et localisation géographique. |
| **Vertica** | La base de données analytique qui sert d'entrepôt de données unique pour toute la plateforme. |
| **OTel Collector** | Le composant qui reçoit la télémétrie des applications instrumentées et la transmet à Neurons. |
| **Rétention** | La durée pendant laquelle une catégorie de données est conservée avant suppression automatique. |
| **vbr** | Vertica Backup and Restore — l'utilitaire fourni avec Vertica pour sauvegarder et restaurer la base. |
{firstcol="26"}

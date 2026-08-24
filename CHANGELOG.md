# CHANGELOG

Todas las entradas siguen el formato: `YYYY-MM-DD — autor — descripción`.

## [Unreleased]

- 2026-08-24 — andresypm@gmail.com — Inicialización del repositorio: estructura de carpetas,
  README con sector (Escenario A — Banca) y plataforma (GCP) declarados, decisiones de
  arquitectura documentadas (BigQuery+dbt para Silver/Gold, Cloud Workflows+Scheduler+Run
  para orquestación, Terraform para IaC). Plan de fases en `PLAN.md`.
- 2026-08-24 — andresypm@gmail.com — Fase 0 completada: Python 3.12, Terraform 1.15.8 y
  Google Cloud SDK instalados; proyecto GCP `finbank-data-platform-dev` creado con billing
  del free trial vinculado (`us-central1`); se eliminó un proyecto duplicado creado por error
  (`fibank-data-platform`, typo, sin billing) tras validar que había dos organizaciones y dos
  billing accounts distintas en la cuenta.

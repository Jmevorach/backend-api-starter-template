# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## Table of Contents

- [[Unreleased]](#unreleased)

## [Unreleased]

### Added
- API governance toolchain (`contracts/openapi.json`, Spectral linting, breaking-change checks).
- Versioned API namespace (`/api/v1/*`) with compatibility routes under `/api/*`.
- Canonical domain example module with `projects` and `tasks` resources.
- Centralized JSON error envelope fields (`code`, `message`, `request_id`, `details`).
- In-memory API rate limiting and configurable request-body limits.
- Security scan workflow (Semgrep + CodeQL) and release workflow.
- Contributor gates via `make verify` and PR template.

### Changed
- Upload validation now enforces filename + extension allow-lists.
- API contract and TypeScript interfaces expanded for new versioned and example endpoints.

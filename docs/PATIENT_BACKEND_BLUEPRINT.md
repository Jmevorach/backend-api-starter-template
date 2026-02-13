# Patient Backend Blueprint

This document outlines practical next steps for evolving this repository into a
production-grade backend for an open-source React patient application.

## Current Baseline

Already included:

- OAuth login (Google and Apple) + server-side sessions
- Protected APIs and route guard plug
- Patient-ready endpoints:
  - `GET /api/patient/profile`
  - `GET /api/patient/dashboard`
- Care-note CRUD (`/api/notes`)
- S3 uploads with presigned URLs
- Production AWS deployment stack (ECS, ALB, Aurora, Valkey, IAM auth)

## Recommended Next Domain Modules

Prioritize these APIs:

1. Appointments (`/api/appointments`)
2. Medications (`/api/medications`)
3. Conditions and care plans (`/api/conditions`, `/api/care-plans`)
4. Labs and vitals (`/api/labs`, `/api/vitals`)
5. Messaging (`/api/messages`, `/api/conversations`)

Keep each as a dedicated context + schema + controller test set.

## Security and Compliance Direction

- Minimize PHI in logs and traces.
- Add audit event tables for critical reads/writes.
- Encrypt sensitive columns where needed.
- Apply role-based authorization (patient, caregiver, clinician, admin).
- Add retention/deletion workflows for user data exports and account deletion.

## Interop Suggestions

If your roadmap includes provider interoperability:

- Add FHIR mapping modules for selected resources (Patient, Observation, MedicationRequest).
- Keep internal models decoupled from direct FHIR JSON payloads.
- Validate and version mapping contracts with integration tests.

## Frontend Integration Tips

- Use `/api/patient/profile` and `/api/patient/dashboard` for initial app bootstrap.
- Keep session refresh simple: call `/api/me` on app start.
- Gate feature flags per user in a dedicated endpoint (`/api/features`).

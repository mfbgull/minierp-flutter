## ADDED Requirements

### Requirement: System report templates require admin role
Creating a system custom-report template (`user_id = 0`, visible to every user) SHALL require an administrator role, in addition to `reports:create`. Ordinary report builders MAY still create private templates. Templates loaded into the builder pass through the same expression validation as stored configs (already enforced by `report-expression-security`).

#### Scenario: Non-admin cannot plant a system template
- **WHEN** a non-admin user holding `reports:create` posts a template with `is_system = true`
- **THEN** the request fails 403 and no `user_id = 0` row is created

#### Scenario: Admin templates still publish
- **WHEN** an administrator creates a system template
- **THEN** it remains visible to every user as before

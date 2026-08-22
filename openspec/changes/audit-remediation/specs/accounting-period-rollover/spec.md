# Spec: accounting-period-rollover (Delta)

## ADDED Requirements

### Requirement: Boot sequence never mutates accounting periods
The boot/migration sequence SHALL NOT insert, reopen, or alter accounting periods; period creation happens exclusively through the posting-time rollover path and explicit admin actions, so admin period closures are durable across restarts.

#### Scenario: Closed current month survives restart
- **WHEN** an admin closes the current month and the server restarts
- **THEN** no period is silently reopened and no UNIQUE-constraint error occurs during boot

#### Scenario: Boot with all periods closed is clean
- **WHEN** every accounting period is closed and the server boots
- **THEN** startup logs no migration error and leaves period status unchanged

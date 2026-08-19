## Context

Users need return actions from purchase and invoice workflows, but the current screens do not expose create/return paths in the 3-dot menu or detail views. Separately, the activity log screen grid is not showing data, which blocks operational visibility.

## Goals / Non-Goals

**Goals:**
- Enable return initiation from purchase return, purchase order, purchase, invoice list, and invoice detail screens.
- Restore data visibility in the activity log grid.

**Non-Goals:**
- Redesign the full return domain model or accounting flow.
- Change backend return posting rules beyond what existing purchase/invoice return logic already supports.
- Introduce new reporting or audit systems.

## Decisions

- Reuse existing return form/screen for purchase and invoice returns where possible; add navigation/routing hooks from the listed entry points.
- Add a single "Return" action item to the relevant 3-dot menus instead of duplicating screens or inventing new flows.
- Fix the activity log grid at the data-binding/query layer rather than replacing the grid component.

## Risks / Trade-offs

- If backend return APIs are incomplete for invoices, frontend return entry may still be stubbed.
- Activity log fix may expose schema or permission issues hidden by the broken grid path.

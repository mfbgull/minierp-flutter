# Shared widgets (PORTING.md §1)

| Widget | Purpose | Reference |
|---|---|---|
| `DataTableShell` | PlutoGrid-backed list shell (server-side paging/sort) | `references/components/common/MiniERPGrid.tsx` (§6) |
| `FormFieldShell` | labelled field + required marker + validation slot | web form conventions |
| `SearchableSelect` | type-ahead dropdown (debounced API search) | `GenericSearchableCell` (§6) |
| `StatusBadge` | colored status chip | `references/utils/statusColors.ts` (§6) |
| `ModalForm` | create/edit dialog scaffold | web `ModalForm` |
| `ConfirmDialog` | confirm dialogs (`showConfirmDialog`) | — |
| `AppToast` | snackbar feedback (`showAppToast`) | — |

All are compiling placeholders — replace stubs with full implementations
as each module is ported.

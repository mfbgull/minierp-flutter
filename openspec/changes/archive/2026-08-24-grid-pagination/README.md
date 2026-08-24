# grid-pagination

Grid-wide server-side pagination and bottom-chrome cleanup: every
data-heavy PlutoGrid list screen pages server-side with the
`ServerPaginationBar` (like suppliers), with server-side search and sort
parity, the keyboard-hint strip removed from all grids, and the now-dead
client-side pager code deleted. Stock Movement is the end-to-end pilot,
then inventory, sales, purchasing, production/BOM/forecast, and expenses
follow the same template.

Docs: [spec.md](specs/grid-pagination/spec.md) · [proposal.md](proposal.md) · [design.md](design.md) · [tasks.md](tasks.md)

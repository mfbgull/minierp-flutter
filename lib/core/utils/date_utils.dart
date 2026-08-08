/// Canonical wire-format date formatter (`YYYY-MM-DD`) — the single
/// implementation the API expects (PORTING.md §2). Previously duplicated
/// as `_isoDate`/`_apiDate`/`_iso`/`isoReportDate` across repositories,
/// list screens, form dialogs and report screens; all now delegate here.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

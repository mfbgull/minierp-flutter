// Database backup models — shaped after `GET /admin/backup`
// (`server/src/routes/adminBackup.ts`). Field names match the API JSON
// keys verbatim.

import 'json_helpers.dart';

/// One backup file in the server's `<db-dir>/backups` folder.
class BackupFile {
  const BackupFile({
    required this.name,
    required this.sizeBytes,
    required this.createdAt,
  });

  factory BackupFile.fromJson(Map<String, dynamic> json) => BackupFile(
    name: asString(json['name']) ?? '',
    sizeBytes: asInt(json['sizeBytes']) ?? 0,
    createdAt: asString(json['createdAt']) ?? '',
  );

  /// Generated filename, e.g. `erp-2026-08-25T10-30-00.db`.
  final String name;
  final int sizeBytes;
  /// ISO timestamp of the file's mtime.
  final String createdAt;
}

/// Backup folder status — files (newest first) + last backup time.
class BackupStatus {
  const BackupStatus({required this.backups, required this.lastBackupAt});

  factory BackupStatus.fromJson(Map<String, dynamic> json) => BackupStatus(
    backups: [
      for (final entry in (json['backups'] as List? ?? const []))
        BackupFile.fromJson(entry! as Map<String, dynamic>),
    ],
    lastBackupAt: asString(json['lastBackupAt']),
  );

  final List<BackupFile> backups;

  /// ISO timestamp, or null when no backup exists yet.
  final String? lastBackupAt;
}

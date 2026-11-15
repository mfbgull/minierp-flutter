/// Client build version, sent as `X-Client-Version` on every request.
///
/// The server logs it and warns when a client is below its minimum
/// supported version (see `server/src/middleware/clientVersion.ts`).
///
/// Keep in sync with `version:` in `pubspec.yaml` — `app_version_test.dart`
/// fails if they drift.
const String kAppVersion = '0.2.1-alpha.1';

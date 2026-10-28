import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/backend/backend_paths.dart';

void main() {
  group('findServerDir', () {
    bool Function(String) only(List<String> paths) => (path) => paths.contains(path);

    test('finds the Linux .deb / AppImage layout beside the executable', () {
      final exists = only(['/opt/minierp/server/dist/server.js', '/opt/minierp/server/runtime/node']);
      expect(
        BackendPaths.findServerDir(
          executablePath: '/opt/minierp/minierp_app',
          platform: BackendPlatform.linux,
          exists: exists,
        ),
        '/opt/minierp/server',
      );
    });

    test('finds the .run layout one level above the bundle', () {
      final exists = only(['/home/u/.minierp/app/server/dist/server.js', '/home/u/.minierp/app/server/runtime/node']);
      expect(
        BackendPaths.findServerDir(
          executablePath: '/home/u/.minierp/app/bundle/minierp_app',
          platform: BackendPlatform.linux,
          exists: exists,
        ),
        '/home/u/.minierp/app/server',
      );
    });

    test('finds the macOS Resources layout', () {
      final exists = only([
        '/Applications/MiniERP.app/Contents/Resources/server/dist/server.js',
        '/Applications/MiniERP.app/Contents/Resources/server/runtime/node',
      ]);
      expect(
        BackendPaths.findServerDir(
          executablePath: '/Applications/MiniERP.app/Contents/MacOS/minierp_app',
          platform: BackendPlatform.macos,
          exists: exists,
        ),
        '/Applications/MiniERP.app/Contents/Resources/server',
      );
    });

    test('finds the Windows layout with node.exe', () {
      final exists = only([
        r'C:\Users\g\AppData\Local\Programs\MiniERP\server\dist\server.js',
        r'C:\Users\g\AppData\Local\Programs\MiniERP\server\runtime\node.exe',
      ]);
      expect(
        BackendPaths.findServerDir(
          executablePath: r'C:\Users\g\AppData\Local\Programs\MiniERP\minierp_app.exe',
          platform: BackendPlatform.windows,
          exists: exists,
        ),
        r'C:\Users\g\AppData\Local\Programs\MiniERP\server',
      );
    });

    test('returns null in development (no bundled server)', () {
      expect(
        BackendPaths.findServerDir(
          executablePath: '/repo/build/linux/x64/debug/bundle/minierp_app',
          platform: BackendPlatform.linux,
          exists: (_) => false,
        ),
        isNull,
      );
    });

    test('requires both the server entry point and the runtime', () {
      final exists = only(['/opt/minierp/server/dist/server.js']);
      expect(
        BackendPaths.findServerDir(
          executablePath: '/opt/minierp/minierp_app',
          platform: BackendPlatform.linux,
          exists: exists,
        ),
        isNull,
      );
    });
  });

  group('resolveDataDir', () {
    test('honours XDG_DATA_HOME on Linux', () {
      expect(
        BackendPaths.resolveDataDir(
          platform: BackendPlatform.linux,
          environment: {'XDG_DATA_HOME': '/xdg', 'HOME': '/home/u'},
        ),
        '/xdg/minierp/data',
      );
    });

    test('falls back to ~/.local/share on Linux', () {
      expect(
        BackendPaths.resolveDataDir(
          platform: BackendPlatform.linux,
          environment: {'HOME': '/home/u'},
        ),
        '/home/u/.local/share/minierp/data',
      );
    });

    test('uses LOCALAPPDATA on Windows', () {
      expect(
        BackendPaths.resolveDataDir(
          platform: BackendPlatform.windows,
          environment: {'LOCALAPPDATA': r'C:\Users\g\AppData\Local'},
        ),
        r'C:\Users\g\AppData\Local\MiniERP\data',
      );
    });

    test('uses Application Support on macOS', () {
      expect(
        BackendPaths.resolveDataDir(
          platform: BackendPlatform.macos,
          environment: {'HOME': '/Users/g'},
        ),
        '/Users/g/Library/Application Support/MiniERP/data',
      );
    });

    test('honours an explicit MINIERP_DATA_DIR override', () {
      expect(
        BackendPaths.resolveDataDir(
          platform: BackendPlatform.linux,
          environment: {
            'MINIERP_DATA_DIR': '/opt/minierp/data',
            'HOME': '/home/u',
          },
        ),
        '/opt/minierp/data',
      );
    });

    test('throws when the home directory is unavailable', () {
      expect(
        () => BackendPaths.resolveDataDir(
          platform: BackendPlatform.linux,
          environment: const {},
        ),
        throwsStateError,
      );
    });
  });

  test('api URLs always use the loopback address', () {
    expect(BackendPaths.apiBaseUrl(41234), 'http://127.0.0.1:41234/api');
    expect(BackendPaths.healthUrl(41234), 'http://127.0.0.1:41234/health');
  });
}

// Verify two things:
//   ① Full stack trace: confirm package:path is in the exception chain
//   ② Whether all \\?\UNC\ paths fail, or only \\?\UNC\wsl.localhost\...
//
// Run from W: drive to reproduce the exact analyzer scenario:
//   cd W:\tmp\test_path_unc
//   dart pub get
//   dart run test_path_unc_full.dart

import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  print('=== Environment ===');
  print('p.style: ${p.style}');
  print('p.current: ${p.current}');
  print('Platform.operatingSystem: ${Platform.operatingSystem}');
  print('');

  // ============================================================
  // ① Full stack trace from resolveSymbolicLinksSync
  // ============================================================
  print('=== Test 1: resolveSymbolicLinksSync() full stack ===');
  try {
    var cwd = Directory.current;
    var resolved = cwd.resolveSymbolicLinksSync();
    print('Resolved: $resolved');
  } catch (e, st) {
    print('Exception type: ${e.runtimeType}');
    print('Exception: $e');
    print('Stack trace:');
    print(st);
  }
  print('');

  // ============================================================
  // ① Full stack trace from p.toUri
  // ============================================================
  print('=== Test 2: p.toUri() with extended UNC path ===');
  // Simulate what resolveSymbolicLinksSync returns
  var extendedUncPath = r'\\?\UNC\wsl.localhost\Ubuntu-24.04\home\berial\workspace\flutter\sd_ldar';
  try {
    var uri = p.toUri(extendedUncPath);
    print('URI: $uri');
  } catch (e, st) {
    print('Exception type: ${e.runtimeType}');
    print('Exception: $e');
    print('Stack trace:');
    print(st);
  }
  print('');

  // ============================================================
  // ② Test various UNC forms to find the exact failure boundary
  // ============================================================
  print('=== Test 3: UNC form boundary test ===');
  var paths = <String>[
    // Extended UNC forms (\\?\UNC\...)
    r'\\?\UNC\wsl.localhost\Ubuntu-24.04\home\berial',
    r'\\?\UNC\localhost\c$\Users',
    r'\\?\UNC\127.0.0.1\c$\Users',
    r'\\?\UNC\someserver\share\path',

    // Standard UNC forms (\\server\share)
    r'\\wsl.localhost\Ubuntu-24.04\home\berial',
    r'\\localhost\c$\Users',
    r'\\127.0.0.1\c$\Users',
    r'\\someserver\share\path',

    // Drive-letter forms (should always work)
    r'W:\home\berial',
    r'C:\Users',
  ];

  for (var path in paths) {
    try {
      var uri = p.toUri(path);
      print('OK   | $path');
      print('     -> $uri');
    } catch (e, st) {
      // Just first line of stack for brevity
      var firstFrame = st.toString().split('\n').take(3).join(' | ');
      print('FAIL | $path');
      print('     | ${e.runtimeType}: $e');
      print('     | stack: $firstFrame');
    }
  }
  print('');

  // ============================================================
  // ② Also test resolveSymbolicLinksSync on a real non-wsl UNC
  // (\\?\UNC\localhost\c$ requires the share to exist; fall back
  //  to whatever real network paths we can find)
  // ============================================================
  print('=== Test 4: resolveSymbolicLinksSync on standard UNC ===');
  // \\wsl.localhost\Ubuntu-24.04\... should be reachable via Windows
  var wslUnc = r'\\wsl.localhost\Ubuntu-24.04\home\berial';
  try {
    var dir = Directory(wslUnc);
    if (dir.existsSync()) {
      var resolved = dir.resolveSymbolicLinksSync();
      print('OK   | $wslUnc');
      print('     -> $resolved');
    } else {
      print('SKIP | $wslUnc (does not exist)');
    }
  } catch (e, st) {
    print('FAIL | $wslUnc');
    print('     | ${e.runtimeType}: $e');
    print('     | stack: ${st.toString().split("\n").take(3).join(" | ")}');
  }
}

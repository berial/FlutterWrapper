// Verify whether Uri.file / Uri.directory (dart:core) can handle
// Windows Extended UNC paths \\?\UNC\...
//
// The analyzer's _PhysicalFile.toUri() uses Uri.file(path), NOT
// package:path's toUri. So if FormatException is happening inside
// the analyzer, it might NOT be from package:path at all.
//
// Run: dart run test_uri_file.dart

import 'dart:io';

void main() {
  print('=== Uri.file() / Uri.directory() on Extended UNC ===');
  var paths = <String>[
    r'\\?\UNC\wsl.localhost\Ubuntu-24.04\home\berial',
    r'\\?\UNC\localhost\c$\Users',
    r'\\wsl.localhost\Ubuntu-24.04\home\berial',
    r'W:\home\berial',
    r'C:\Users',
  ];

  for (var path in paths) {
    try {
      var uri = Uri.file(path, windows: true);
      print('OK   (file)      | $path');
      print('                  -> $uri');
    } catch (e) {
      print('FAIL (file)      | $path');
      print('                  | ${e.runtimeType}: $e');
    }

    try {
      var uri = Uri.directory(path, windows: true);
      print('OK   (directory) | $path');
      print('                  -> $uri');
    } catch (e) {
      print('FAIL (directory) | $path');
      print('                  | ${e.runtimeType}: $e');
    }
  }

  print('');
  print('=== What resolveSymbolicLinksSync actually returns ===');
  try {
    var dir = Directory(r'\\wsl.localhost\Ubuntu-24.04\home\berial');
    if (dir.existsSync()) {
      var resolved = dir.resolveSymbolicLinksSync();
      print('resolved: $resolved');
      print('length: ${resolved.length}');
      // Try to feed it to Uri.file
      try {
        var uri = Uri.file(resolved, windows: true);
        print('Uri.file: $uri');
      } catch (e) {
        print('Uri.file FAIL: ${e.runtimeType}: $e');
      }
    } else {
      print('dir does not exist');
    }
  } catch (e, st) {
    print('resolveSymbolicLinksSync FAIL: ${e.runtimeType}: $e');
    print(st.toString().split('\n').take(3).join('\n'));
  }

  print('');
  print('=== Convert Extended UNC back to standard UNC then Uri.file ===');
  var ext = r'\\?\UNC\wsl.localhost\Ubuntu-24.04\home\berial';
  var stripped = r'\\' + ext.substring(8); // remove \\?\UNC\
  print('stripped: $stripped');
  try {
    var uri = Uri.file(stripped, windows: true);
    print('Uri.file: $uri');
  } catch (e) {
    print('Uri.file FAIL: ${e.runtimeType}: $e');
  }
}

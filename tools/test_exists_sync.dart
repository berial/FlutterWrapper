// Reproduce the actual error from AS log:
//   FileSystemException: Exists failed, path = '\\wsl.localhost\Ubuntu-24.04\...fix_data' (OS Error: 指定的路径无效。, errno = 161)
//   #0  _Directory.existsSync (dart:io/directory_impl.dart:97)
//   #1  _PhysicalResource.exists (package:analyzer/file_system/physical_file_system.dart:368)
//
// This is NOT a FormatException from package:path — it's a FileSystemException
// from dart:io's existsSync on a UNC path.
//
// Run from D: drive (Windows native) to ensure we're testing dart:io behavior:
//   cd D:\Android\FlutterWrapper
//   dart run tools\test_exists_sync.dart

import 'dart:io';

void main() {
  // The exact path from the AS log
  var paths = <String>[
    r'\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data',
    r'\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib',
    r'\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4',
    r'\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev',
    r'\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache',
    r'\\wsl.localhost\Ubuntu-24.04\home\berial',
    r'\\wsl.localhost\Ubuntu-24.04',
    r'\\wsl.localhost',
    // Compare with mapped drive form
    r'W:\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data',
    r'W:\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib',
    // Extended UNC form (what resolveSymbolicLinksSync returns)
    r'\\?\UNC\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data',
  ];

  for (var path in paths) {
    try {
      var dir = Directory(path);
      var exists = dir.existsSync();
      print('OK   existsSync=$exists | $path');
    } catch (e) {
      print('FAIL ${e.runtimeType} | $path');
      print('                  | $e');
    }
  }

  print('');
  print('=== List animated_stack_widget-0.0.4/lib to see if fix_data exists ===');
  var libDir = Directory(r'\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib');
  try {
    if (libDir.existsSync()) {
      for (var entry in libDir.listSync()) {
        print('  ${entry.runtimeType}: ${entry.path}');
      }
    } else {
      print('lib dir does not exist');
    }
  } catch (e) {
    print('listSync FAIL: ${e.runtimeType}: $e');
  }

  print('');
  print('=== resolveSymbolicLinksSync on \\wsl.localhost\... ===');
  try {
    var resolved = Directory(r'\\wsl.localhost\Ubuntu-24.04\home\berial').resolveSymbolicLinksSync();
    print('resolved: $resolved');
  } catch (e, st) {
    print('FAIL: ${e.runtimeType}: $e');
    print(st.toString().split('\n').take(3).join('\n'));
  }
}

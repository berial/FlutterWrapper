// Test how Windows Dart resolves W: paths internally
import 'dart:io';

void main() {
  // Current dir
  var cwd = Directory.current;
  print('Directory.current: ${cwd.path}');
  print('absolute: ${cwd.absolute.path}');
  print('resolveSymbolicLinks: ${cwd.resolveSymbolicLinksSync()}');

  // Test pub-cache path
  var pubCache = Directory(r'W:\home\berial\.pub-cache\hosted\pub.dev\archive-4.0.9');
  if (pubCache.existsSync()) {
    print('pubCache absolute: ${pubCache.absolute.path}');
    print('pubCache resolveSymbolicLinks: ${pubCache.resolveSymbolicLinksSync()}');
  }
}

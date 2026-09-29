import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the rules that keep the simulation and the bot deterministic (see
/// the PRD): no Flutter, no dart:math, and no `double` outside fixed.dart's
/// conversion helpers.
void main() {
  final simFiles = [
    for (final dir in ['lib/sim', 'lib/ai'])
      ...Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
  ];

  test('lib/sim exists and has files', () {
    expect(simFiles, isNotEmpty);
  });

  for (final file in simFiles) {
    final name = file.uri.pathSegments.last;
    final code = file
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    test('$name imports no Flutter or dart:math', () {
      expect(code, isNot(contains('package:flutter')));
      expect(code, isNot(contains('dart:math')));
      expect(code, isNot(contains('dart:ui')));
    });

    // Bit operators truncate to 32 bits on web, which broke the stage
    // (negative numbers turned positive). Only int_math.dart may use them,
    // on values it keeps within 32 bits; input_frame.dart uses small flags.
    if (name != 'int_math.dart') {
      test('$name uses no web-unsafe bit shifts or 32-bit masks', () {
        final shifts = RegExp(r'<<|>>|0xFFFFFFFF').allMatches(code).length;
        final allowed = name == 'input_frame.dart' ? 1 : 0; // 1 << index
        expect(shifts, allowed);
      });
    }

    if (name != 'fixed.dart') {
      test('$name uses no double', () {
        expect(RegExp(r'\bdouble\b').hasMatch(code), isFalse);
      });
    }
  }
}

import 'package:flutter_demo/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatTimestamp returns empty string for invalid value', () {
    expect(formatTimestamp(0), '');
  });

  test('formatTimestamp formats valid timestamps', () {
    final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final formatted = formatTimestamp(seconds);
    expect(
      RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(formatted),
      isTrue,
    );
    expect(formatted.isNotEmpty, isTrue);
  });
}

int parseInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String formatTimestamp(int secondsSinceEpoch) {
  if (secondsSinceEpoch <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(
    secondsSinceEpoch * 1000,
    isUtc: true,
  ).toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} '
      '${pad(date.hour)}:${pad(date.minute)}';
}

List<String> parseTags(Map<String, dynamic> json, String text) {
  final tags = <String>{};
  final rawTags = json['tags'];
  if (rawTags is List) {
    tags.addAll(
      rawTags
          .map((item) => item?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty),
    );
  }
  final cw = json['cw'];
  if (cw is String && cw.trim().isNotEmpty) {
    tags.add(cw.trim());
  }
  final tag = json['tag'];
  if (tag is String && tag.trim().isNotEmpty) {
    tags.add(tag.trim());
  }
  final topic = json['topic'];
  if (topic is String && topic.trim().isNotEmpty) {
    tags.add(topic.trim());
  }
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('#')) continue;
    if (trimmed.startsWith('# ')) continue;
    final match = RegExp(r'^#([^\s#]+)$').firstMatch(trimmed);
    if (match == null) continue;
    final tag = match.group(1) ?? '';
    if (tag.isEmpty) continue;
    if (RegExp(r'^\d+$').hasMatch(tag)) continue;
    tags.add(tag);
  }
  return tags.toList();
}

const _anonNames = [
  'Alice',
  'Bob',
  'Carol',
  'Dave',
  'Eve',
  'Francis',
  'Grace',
  'Hans',
  'Isabella',
  'Jason',
  'Kate',
  'Louis',
  'Margaret',
  'Nathan',
  'Olivia',
  'Paul',
  'Queen',
  'Richard',
  'Susan',
  'Thomas',
  'Uma',
  'Vivian',
  'Winnie',
  'Xander',
  'Yasmine',
  'Zach',
];

String formatAnonName(int nameId) {
  if (nameId == 0) return '洞主';
  final index = nameId - 1;
  if (index >= 0 && index < _anonNames.length) {
    return _anonNames[index];
  }
  final offset = index - _anonNames.length;
  final maxCombo = _anonNames.length * _anonNames.length;
  if (offset < maxCombo) {
    final first = offset ~/ _anonNames.length;
    final second = offset % _anonNames.length;
    return '${_anonNames[first]} ${_anonNames[second]}';
  }
  final seq = offset - maxCombo + 1;
  return 'You Win+$seq';
}

String truncateMarkdown(String text, int maxChars) {
  final trimmed = text.trim();
  if (trimmed.length <= maxChars) return trimmed;
  return '${trimmed.substring(0, maxChars).trimRight()}...';
}

List<int> extractPostRefs(String text, {int? excludePid}) {
  final matches = RegExp(r'#(\d{1,9})').allMatches(text);
  final seen = <int>{};
  for (final match in matches) {
    final value = int.tryParse(match.group(1) ?? '');
    if (value == null) continue;
    if (excludePid != null && value == excludePid) continue;
    seen.add(value);
  }
  return seen.toList()..sort();
}

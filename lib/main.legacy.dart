// Legacy monolithic snapshot before refactor.
// This file is for reference and is not used by default.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_view/photo_view.dart';

// ---- lib/constants.dart ----
const tholeBaseUrl = 'https://api.tholeapis.top/_api/v1';
const tholeWebProxyBaseUrl = 'http://localhost:8080/_api/v1';
const tholeWebProxyQBaseUrl = 'http://localhost:8080/q/_api/v1';
const tholeWebProxyQ2BaseUrl = 'http://localhost:8080/q2/_api/v1';
const defaultTokenT = '';
const defaultTokenQ = '';
const userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/96.0.4664.93 Safari/537.36';

// ---- lib/utils.dart ----
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

// ---- lib/models.dart ----
class Post {
  Post({
    required this.pid,
    required this.text,
    this.timestamp,
    this.commentCount = 0,
    this.attention,
    this.tags = const [],
  });

  final int pid;
  final String text;
  final int? timestamp;
  final int commentCount;
  final bool? attention;
  final List<String> tags;

  factory Post.fromJson(Map<String, dynamic> json) {
    final timestampValue = json['timestamp'] ?? json['create_time'];
    final textValue = (json['text'] as String?)?.trim() ?? '';
    final tags = parseTags(json, textValue);
    return Post(
      pid: parseInt(json['pid']),
      text: textValue,
      timestamp: timestampValue is int ? timestampValue : null,
      commentCount: json['n_comments'] is int
          ? json['n_comments'] as int
          : (json['reply'] is int ? json['reply'] as int : 0),
      attention: json['attention'] is bool ? json['attention'] as bool : null,
      tags: tags,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pid': pid,
      'text': text,
      'timestamp': timestamp,
      'n_comments': commentCount,
      'attention': attention,
      'tags': tags,
    };
  }

  Post copyWith({
    bool? attention,
  }) {
    return Post(
      pid: pid,
      text: text,
      timestamp: timestamp,
      commentCount: commentCount,
      attention: attention ?? this.attention,
      tags: tags,
    );
  }
}

class Comment {
  Comment({
    required this.cid,
    required this.nameId,
    required this.text,
    this.timestamp,
  });

  final int cid;
  final int nameId;
  final String text;
  final int? timestamp;

  factory Comment.fromJson(Map<String, dynamic> json) {
    final timestampValue = json['timestamp'] ?? json['create_time'];
    return Comment(
      cid: parseInt(json['cid']),
      nameId: parseInt(json['name_id']),
      text: (json['text'] as String?)?.trim() ?? '',
      timestamp: timestampValue is int ? timestampValue : null,
    );
  }
}

enum BackendType { t, q, qOld }

enum FeedMode {
  latestReply(1, '最新回复'),
  latestPost(0, '最新发布'),
  hot(2, '热门'),
  random(3, '随机'),
  classic(4, '典藏');

  const FeedMode(this.orderMode, this.label);

  final int orderMode;
  final String label;
}

enum SearchMode { tag, full }

class BackendConfig {
  const BackendConfig({
    required this.name,
    required this.baseUrl,
    required this.webProxyBaseUrl,
    required this.roomId,
    this.supportsSearch = false,
    this.supportsPost = true,
    this.supportsComment = false,
  });

  final String name;
  final String baseUrl;
  final String webProxyBaseUrl;
  final int roomId;
  final bool supportsSearch;
  final bool supportsPost;
  final bool supportsComment;

  static const t = BackendConfig(
    name: '新 T 树洞',
    baseUrl: tholeBaseUrl,
    webProxyBaseUrl: tholeWebProxyBaseUrl,
    roomId: 1,
    supportsSearch: true,
    supportsPost: true,
    supportsComment: true,
  );

  static const q = BackendConfig(
    name: '新 Q 树洞',
    baseUrl: 'https://api.thuhole.site/_api/v1',
    webProxyBaseUrl: tholeWebProxyQBaseUrl,
    roomId: 0,
    supportsSearch: true,
    supportsComment: true,
    supportsPost: true,
  );

  static const qOld = BackendConfig(
    name: '新 Q 旧洞',
    baseUrl: 'https://api2.thuhole.site/_api/v1',
    webProxyBaseUrl: tholeWebProxyQ2BaseUrl,
    roomId: 0,
    supportsSearch: true,
    supportsPost: false,
    supportsComment: false,
  );
}

class SettingsResult {
  const SettingsResult({
    required this.tokenT,
    required this.tokenQ,
    required this.cacheEnabled,
    required this.cacheTtlMinutes,
    required this.collapseTaggedPosts,
  });

  final String tokenT;
  final String tokenQ;
  final bool cacheEnabled;
  final int cacheTtlMinutes;
  final bool collapseTaggedPosts;
}

// ---- lib/services.dart ----
class TholeApiClient {
  TholeApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<Post>> fetchLatestPosts({
    required String token,
    required String baseUrl,
    int page = 1,
    int roomId = 1,
    int orderMode = 0,
  }) async {
    final uri = _buildUri(
      baseUrl,
      'getlist',
      queryParameters: {
        'p': '$page',
        'order_mode': '$orderMode',
        'room_id': '$roomId',
        if (kIsWeb) 'token': token,
      },
    );
    final data = await _get(uri, token: token);
    final list = (data['data'] as List<dynamic>)
        .map((item) => Post.fromJson(item as Map<String, dynamic>))
        .toList();
    await PostCache.putMany(baseUrl, list);
    return list;
  }

  Future<Post> fetchPostById({
    required String token,
    required String baseUrl,
    required int pid,
    bool bypassCache = false,
  }) async {
    final cached = await PostCache.get(
      baseUrl,
      pid,
      bypassCache: bypassCache,
    );
    if (cached != null) return cached;
    final uri = _buildUri(
      baseUrl,
      'getone',
      queryParameters: {
        'pid': '$pid',
        if (kIsWeb) 'token': token,
      },
    );
    final data = await _get(uri, token: token);
    final item = data['data'] as Map<String, dynamic>;
    final post = Post.fromJson(item);
    await PostCache.putMany(baseUrl, [post]);
    return post;
  }

  Future<List<Post>> fetchAttentionPosts({
    required String token,
    required String baseUrl,
  }) async {
    final uri = _buildUri(
      baseUrl,
      'getattention',
      queryParameters: {
        if (kIsWeb) 'token': token,
      },
    );
    final data = await _get(uri, token: token);
    final raw = data['data'];
    if (raw is! List) return [];
    if (raw.isEmpty) return [];
    if (raw.first is Map<String, dynamic>) {
      final posts = raw
          .map((item) => Post.fromJson(item as Map<String, dynamic>))
          .toList();
      await PostCache.putMany(baseUrl, posts);
      return posts;
    }
    final pids = raw
        .map((item) => parseInt(item))
        .where((pid) => pid > 0)
        .toList();
    final posts = <Post>[];
    for (final pid in pids) {
      try {
        final post = await fetchPostById(
          token: token,
          baseUrl: baseUrl,
          pid: pid,
        );
        posts.add(post);
      } catch (_) {}
    }
    return posts;
  }

  Future<List<Post>> fetchMultiPosts({
    required String token,
    required String baseUrl,
    required List<int> pids,
    bool bypassCache = false,
  }) async {
    if (pids.isEmpty) return [];
    final uniquePids = pids.where((pid) => pid > 0).toSet().toList();
    final cachedMap = <int, Post>{};
    if (!bypassCache) {
      for (final pid in uniquePids) {
        final cached = await PostCache.get(baseUrl, pid);
        if (cached != null) {
          cachedMap[pid] = cached;
        }
      }
    }
    final missing = uniquePids.where((pid) => !cachedMap.containsKey(pid)).toList();
    final fetched = <Post>[];
    if (missing.isNotEmpty) {
      try {
        final query = missing.map((pid) => 'pids=$pid').join('&');
        final tokenQuery = kIsWeb ? 'token=$token&' : '';
        final uri = Uri.parse(
          '$baseUrl/getmulti?$tokenQuery$query',
        );
        final data = await _get(uri, token: token);
        final raw = data['data'];
        if (raw is List) {
          fetched.addAll(
            raw.map((item) => Post.fromJson(item as Map<String, dynamic>)),
          );
        }
      } catch (_) {
        for (final pid in missing) {
          try {
            final post = await fetchPostById(
              token: token,
              baseUrl: baseUrl,
              pid: pid,
              bypassCache: true,
            );
            fetched.add(post);
          } catch (_) {}
        }
      }
    }
    if (fetched.isNotEmpty) {
      await PostCache.putMany(baseUrl, fetched);
    }
    final resultMap = {
      for (final entry in cachedMap.entries) entry.key: entry.value,
      for (final post in fetched) post.pid: post,
    };
    return uniquePids
        .where((pid) => resultMap.containsKey(pid))
        .map((pid) => resultMap[pid]!)
        .toList();
  }

  Future<List<Post>> searchPosts({
    required String token,
    required String baseUrl,
    required int roomId,
    required String keywords,
    required int page,
    required int pageSize,
    required SearchMode searchMode,
  }) async {
    final uri = _buildUri(
      baseUrl,
      'search',
      queryParameters: {
        'search_mode': searchMode == SearchMode.tag ? '0' : '1',
        'page': '$page',
        'room_id': '$roomId',
        'keywords': keywords,
        'pagesize': '$pageSize',
        if (kIsWeb) 'token': token,
      },
    );
    final data = await _get(uri, token: token);
    final raw = data['data'];
    if (raw is! List) return [];
    final posts = raw
        .map((item) => Post.fromJson(item as Map<String, dynamic>))
        .toList();
    await PostCache.putMany(baseUrl, posts);
    return posts;
  }

  Future<List<Comment>> fetchComments({
    required String token,
    required String baseUrl,
    required int pid,
  }) async {
    final uri = _buildUri(
      baseUrl,
      'getcomment',
      queryParameters: {
        'pid': '$pid',
        if (kIsWeb) 'token': token,
      },
    );
    final data = await _get(uri, token: token);
    final list = (data['data'] as List<dynamic>)
        .map((item) => Comment.fromJson(item as Map<String, dynamic>))
        .toList();
    return list;
  }

  Future<void> toggleAttention({
    required String token,
    required String baseUrl,
    required int pid,
    required bool enable,
  }) async {
    final uri = _buildUri(
      baseUrl,
      'attention',
      queryParameters: {
        if (kIsWeb) 'token': token,
      },
    );
    await _post(
      uri,
      token: token,
      body: {'pid': '$pid', 'switch': enable ? '1' : '0'},
    );
  }

  Future<void> createPost({
    required String token,
    required String baseUrl,
    required int roomId,
    required String text,
    String cw = '',
  }) async {
    final uri = _buildUri(
      baseUrl,
      'dopost',
      queryParameters: {
        if (kIsWeb) 'token': token,
      },
    );
    await _post(
      uri,
      token: token,
      body: {
        'cw': cw,
        'text': text,
        'allow_search': '1',
        'use_title': '',
        'room_id': '$roomId',
      },
    );
  }

  Future<void> createComment({
    required String token,
    required String baseUrl,
    required int pid,
    required String text,
  }) async {
    final uri = _buildApiV2Uri(baseUrl, 'post/$pid/comment');
    final uriWithToken = kIsWeb
        ? uri.replace(queryParameters: {'token': token})
        : uri;
    await _post(
      uriWithToken,
      token: token,
      body: {
        'text': text,
        'use_title': '',
      },
    );
  }

  Uri _buildUri(
    String baseUrl,
    String path, {
    Map<String, String>? queryParameters,
  }) {
    var sanitized = baseUrl;
    while (sanitized.endsWith('/')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    final full = '$sanitized/$path';
    return Uri.parse(full).replace(queryParameters: queryParameters);
  }

  Uri _buildApiV2Uri(String baseUrl, String path) {
    var sanitized = baseUrl;
    while (sanitized.endsWith('/')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    if (sanitized.endsWith('/_api/v1')) {
      sanitized = sanitized.substring(0, sanitized.length - '/_api/v1'.length);
    } else if (sanitized.endsWith('/_api/v2')) {
      sanitized = sanitized.substring(0, sanitized.length - '/_api/v2'.length);
    }
    final full = '$sanitized/_api/v2/$path';
    return Uri.parse(full);
  }

  Future<Map<String, dynamic>> _get(Uri uri, {required String token}) async {
    if (token.isEmpty) {
      throw const ApiException('Token 不能为空');
    }
    final headers = kIsWeb
        ? <String, String>{}
        : {'User-Agent': userAgent, 'User-Token': token};
    final response = await _client.get(
      uri,
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw ApiException('请求失败: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final code = body['code'] as int? ?? 0;
    if (code != 0) {
      throw ApiException('接口错误: code $code');
    }
    return body;
  }

  Future<Map<String, dynamic>> _post(
    Uri uri, {
    required String token,
    required Map<String, String> body,
  }) async {
    if (token.isEmpty) {
      throw const ApiException('Token 不能为空');
    }
    final headers = kIsWeb
        ? <String, String>{}
        : {'User-Agent': userAgent, 'User-Token': token};
    final response = await _client.post(
      uri,
      headers: headers,
      body: body,
    );
    if (response.statusCode != 200) {
      throw ApiException('请求失败: HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final code = data['code'] as int? ?? 0;
    if (code != 0) {
      throw ApiException('接口错误: code $code');
    }
    return data;
  }
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FavoritesStore {
  static String _key(String backendKey) => 'local_favorites_$backendKey';

  static Future<List<int>> load(String backendKey) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key(backendKey)) ?? const <String>[];
    return list
        .map((value) => int.tryParse(value) ?? 0)
        .where((v) => v > 0)
        .toList();
  }

  static Future<void> update(String backendKey, int pid, bool enabled) async {
    final current = await load(backendKey);
    final set = current.toSet();
    if (enabled) {
      set.add(pid);
    } else {
      set.remove(pid);
    }
    await _save(backendKey, set.toList());
  }

  static Future<void> saveFromText(String backendKey, String text) async {
    final matches = RegExp(r'#?(\d{1,9})').allMatches(text);
    final set = <int>{};
    for (final match in matches) {
      final value = int.tryParse(match.group(1) ?? '');
      if (value != null && value > 0) {
        set.add(value);
      }
    }
    await _save(backendKey, set.toList());
  }

  static Future<void> _save(String backendKey, List<int> values) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = values.toSet().toList()..sort();
    await prefs.setStringList(
      _key(backendKey),
      sorted.map((value) => value.toString()).toList(),
    );
  }
}

class PostCache {
  static const _prefsKey = 'post_cache_v1';
  static const _ttl = Duration(hours: 1);
  static final Map<String, _PostCacheEntry> _entries = {};
  static bool _loaded = false;
  static bool _enabled = true;
  static Duration _dynamicTtl = _ttl;

  static String _key(String baseUrl, int pid) => '$baseUrl|$pid';

  static Future<Post?> get(
    String baseUrl,
    int pid, {
    bool bypassCache = false,
  }) async {
    if (bypassCache) return null;
    await _ensureLoaded();
    if (!_enabled) return null;
    final entry = _entries[_key(baseUrl, pid)];
    if (entry == null) return null;
    if (_isExpired(entry.timestampMs)) {
      _entries.remove(_key(baseUrl, pid));
      await _persist();
      return null;
    }
    return Post.fromJson(entry.data);
  }

  static Future<void> putMany(String baseUrl, List<Post> posts) async {
    if (posts.isEmpty) return;
    await _ensureLoaded();
    if (!_enabled) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final post in posts) {
      _entries[_key(baseUrl, post.pid)] = _PostCacheEntry(
        timestampMs: now,
        data: post.toJson(),
      );
    }
    await _persist();
  }

  static Future<void> applyConfig({
    required bool enabled,
    required int ttlMinutes,
  }) async {
    _enabled = enabled;
    _dynamicTtl = Duration(minutes: ttlMinutes > 0 ? ttlMinutes : 0);
    await _ensureLoaded();
    if (!enabled) {
      _entries.clear();
      await _persist();
    }
  }

  static bool _isExpired(int timestampMs) {
    if (!_enabled) return true;
    if (_dynamicTtl == Duration.zero) return true;
    final expiresAt = timestampMs + _dynamicTtl.inMilliseconds;
    return DateTime.now().millisecondsSinceEpoch > expiresAt;
  }

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    if (json == null || json.isEmpty) return;
    try {
      final raw = jsonDecode(json) as Map<String, dynamic>;
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          _entries[entry.key] = _PostCacheEntry.fromJson(value);
        }
      }
    } catch (_) {}
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      for (final entry in _entries.entries) entry.key: entry.value.toJson(),
    };
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}

class _PostCacheEntry {
  _PostCacheEntry({required this.timestampMs, required this.data});

  final int timestampMs;
  final Map<String, dynamic> data;

  factory _PostCacheEntry.fromJson(Map<String, dynamic> json) {
    return _PostCacheEntry(
      timestampMs: json['timestamp_ms'] as int? ?? 0,
      data: (json['data'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp_ms': timestampMs,
      'data': data,
    };
  }
}

// ---- lib/widgets.dart ----
class PostHeader extends StatelessWidget {
  const PostHeader({
    super.key,
    required this.post,
    required this.token,
    required this.baseUrl,
    required this.onOpenPost,
  });

  final Post post;
  final String token;
  final String baseUrl;
  final ValueChanged<Post> onOpenPost;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TagPidRow(
                tags: post.tags,
                pid: post.pid,
                textStyle: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              MarkdownContent(
                text: post.text,
                token: token,
                baseUrl: baseUrl,
                currentPostId: post.pid,
                onOpenPost: onOpenPost,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (post.timestamp != null)
                    Text(
                      formatTimestamp(post.timestamp!),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  Text(
                    '评论 ${post.commentCount}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MarkdownContent extends StatelessWidget {
  const MarkdownContent({
    super.key,
    required this.text,
    this.maxImageHeight,
    this.token,
    this.baseUrl,
    this.currentPostId,
    this.onOpenPost,
  });

  final String text;
  final double? maxImageHeight;
  final String? token;
  final String? baseUrl;
  final int? currentPostId;
  final ValueChanged<Post>? onOpenPost;

  @override
  Widget build(BuildContext context) {
    final style = MarkdownStyleSheet.fromTheme(Theme.of(context));
    final refs = extractPostRefs(text, excludePid: currentPostId);
    final canShowRefs =
        refs.isNotEmpty && token != null && baseUrl != null;
    final markdown = MarkdownBody(
      data: text,
      styleSheet: style,
      imageBuilder: (uri, title, alt) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: maxImageHeight != null
                  ? BoxConstraints(maxHeight: maxImageHeight!)
                  : const BoxConstraints(),
              child: InkWell(
                onTap: () => _openImage(context, uri),
                child: Image.network(
                  uri.toString(),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                    return _MarkdownImageFallback(uri: uri);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
    if (!canShowRefs) {
      return markdown;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        markdown,
        const SizedBox(height: 8),
        QuotePreviewList(
          pids: refs,
          token: token!,
          baseUrl: baseUrl!,
          onOpenPost: onOpenPost,
        ),
      ],
    );
  }

  void _openImage(BuildContext context, Uri uri) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageViewerPage(imageUrl: uri.toString()),
      ),
    );
  }
}

class TagRow extends StatelessWidget {
  const TagRow({super.key, required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags
          .map(
            (tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '#$tag',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class TagPidRow extends StatelessWidget {
  const TagPidRow({
    super.key,
    required this.tags,
    required this.pid,
    this.textStyle,
  });

  final List<String> tags;
  final int pid;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle =
        textStyle ?? Theme.of(context).textTheme.labelLarge;
    if (tags.isEmpty) {
      return Text('#$pid', style: labelStyle);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('#$pid', style: labelStyle),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: tags
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '#$tag',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSecondaryContainer,
                            ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class AttentionButton extends StatelessWidget {
  const AttentionButton({
    super.key,
    required this.isActive,
    required this.isLoading,
    required this.onPressed,
  });

  final bool isActive;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: EdgeInsets.all(6),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      tooltip: isActive ? '取消关注' : '关注',
      icon: Icon(isActive ? Icons.star : Icons.star_border),
      onPressed: onPressed,
    );
  }
}

class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('图片预览')),
      body: Center(
        child: PhotoView(
          imageProvider: NetworkImage(imageUrl),
          minScale: PhotoViewComputedScale.contained * 0.8,
          maxScale: PhotoViewComputedScale.covered * 3,
          errorBuilder: (context, error, stackTrace) {
            return _MarkdownImageFallback(uri: Uri.parse(imageUrl));
          },
          backgroundDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
      ),
    );
  }
}

class QuotePreviewList extends StatefulWidget {
  const QuotePreviewList({
    super.key,
    required this.pids,
    required this.token,
    required this.baseUrl,
    this.onOpenPost,
  });

  final List<int> pids;
  final String token;
  final String baseUrl;
  final ValueChanged<Post>? onOpenPost;

  @override
  State<QuotePreviewList> createState() => _QuotePreviewListState();
}

class _QuotePreviewListState extends State<QuotePreviewList> {
  final _client = TholeApiClient();
  final Map<int, Future<Post?>> _futures = {};

  @override
  void initState() {
    super.initState();
    for (final pid in widget.pids) {
      _futures[pid] = _loadPost(pid);
    }
  }

  @override
  void didUpdateWidget(covariant QuotePreviewList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pids.toString() == widget.pids.toString()) return;
    _futures.clear();
    for (final pid in widget.pids) {
      _futures[pid] = _loadPost(pid);
    }
  }

  Future<Post?> _loadPost(int pid) async {
    try {
      final cached = await PostCache.get(widget.baseUrl, pid);
      if (cached != null) return cached;
      return await _client.fetchPostById(
        token: widget.token,
        baseUrl: widget.baseUrl,
        pid: pid,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.pids
          .map(
            (pid) => FutureBuilder<Post?>(
              future: _futures[pid],
              builder: (context, snapshot) {
                return _QuotePreviewTile(
                  pid: pid,
                  post: snapshot.data,
                  onTap: snapshot.data != null && widget.onOpenPost != null
                      ? () => widget.onOpenPost!(snapshot.data!)
                      : null,
                );
              },
            ),
          )
          .toList(),
    );
  }
}

class _QuotePreviewTile extends StatelessWidget {
  const _QuotePreviewTile({
    required this.pid,
    required this.post,
    this.onTap,
  });

  final int pid;
  final Post? post;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = post == null
        ? const _QuotePreviewShell(title: '引用加载失败')
        : _QuotePreviewShell(
            title: '#$pid',
            subtitle: truncateMarkdown(post!.text, 80),
          );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }
}

class _QuotePreviewShell extends StatelessWidget {
  const _QuotePreviewShell({
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _MarkdownImageFallback extends StatelessWidget {
  const _MarkdownImageFallback({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            Icons.broken_image,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 4),
          Text(
            uri.toString(),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---- lib/pages.dart ----
enum MainTab { feed, favorites }

enum FavoritesMode { online, local }

class LatestPostsPage extends StatefulWidget {
  const LatestPostsPage({super.key});

  @override
  State<LatestPostsPage> createState() => _LatestPostsPageState();
}

class _LatestPostsPageState extends State<LatestPostsPage> {
  final _apiClient = TholeApiClient();
  final List<Post> _posts = [];
  final int _previewMaxChars = 160;
  String _token = defaultTokenT;
  BackendType _backend = BackendType.t;
  FeedMode _feedMode = FeedMode.latestPost;
  MainTab _tab = MainTab.feed;
  bool _collapseTaggedPosts = false;
  final Set<int> _togglingAttention = {};
  bool _isLoading = false;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _errorMessage;
  BackendConfig get _activeBackend =>
      switch (_backend) {
        BackendType.t => BackendConfig.t,
        BackendType.q => BackendConfig.q,
        BackendType.qOld => BackendConfig.qOld,
      };
  String get _activeBaseUrl =>
      kIsWeb ? _activeBackend.webProxyBaseUrl : _activeBackend.baseUrl;
  int get _activeRoomId => _activeBackend.roomId;
  int get _activeOrderMode => _feedMode.orderMode;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadPreferences();
    if (!mounted) return;
    await _fetchPosts(showLoadingIndicator: true);
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('backend') ?? BackendType.t.name;
    final tokenT = prefs.getString('token_t') ?? defaultTokenT;
    final tokenQ = prefs.getString('token_q') ?? defaultTokenQ;
    final modeT = prefs.getInt('mode_t') ?? FeedMode.latestPost.orderMode;
    final modeQ = prefs.getInt('mode_q') ?? FeedMode.latestPost.orderMode;
    final modeQ2 = prefs.getInt('mode_q2') ?? FeedMode.latestPost.orderMode;
    final selected = BackendType.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => BackendType.t,
    );
    final selectedMode = switch (selected) {
      BackendType.t => modeT,
      BackendType.q => modeQ,
      BackendType.qOld => modeQ2,
    };
    if (!mounted) return;
    setState(() {
      _backend = selected;
      _token = switch (selected) {
        BackendType.t => tokenT,
        BackendType.q => tokenQ,
        BackendType.qOld => tokenQ,
      };
      _feedMode = FeedMode.values.firstWhere(
        (mode) => mode.orderMode == selectedMode,
        orElse: () => FeedMode.latestPost,
      );
      _collapseTaggedPosts =
          prefs.getBool('collapse_tagged_posts') ?? false;
    });
  }

  bool _onPostScrollNotification(ScrollNotification notification) {
    final atBottom = notification.metrics.extentAfter == 0;
    final isPullUp = notification is OverscrollNotification
        ? notification.overscroll > 0
        : notification is ScrollEndNotification && atBottom;
    if (atBottom && isPullUp) {
      if (_isLoading || _isFetchingMore || !_hasMore) return false;
      _fetchPosts(page: _page + 1, append: true, showLoadingIndicator: false);
    }
    return false;
  }

  Future<void> _fetchPosts({
    int page = 1,
    bool append = false,
    bool showLoadingIndicator = true,
  }) async {
    if (!mounted) return;
    setState(() {
      if (!append && showLoadingIndicator) {
        _isLoading = true;
      }
      if (append) {
        _isFetchingMore = true;
      } else {
        _errorMessage = null;
      }
    });

    try {
      final posts = await _apiClient.fetchLatestPosts(
        token: _token,
        baseUrl: _activeBaseUrl,
        roomId: _activeRoomId,
        orderMode: _activeOrderMode,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        if (append) {
          _posts.addAll(posts);
          _page = page;
        } else {
          _posts
            ..clear()
            ..addAll(posts);
          _page = 1;
        }
        _hasMore = posts.isNotEmpty;
      });
    } catch (error) {
      if (!mounted) return;
      if (append) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载更多失败: $error')),
        );
      } else {
        setState(() {
          _errorMessage = error.toString();
          _posts.clear();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = _isWide(context);
    return Scaffold(
      appBar: _tab == MainTab.feed
          ? AppBar(
              title: _buildBackendSwitcherTitle(),
              bottom: _buildModeBar(context),
              actions: [
                if (_activeBackend.supportsPost)
                  IconButton(
                    onPressed: _openComposePage,
                    tooltip: '发帖',
                    icon: const Icon(Icons.edit),
                  ),
                if (_activeBackend.supportsSearch)
                  IconButton(
                    onPressed: _openSearchPage,
                    tooltip: '搜索',
                    icon: const Icon(Icons.search),
                  ),
                IconButton(
                  onPressed: _refresh,
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  onPressed: _openSettings,
                  tooltip: '设置',
                  icon: const Icon(Icons.settings),
                ),
              ],
            )
          : null,
      body: _tab == MainTab.feed
          ? _buildFeedBody(isWide)
          : FavoritesView(
              token: _token,
              baseUrl: _activeBaseUrl,
              backendKey: _backend.name,
              supportsComment: _activeBackend.supportsComment,
              showInlineActions: false,
            ),
      bottomNavigationBar: _buildBottomBar(isWide),
    );
  }

  PreferredSizeWidget? _buildModeBar(BuildContext context) {
    final isWide = _isWide(context);
    final width = MediaQuery.of(context).size.width;
    final barWidth = isWide ? width * 0.7 : width;
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: SizedBox(
        height: 56,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: barWidth),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: FeedMode.values.length,
              itemBuilder: (context, index) {
                final mode = FeedMode.values[index];
                final selected = mode == _feedMode;
                return ChoiceChip(
                  label: Text(mode.label),
                  selected: selected,
                  onSelected: (value) => _switchMode(mode),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedBody(bool isWide) {
    if (_isLoading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '加载失败\n$_errorMessage',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _refresh,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('暂无帖子')),
        ],
      );
    }

    final width = MediaQuery.of(context).size.width;
    final contentWidth = isWide ? width * 0.7 : width;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onPostScrollNotification,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: _posts.length + (_isFetchingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _posts.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('加载中...')),
              );
            }
            final post = _posts[index];
            final collapsed = _collapseTaggedPosts && post.tags.isNotEmpty;
            final preview = collapsed
                ? ''
                : truncateMarkdown(post.text, _previewMaxChars);
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _openDetail(post),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TagPidRow(tags: post.tags, pid: post.pid),
                                const SizedBox(height: 8),
                                if (collapsed)
                                  Text(
                                    '含 tag 的帖子已折叠',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  )
                                else
                                  MarkdownContent(
                                    text: preview,
                                    maxImageHeight: 240,
                                    token: _token,
                                    baseUrl: _activeBaseUrl,
                                    currentPostId: post.pid,
                                    onOpenPost: _openDetail,
                                  ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (post.timestamp != null)
                                      Text(
                                        formatTimestamp(post.timestamp!),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    Text(
                                      '评论 ${post.commentCount}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: AttentionButton(
                                isActive: post.attention ?? false,
                                isLoading:
                                    _togglingAttention.contains(post.pid),
                                onPressed: () => _togglePostAttention(post),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool isWide) {
    if (isWide) return const SizedBox.shrink();
    return NavigationBar(
      selectedIndex: _tab.index,
      onDestinationSelected: (index) {
        setState(() {
          _tab = MainTab.values[index];
        });
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: '最新'),
        NavigationDestination(icon: Icon(Icons.star), label: '关注'),
      ],
    );
  }

  Widget _buildBackendSwitcherTitle() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<BackendType>(
        value: _backend,
        onChanged: (value) {
          if (value == null) return;
          _switchBackend(value);
        },
        items: BackendType.values
            .map(
              (backend) => DropdownMenuItem(
                value: backend,
                child: Text(_configFor(backend).name),
              ),
            )
            .toList(),
      ),
    );
  }

  void _switchBackend(BackendType backend) async {
    if (_backend == backend) return;
    final prefs = await SharedPreferences.getInstance();
    final tokenT = prefs.getString('token_t') ?? defaultTokenT;
    final tokenQ = prefs.getString('token_q') ?? defaultTokenQ;
    final modeT = prefs.getInt('mode_t') ?? FeedMode.latestPost.orderMode;
    final modeQ = prefs.getInt('mode_q') ?? FeedMode.latestPost.orderMode;
    final modeQ2 = prefs.getInt('mode_q2') ?? FeedMode.latestPost.orderMode;
    final selectedMode = switch (backend) {
      BackendType.t => modeT,
      BackendType.q => modeQ,
      BackendType.qOld => modeQ2,
    };
    setState(() {
      _backend = backend;
      _token = switch (backend) {
        BackendType.t => tokenT,
        BackendType.q => tokenQ,
        BackendType.qOld => tokenQ,
      };
      _feedMode = FeedMode.values.firstWhere(
        (mode) => mode.orderMode == selectedMode,
        orElse: () => FeedMode.latestPost,
      );
      _tab = MainTab.feed;
    });
    await prefs.setString('backend', backend.name);
    await _fetchPosts(showLoadingIndicator: true);
  }

  BackendConfig _configFor(BackendType backend) {
    return switch (backend) {
      BackendType.t => BackendConfig.t,
      BackendType.q => BackendConfig.q,
      BackendType.qOld => BackendConfig.qOld,
    };
  }

  bool _isWide(BuildContext context) {
    return MediaQuery.of(context).size.width > 720;
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          onChanged: (result) {
            setState(() {
              _token = switch (_backend) {
                BackendType.t => result.tokenT,
                BackendType.q => result.tokenQ,
                BackendType.qOld => result.tokenQ,
              };
              _collapseTaggedPosts = result.collapseTaggedPosts;
            });
          },
        ),
      ),
    );
  }

  Future<void> _openSearchPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SearchPage(
          token: _token,
          baseUrl: _activeBaseUrl,
          roomId: _activeRoomId,
          backendKey: _backend.name,
          supportsComment: _activeBackend.supportsComment,
        ),
      ),
    );
  }

  Future<void> _openComposePage() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ComposePage(
          token: _token,
          baseUrl: _activeBaseUrl,
          roomId: _activeRoomId,
        ),
      ),
    );
    if (result == true) {
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    await _fetchPosts(page: 1, append: false, showLoadingIndicator: false);
  }

  void _switchMode(FeedMode mode) async {
    if (mode == _feedMode) return;
    final prefs = await SharedPreferences.getInstance();
    switch (_backend) {
      case BackendType.t:
        await prefs.setInt('mode_t', mode.orderMode);
        break;
      case BackendType.q:
        await prefs.setInt('mode_q', mode.orderMode);
        break;
      case BackendType.qOld:
        await prefs.setInt('mode_q2', mode.orderMode);
        break;
    }
    setState(() {
      _feedMode = mode;
    });
    await _fetchPosts(showLoadingIndicator: true);
  }

  Future<void> _openDetail(Post post) async {
    final updated = await Navigator.of(context).push<Post>(
      MaterialPageRoute(
        builder: (context) => PostDetailPage(
          post: post,
          token: _token,
          baseUrl: _activeBaseUrl,
          backendKey: _backend.name,
          supportsComment: _activeBackend.supportsComment,
        ),
      ),
    );
    if (updated != null) {
      setState(() {
        _replacePostAttention(_posts, updated.pid, updated.attention ?? false);
      });
    }
  }

  Future<void> _togglePostAttention(Post post) async {
    if (_togglingAttention.contains(post.pid)) return;
    setState(() {
      _togglingAttention.add(post.pid);
    });
    final next = !(post.attention ?? false);
    try {
      await _apiClient.toggleAttention(
        token: _token,
        baseUrl: _activeBaseUrl,
        pid: post.pid,
        enable: next,
      );
      await FavoritesStore.update(_backend.name, post.pid, next);
      if (!mounted) return;
      setState(() {
        _replacePostAttention(_posts, post.pid, next);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _togglingAttention.remove(post.pid);
        });
      }
    }
  }

  void _replacePostAttention(List<Post> list, int pid, bool next) {
    final index = list.indexWhere((item) => item.pid == pid);
    if (index == -1) return;
    list[index] = list[index].copyWith(attention: next);
  }
}

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({
    super.key,
    required this.post,
    required this.token,
    required this.baseUrl,
    required this.backendKey,
    required this.supportsComment,
  });

  final Post post;
  final String token;
  final String baseUrl;
  final String backendKey;
  final bool supportsComment;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final _apiClient = TholeApiClient();
  final List<Comment> _comments = [];
  final int _pageSize = 20;
  final _commentController = TextEditingController();
  int _visibleCount = 0;
  bool _isLoading = false;
  bool _isAttention = false;
  bool _isTogglingAttention = false;
  bool _isSendingComment = false;
  String? _errorMessage;

  bool get _hasMore => _visibleCount < _comments.length;

  @override
  void initState() {
    super.initState();
    _isAttention = widget.post.attention ?? false;
    _fetchComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool _onCommentScrollNotification(ScrollNotification notification) {
    final atBottom = notification.metrics.extentAfter == 0;
    final isPullUp = notification is OverscrollNotification
        ? notification.overscroll > 0
        : notification is ScrollEndNotification && atBottom;
    if (atBottom && isPullUp) {
      if (_isLoading || !_hasMore) return false;
      setState(() {
        _visibleCount = min(_visibleCount + _pageSize, _comments.length);
      });
    }
    return false;
  }

  Future<void> _fetchComments() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final comments = await _apiClient.fetchComments(
        token: widget.token,
        baseUrl: widget.baseUrl,
        pid: widget.post.pid,
      );
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(comments);
        _visibleCount = min(_pageSize, _comments.length);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _comments.clear();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshComments() async {
    await _fetchComments();
  }

  Future<void> _toggleAttention() async {
    setState(() {
      _isTogglingAttention = true;
    });
    try {
      final next = !_isAttention;
      await _apiClient.toggleAttention(
        token: widget.token,
        baseUrl: widget.baseUrl,
        pid: widget.post.pid,
        enable: next,
      );
      await FavoritesStore.update(widget.backendKey, widget.post.pid, next);
      if (!mounted) return;
      setState(() {
        _isAttention = next;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingAttention = false;
        });
      }
    }
  }

  Future<void> _openReferencedPost(Post post) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PostDetailPage(
          post: post,
          token: widget.token,
          baseUrl: widget.baseUrl,
          backendKey: widget.backendKey,
          supportsComment: widget.supportsComment,
        ),
      ),
    );
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评论不能为空')),
      );
      return;
    }
    setState(() {
      _isSendingComment = true;
    });
    try {
      await _apiClient.createComment(
        token: widget.token,
        baseUrl: widget.baseUrl,
        pid: widget.post.pid,
        text: text,
      );
      if (!mounted) return;
      _commentController.clear();
      await _fetchComments();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('评论失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingComment = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('#${widget.post.pid}'),
        actions: [
          IconButton(
            onPressed: _isTogglingAttention ? null : _toggleAttention,
            tooltip: _isAttention ? '取消关注' : '关注',
            icon: _isTogglingAttention
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_isAttention ? Icons.star : Icons.star_border),
          ),
          IconButton(
            onPressed: _refreshComments,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchComments,
        child: _buildBody(),
      ),
      bottomNavigationBar: widget.supportsComment
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: '写评论…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isSendingComment ? null : _submitComment,
                      icon: _isSendingComment
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      tooltip: '发送',
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading && _comments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  '加载失败\n$_errorMessage',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _fetchComments,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final visible = _comments.take(_visibleCount).toList();
    final itemCount = 1 + visible.length + (_hasMore ? 1 : 0);
    return NotificationListener<ScrollNotification>(
      onNotification: _onCommentScrollNotification,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return PostHeader(
              post: widget.post,
              token: widget.token,
              baseUrl: widget.baseUrl,
              onOpenPost: _openReferencedPost,
            );
          }
          final commentIndex = index - 1;
          if (commentIndex >= visible.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: _hasMore ? const Text('上滑刷新') : const Text('没有更多评论'),
              ),
            );
          }
          final comment = visible[commentIndex];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatAnonName(comment.nameId),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    MarkdownContent(
                      text: comment.text,
                      token: widget.token,
                      baseUrl: widget.baseUrl,
                      currentPostId: widget.post.pid,
                      onOpenPost: _openReferencedPost,
                    ),
                    const SizedBox(height: 12),
                    if (comment.timestamp != null)
                      Text(
                        formatTimestamp(comment.timestamp!),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({
    super.key,
    required this.token,
    required this.baseUrl,
    required this.backendKey,
    required this.supportsComment,
  });

  final String token;
  final String baseUrl;
  final String backendKey;
  final bool supportsComment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              );
            },
            tooltip: '设置',
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: FavoritesView(
        token: token,
        baseUrl: baseUrl,
        backendKey: backendKey,
        supportsComment: supportsComment,
        showInlineActions: true,
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.token,
    required this.baseUrl,
    required this.roomId,
    required this.backendKey,
    required this.supportsComment,
  });

  final String token;
  final String baseUrl;
  final int roomId;
  final String backendKey;
  final bool supportsComment;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _apiClient = TholeApiClient();
  final _controller = TextEditingController();
  final List<Post> _results = [];
  bool _isLoading = false;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  int _page = 1;
  SearchMode _mode = SearchMode.full;
  String? _errorMessage;
  final Set<int> _togglingAttention = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search({bool append = false}) async {
    final keywords = _controller.text.trim();
    if (keywords.isEmpty) {
      setState(() {
        _results.clear();
        _errorMessage = null;
        _hasMore = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      if (append) {
        _isFetchingMore = true;
      } else {
        _isLoading = true;
        _errorMessage = null;
      }
    });
    try {
      final nextPage = append ? _page + 1 : 1;
      final posts = await _apiClient.searchPosts(
        token: widget.token,
        baseUrl: widget.baseUrl,
        roomId: widget.roomId,
        keywords: keywords,
        page: nextPage,
        pageSize: 50,
        searchMode: _mode,
      );
      if (!mounted) return;
      setState(() {
        if (append) {
          _results.addAll(posts);
          _page = nextPage;
        } else {
          _results
            ..clear()
            ..addAll(posts);
          _page = 1;
        }
        _hasMore = posts.isNotEmpty;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (append) {
          _results.clear();
        }
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    final atBottom = notification.metrics.extentAfter == 0;
    final isPullUp = notification is OverscrollNotification
        ? notification.overscroll > 0
        : notification is ScrollEndNotification && atBottom;
    if (atBottom && isPullUp) {
      if (_isLoading || _isFetchingMore || !_hasMore) return false;
      _search(append: true);
    }
    return false;
  }

  Future<void> _openDetail(Post post) async {
    final updated = await Navigator.of(context).push<Post>(
      MaterialPageRoute(
        builder: (context) => PostDetailPage(
          post: post,
          token: widget.token,
          baseUrl: widget.baseUrl,
          backendKey: widget.backendKey,
          supportsComment: widget.supportsComment,
        ),
      ),
    );
    if (updated != null) {
      setState(() {
        _replacePostAttention(_results, updated.pid, updated.attention ?? false);
      });
    }
  }

  void _replacePostAttention(List<Post> list, int pid, bool next) {
    final index = list.indexWhere((item) => item.pid == pid);
    if (index == -1) return;
    list[index] = list[index].copyWith(attention: next);
  }

  Future<void> _togglePostAttention(Post post) async {
    if (_togglingAttention.contains(post.pid)) return;
    setState(() {
      _togglingAttention.add(post.pid);
    });
    final next = !(post.attention ?? false);
    try {
      await _apiClient.toggleAttention(
        token: widget.token,
        baseUrl: widget.baseUrl,
        pid: post.pid,
        enable: next,
      );
      await FavoritesStore.update(widget.backendKey, post.pid, next);
      if (!mounted) return;
      setState(() {
        _replacePostAttention(_results, post.pid, next);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _togglingAttention.remove(post.pid);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        actions: [
          IconButton(
            onPressed: _search,
            tooltip: '搜索',
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: '关键词',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('全文搜索'),
                      selected: _mode == SearchMode.full,
                      onSelected: (value) {
                        setState(() {
                          _mode = SearchMode.full;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Tag 搜索'),
                      selected: _mode == SearchMode.tag,
                      onSelected: (value) {
                        setState(() {
                          _mode = SearchMode.tag;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _buildSearchResults()),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isLoading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '搜索失败\n$_errorMessage',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _search,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(child: Text('暂无结果'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _results.length + (_isFetchingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _results.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('加载中...')),
            );
          }
          final post = _results[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openDetail(post),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TagPidRow(tags: post.tags, pid: post.pid),
                          const SizedBox(height: 8),
                          MarkdownContent(
                            text: truncateMarkdown(post.text, 200),
                            maxImageHeight: 220,
                            token: widget.token,
                            baseUrl: widget.baseUrl,
                            currentPostId: post.pid,
                            onOpenPost: _openDetail,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (post.timestamp != null)
                                Text(
                                  formatTimestamp(post.timestamp!),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              Text(
                                '评论 ${post.commentCount}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: AttentionButton(
                          isActive: post.attention ?? false,
                          isLoading: _togglingAttention.contains(post.pid),
                          onPressed: () => _togglePostAttention(post),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ComposePage extends StatefulWidget {
  const ComposePage({
    super.key,
    required this.token,
    required this.baseUrl,
    required this.roomId,
  });

  final String token;
  final String baseUrl;
  final int roomId;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final _apiClient = TholeApiClient();
  final _cwController = TextEditingController();
  final _textController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _cwController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正文不能为空')),
      );
      return;
    }
    setState(() {
      _isSending = true;
    });
    try {
      await _apiClient.createPost(
        token: widget.token,
        baseUrl: widget.baseUrl,
        roomId: widget.roomId,
        text: text,
        cw: _cwController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发布成功')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发布失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发帖'),
        actions: [
          IconButton(
            onPressed: _isSending ? null : _submit,
            icon: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            tooltip: '发送',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _cwController,
            decoration: const InputDecoration(
              labelText: 'CW / Tag',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: '正文',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class FavoritesView extends StatefulWidget {
  const FavoritesView({
    super.key,
    required this.token,
    required this.baseUrl,
    required this.backendKey,
    required this.supportsComment,
    required this.showInlineActions,
  });

  final String token;
  final String baseUrl;
  final String backendKey;
  final bool supportsComment;
  final bool showInlineActions;

  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView> {
  final _apiClient = TholeApiClient();
  final _controller = TextEditingController();
  final List<Post> _posts = [];
  final Set<int> _togglingAttention = {};
  FavoritesMode _mode = FavoritesMode.online;
  bool _isLoading = false;
  String? _errorMessage;
  String _cachedInput = '';

  @override
  void initState() {
    super.initState();
    _loadLocalFavorites();
    _loadPosts();
  }

  Future<void> _loadLocalFavorites() async {
    final list = await FavoritesStore.load(widget.backendKey);
    if (!mounted) return;
    setState(() {
      _controller.text = list.isEmpty
          ? '#pid1 #pid2'
          : list.map((pid) => '#$pid').join(' ');
      _cachedInput = _controller.text;
    });
  }

  @override
  void didUpdateWidget(covariant FavoritesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backendKey != widget.backendKey) {
      _loadLocalFavorites();
      _loadPosts();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadPosts({bool bypassCache = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      List<Post> posts;
      if (_mode == FavoritesMode.online) {
        posts = await _apiClient.fetchAttentionPosts(
          token: widget.token,
          baseUrl: widget.baseUrl,
        );
      } else {
        final ids = await FavoritesStore.load(widget.backendKey);
        posts = await _apiClient.fetchMultiPosts(
          token: widget.token,
          baseUrl: widget.baseUrl,
          pids: ids,
          bypassCache: bypassCache,
        );
      }
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(posts);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _posts.clear();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    await _loadPosts(bypassCache: _mode == FavoritesMode.local);
  }

  Future<void> _togglePostAttention(Post post) async {
    if (_togglingAttention.contains(post.pid)) return;
    setState(() {
      _togglingAttention.add(post.pid);
    });
    final next = !(post.attention ?? false);
    try {
      await _apiClient.toggleAttention(
        token: widget.token,
        baseUrl: widget.baseUrl,
        pid: post.pid,
        enable: next,
      );
      await FavoritesStore.update(widget.backendKey, post.pid, next);
      if (!mounted) return;
      setState(() {
        _replacePostAttention(_posts, post.pid, next);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _togglingAttention.remove(post.pid);
        });
      }
    }
  }

  void _replacePostAttention(List<Post> list, int pid, bool next) {
    final index = list.indexWhere((item) => item.pid == pid);
    if (index == -1) return;
    list[index] = list[index].copyWith(attention: next);
  }

  Future<void> _openDetail(Post post) async {
    final updated = await Navigator.of(context).push<Post>(
      MaterialPageRoute(
        builder: (context) => PostDetailPage(
          post: post,
          token: widget.token,
          baseUrl: widget.baseUrl,
          backendKey: widget.backendKey,
          supportsComment: widget.supportsComment,
        ),
      ),
    );
    if (updated != null) {
      setState(() {
        _replacePostAttention(_posts, updated.pid, updated.attention ?? false);
      });
    }
  }

  Future<void> _saveLocalFavorites() async {
    final text = _controller.text.trim();
    await FavoritesStore.saveFromText(widget.backendKey, text);
    setState(() {
      _cachedInput = _controller.text.trim();
    });
    await _loadPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showInlineActions)
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('线上收藏'),
                      selected: _mode == FavoritesMode.online,
                      onSelected: (value) {
                        setState(() {
                          _mode = FavoritesMode.online;
                        });
                        _loadPosts();
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('本地收藏'),
                      selected: _mode == FavoritesMode.local,
                      onSelected: (value) {
                        setState(() {
                          _mode = FavoritesMode.local;
                        });
                        _loadPosts();
                      },
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _refresh,
                      tooltip: '刷新',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (_mode == FavoritesMode.local) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: '本地收藏列表 (#pid1 #pid2)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _controller.text.trim() == _cachedInput.trim()
                          ? null
                          : _saveLocalFavorites,
                      child: const Text('更新列表'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_isLoading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '加载失败\n$_errorMessage',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _refresh,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('暂无收藏')),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openDetail(post),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TagPidRow(tags: post.tags, pid: post.pid),
                        const SizedBox(height: 8),
                        MarkdownContent(
                          text: truncateMarkdown(post.text, 200),
                          maxImageHeight: 220,
                          token: widget.token,
                          baseUrl: widget.baseUrl,
                          currentPostId: post.pid,
                          onOpenPost: _openDetail,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (post.timestamp != null)
                              Text(
                                formatTimestamp(post.timestamp!),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            Text(
                              '评论 ${post.commentCount}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: AttentionButton(
                        isActive: post.attention ?? false,
                        isLoading: _togglingAttention.contains(post.pid),
                        onPressed: () => _togglePostAttention(post),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.onChanged});

  final ValueChanged<SettingsResult>? onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _tokenTController = TextEditingController();
  final _tokenQController = TextEditingController();
  final _cacheHoursController = TextEditingController();
  bool _cacheEnabled = true;
  bool _collapseTaggedPosts = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tokenTController.dispose();
    _tokenQController.dispose();
    _cacheHoursController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final tokenT = prefs.getString('token_t') ?? defaultTokenT;
    final tokenQ = prefs.getString('token_q') ?? defaultTokenQ;
    final cacheEnabled = prefs.getBool('post_cache_enabled') ?? true;
    final ttlMinutes = prefs.getInt('post_cache_ttl_minutes') ?? 60;
    final collapseTagged = prefs.getBool('collapse_tagged_posts') ?? false;
    if (!mounted) return;
    setState(() {
      _tokenTController.text = tokenT;
      _tokenQController.text = tokenQ;
      _cacheEnabled = cacheEnabled;
      _cacheHoursController.text = (ttlMinutes / 60).round().toString();
      _collapseTaggedPosts = collapseTagged;
    });
  }

  Future<void> _persist({bool showError = false}) async {
    try {
      final tokenT = _tokenTController.text.trim();
      final tokenQ = _tokenQController.text.trim();
      final hours = int.tryParse(_cacheHoursController.text.trim()) ?? 0;
      if (_cacheEnabled && hours <= 0) {
        throw const FormatException('缓存时长需要大于 0');
      }
      final ttlMinutes = _cacheEnabled ? hours * 60 : 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token_t', tokenT.isEmpty ? defaultTokenT : tokenT);
      await prefs.setString('token_q', tokenQ.isEmpty ? defaultTokenQ : tokenQ);
      await prefs.setBool('post_cache_enabled', _cacheEnabled);
      await prefs.setInt('post_cache_ttl_minutes', ttlMinutes);
      await prefs.setBool('collapse_tagged_posts', _collapseTaggedPosts);
      if (!mounted) return;
      await PostCache.applyConfig(
        enabled: _cacheEnabled,
        ttlMinutes: ttlMinutes,
      );
      widget.onChanged?.call(
        SettingsResult(
          tokenT: tokenT.isEmpty ? defaultTokenT : tokenT,
          tokenQ: tokenQ.isEmpty ? defaultTokenQ : tokenQ,
          cacheEnabled: _cacheEnabled,
          cacheTtlMinutes: ttlMinutes,
          collapseTaggedPosts: _collapseTaggedPosts,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $error')),
        );
      }
    }
  }

  void _schedulePersist() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _persist(showError: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Token 设置',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenTController,
            decoration: const InputDecoration(
              labelText: '新 T 树洞 Token',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _schedulePersist(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenQController,
            decoration: const InputDecoration(
              labelText: '新 Q 树洞 / 新 Q 旧洞 Token',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _schedulePersist(),
          ),
          const SizedBox(height: 24),
          Text(
            '帖子缓存',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '启用缓存',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Switch(
                      value: _cacheEnabled,
                      onChanged: (value) {
                        setState(() {
                          _cacheEnabled = value;
                        });
                        _persist(showError: true);
                      },
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _cacheHoursController,
                        enabled: _cacheEnabled,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '时长(小时)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => _schedulePersist(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '开启后，一段时间内访问过的帖子将使用本地缓存。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('折叠含 tag 树洞'),
            value: _collapseTaggedPosts,
            onChanged: (value) {
              setState(() {
                _collapseTaggedPosts = value;
              });
              _persist(showError: false);
            },
          ),
        ],
      ),
    );
  }
}

// ---- lib/app.dart ----
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '树洞 BBS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const LatestPostsPage(),
    );
  }
}

// ---- lib/main.dart ----
void main() {
  runApp(const MyApp());
}

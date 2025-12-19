import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'models.dart';
import 'services.dart';
import 'theme_controller.dart';
import 'utils.dart';
import 'widgets.dart';

enum MainTab { feed, favorites }

enum FavoritesMode { online, local }

class LatestPostsPage extends StatefulWidget {
  const LatestPostsPage({super.key});

  @override
  State<LatestPostsPage> createState() => _LatestPostsPageState();
}

class _LatestPostsPageState extends State<LatestPostsPage> {
  final _apiClient = TholeApiClient();
  final GlobalKey<_FavoritesViewState> _favoritesKey =
      GlobalKey<_FavoritesViewState>();
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
      appBar: _buildAppBar(context),
      body: _tab == MainTab.feed
          ? _buildFeedBody(isWide)
          : FavoritesView(
              key: _favoritesKey,
              token: _token,
              baseUrl: _activeBaseUrl,
              backendKey: _backend.name,
              supportsComment: _activeBackend.supportsComment,
              showInlineActions: true,
            ),
      floatingActionButton: _tab == MainTab.feed &&
              _activeBackend.supportsPost
          ? FloatingActionButton(
              onPressed: _openComposePage,
              tooltip: '发帖',
              child: const Icon(Icons.edit),
            )
          : null,
      bottomNavigationBar: _buildBottomBar(isWide),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: _buildBackendSwitcherTitle(),
      bottom: _tab == MainTab.feed ? _buildModeBar(context) : null,
      actions: [
        if (_activeBackend.supportsSearch)
          IconButton(
            onPressed: _openSearchPage,
            tooltip: '搜索',
            icon: const Icon(Icons.search),
          ),
        IconButton(
          onPressed: _refreshCurrent,
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          onPressed: _openSettings,
          tooltip: '设置',
          icon: const Icon(Icons.settings),
        ),
      ],
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
            return Center(
              child: SizedBox(
                width: contentWidth,
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
                                    selectable: false,
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
    });
    await prefs.setString('backend', backend.name);
    if (_tab == MainTab.feed) {
      await _fetchPosts(showLoadingIndicator: true);
    } else {
      await _favoritesKey.currentState?.refresh();
    }
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

  Future<void> _refreshCurrent() async {
    if (_tab == MainTab.feed) {
      await _refresh();
    } else {
      await _favoritesKey.currentState?.refresh();
    }
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
          pid: post.pid,
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
    this.post,
    required this.pid,
    required this.token,
    required this.baseUrl,
    required this.backendKey,
    required this.supportsComment,
  });

  final Post? post;
  final int pid;
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
  bool _isPostLoading = false;
  bool _isAttention = false;
  bool _isTogglingAttention = false;
  bool _isSendingComment = false;
  String? _errorMessage;
  String? _postErrorMessage;
  Post? _post;

  bool get _hasMore => _visibleCount < _comments.length;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _isAttention = widget.post?.attention ?? false;
    if (_post == null) {
      _fetchPost();
    }
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
        pid: widget.pid,
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

  Future<void> _fetchPost() async {
    if (!mounted) return;
    setState(() {
      _isPostLoading = true;
      _postErrorMessage = null;
    });
    try {
      final cached = await PostCache.get(widget.baseUrl, widget.pid);
      final post = cached ??
          await _apiClient.fetchPostById(
            token: widget.token,
            baseUrl: widget.baseUrl,
            pid: widget.pid,
          );
      if (!mounted) return;
      setState(() {
        _post = post;
        _isAttention = post.attention ?? _isAttention;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _postErrorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPostLoading = false;
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
        pid: widget.pid,
        enable: next,
      );
      await FavoritesStore.update(widget.backendKey, widget.pid, next);
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
          pid: post.pid,
          token: widget.token,
          baseUrl: widget.baseUrl,
          backendKey: widget.backendKey,
          supportsComment: widget.supportsComment,
        ),
      ),
    );
  }

  Future<bool> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评论不能为空')),
      );
      return false;
    }
    setState(() {
      _isSendingComment = true;
    });
    try {
      await _apiClient.createComment(
        token: widget.token,
        baseUrl: widget.baseUrl,
        pid: widget.pid,
        text: text,
      );
      if (!mounted) return false;
      _commentController.clear();
      await _fetchComments();
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('评论失败: $error')),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSendingComment = false;
        });
      }
    }
  }

  Future<void> _openCommentComposer() async {
    if (!widget.supportsComment) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _commentController,
                minLines: 2,
                maxLines: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '写评论…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _isSendingComment
                      ? null
                      : () async {
                          final ok = await _submitComment();
                          if (ok && mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  icon: _isSendingComment
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('发送'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('#${widget.pid}'),
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
      floatingActionButton: widget.supportsComment
          ? FloatingActionButton(
              onPressed: _openCommentComposer,
              tooltip: '写评论',
              child: const Icon(Icons.chat_bubble_outline),
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
            final post = _post;
            if (post != null) {
              return PostHeader(
                post: post,
                token: widget.token,
                baseUrl: widget.baseUrl,
                onOpenPost: _openReferencedPost,
              );
            }
            if (_postErrorMessage != null) {
              return _PostDetailPlaceholder(
                message: '帖子加载失败\n$_postErrorMessage',
                isLoading: false,
              );
            }
            return _PostDetailPlaceholder(
              isLoading: _isPostLoading,
              message: '帖子加载中...',
            );
          }
          final commentIndex = index - 1;
          if (commentIndex >= visible.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: _hasMore
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('没有更多评论'),
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
                      currentPostId: widget.pid,
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

class _PostDetailPlaceholder extends StatelessWidget {
  const _PostDetailPlaceholder({
    this.message = '加载中...',
    this.isLoading = true,
  });

  final String message;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (isLoading) const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
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
          pid: post.pid,
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
                            selectable: false,
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
              labelText: 'Tag',
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
  bool _showLocalEditor = false;
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

  Future<void> refresh() async {
    await _refresh();
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
          pid: post.pid,
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
          Padding(
            padding: const EdgeInsets.all(16),
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
                          _showLocalEditor = false;
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
                          _showLocalEditor = false;
                        });
                        _loadPosts();
                      },
                    ),
                  ],
                ),
                if (_mode == FavoritesMode.local) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _showLocalEditor = !_showLocalEditor;
                        });
                      },
                      icon: Icon(_showLocalEditor ? Icons.close : Icons.edit),
                      label: Text(_showLocalEditor ? '收起编辑' : '编辑列表'),
                    ),
                  ),
                ],
                if (_mode == FavoritesMode.local && _showLocalEditor) ...[
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
                          selectable: false,
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
  ThemeMode _themeMode = themeModeNotifier.value;
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
      _themeMode = themeModeNotifier.value;
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

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
          const SizedBox(height: 12),
          Text(
            '主题模式',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('跟随系统'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('浅色'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('深色'),
              ),
            ],
            selected: {_themeMode},
            onSelectionChanged: (selection) async {
              final next = selection.first;
              setState(() {
                _themeMode = next;
              });
              await setThemeMode(next);
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                '网站入口',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _openExternalUrl(
                  'https://thuhollow.github.io',
                ),
                child: const Text('新 T 树洞'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _openExternalUrl(
                  'https://new-q.thuhole.site',
                ),
                child: const Text('新 Q 树洞'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

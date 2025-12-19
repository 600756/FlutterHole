import 'package:flutter/material.dart';
import 'package:flutter_demo/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PostCard renders content and metadata', (tester) async {
    final post = Post(
      pid: 42,
      text: 'Title\nBody text for testing.',
      timestamp: 1700000000,
      commentCount: 3,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(post: post, onTap: () {}),
        ),
      ),
    );

    expect(find.text('Title'), findsOneWidget);
    expect(find.textContaining('Body text'), findsOneWidget);
    expect(find.textContaining('评论 3'), findsOneWidget);
  });
}

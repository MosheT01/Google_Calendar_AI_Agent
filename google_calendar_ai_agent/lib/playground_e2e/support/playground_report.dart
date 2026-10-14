import 'dart:math';

import 'playground_env.dart';

class PlaygroundGoalResult {
  final String id;
  final String description;
  final bool passed;
  final String reason;
  final String toolsUsed;
  final String responseSnippet;
  final String stateDiff;
  final Duration duration;

  const PlaygroundGoalResult({
    required this.id,
    required this.description,
    required this.passed,
    required this.reason,
    required this.toolsUsed,
    required this.responseSnippet,
    required this.stateDiff,
    required this.duration,
  });
}

class PlaygroundAggregate {
  final int total;
  final int passed;
  final int failed;
  final double passRate;
  final double threshold;

  const PlaygroundAggregate({
    required this.total,
    required this.passed,
    required this.failed,
    required this.passRate,
    required this.threshold,
  });

  bool get gatePassed => passRate >= threshold;
}

PlaygroundAggregate aggregateResults(List<PlaygroundGoalResult> results) {
  final total = results.length;
  final passed = results.where((result) => result.passed).length;
  final failed = total - passed;
  final passRate = total == 0 ? 0.0 : passed / total;
  return PlaygroundAggregate(
    total: total,
    passed: passed,
    failed: failed,
    passRate: passRate,
    threshold: resolvePassThreshold(),
  );
}

String buildMarkdownReport(
  List<PlaygroundGoalResult> results,
  PlaygroundAggregate aggregate,
) {
  final buffer = StringBuffer();
  buffer.writeln('## Playground E2E Aggregate Report');
  buffer.writeln(
    '- Total: ${aggregate.total}, Passed: ${aggregate.passed}, Failed: ${aggregate.failed}',
  );
  buffer.writeln(
    '- Pass rate: ${(aggregate.passRate * 100).toStringAsFixed(1)}% (threshold ${(aggregate.threshold * 100).toStringAsFixed(1)}%)',
  );
  buffer.writeln('- Gate: ${aggregate.gatePassed ? 'PASS' : 'FAIL'}');
  buffer.writeln('');
  buffer.writeln(
    '| Goal | Status | Duration | Tools | Reason | State Diff | Response |',
  );
  buffer.writeln('|---|---|---:|---|---|---|---|');
  for (final result in results) {
    final durationMs = max(1, result.duration.inMilliseconds);
    final status = result.passed ? 'PASS' : 'FAIL';
    final tools = _escape(result.toolsUsed);
    final reason = _escape(result.reason);
    final stateDiff = _escape(result.stateDiff);
    final response = _escape(result.responseSnippet);
    buffer.writeln(
      '| ${result.id} | $status | ${durationMs}ms | $tools | $reason | $stateDiff | $response |',
    );
  }
  return buffer.toString();
}

String _escape(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '-';
  return trimmed
      .replaceAll('\n', ' ')
      .replaceAll('|', '\\|')
      .replaceAll(RegExp(r'\s+'), ' ');
}
  
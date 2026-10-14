class AgentLoopPolicy {
  AgentLoopPolicy._();

  static const int historyPairs = 12;
  static const int maxUnfinishedNudges = 2;
  static const int maxConnectionRetries = 2;
  static const int maxQuotaDelaySeconds = 90;

  static const String unfinishedNudge =
      'Continue the same batch. Apply the remaining items with tool calls. '
      'Reply with the final list only when every item has a tool result.';

  static const String extraBudgetNudge =
      'Continue from the last successful tool result and finish the remaining items.';

  static List<T> recentPairs<T>(List<T> history, {int pairs = historyPairs}) {
    final keep = pairs * 2;
    if (history.length <= keep) {
      return List<T>.from(history);
    }
    return history.sublist(history.length - keep);
  }

  static bool allowMutations(String prompt) {
    final hasRead = RegExp(
      r'\b(search|recheck|check|list|look|dups|duplicates?|agenda)\b',
      caseSensitive: false,
    ).hasMatch(prompt);
    final hasWrite = RegExp(
      r'\b(add|create|book|schedule|delete|remove|rename|move|reschedule|fix|update|change|put|set)\b',
      caseSensitive: false,
    ).hasMatch(prompt);
    if (hasRead && !hasWrite) {
      return false;
    }
    return true;
  }

  static bool looksUnfinished(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('i will now') ||
        normalized.contains('remaining') ||
        normalized.contains('next i will');
  }

  static bool isConnectionAbort(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('clientexception') ||
        normalized.contains('software caused connection abort');
  }

  static int? quotaRetryDelaySeconds(Object error) {
    final normalized = error.toString().toLowerCase();
    if (!normalized.contains('quota')) {
      return null;
    }
    final match =
        RegExp(r'retry in\s+([0-9]+(?:\.[0-9]+)?)').firstMatch(normalized);
    if (match == null) {
      return null;
    }
    final seconds = double.parse(match.group(1)!).ceil();
    if (seconds < 0) {
      return 0;
    }
    if (seconds > maxQuotaDelaySeconds) {
      return maxQuotaDelaySeconds;
    }
    return seconds;
  }

  static Future<List<R>> runAll<T, R>(
    List<T> calls,
    Future<R> Function(T call) execute,
  ) async {
    final results = <R>[];
    for (final call in calls) {
      results.add(await execute(call));
    }
    return results;
  }
}

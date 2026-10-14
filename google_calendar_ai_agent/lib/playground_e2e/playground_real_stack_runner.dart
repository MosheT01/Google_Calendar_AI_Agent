import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:google_calendar_ai_agent/core/constants/app_constants.dart';
import 'package:google_calendar_ai_agent/domain/entities/chat_message.dart';
import 'package:google_calendar_ai_agent/presentation/providers/app_provider.dart';
import 'package:google_calendar_ai_agent/services/ai_service.dart';
import 'package:google_calendar_ai_agent/services/calendar_service.dart';

import 'support/playground_env.dart';
import 'support/playground_goals.dart';
import 'support/playground_lifecycle.dart';
import 'support/playground_report.dart';

class _GoalArtifacts {
  final Set<String> tools;
  final String mergedResponse;
  final String mergedTrace;
  final String mergedFunctionCalls;

  const _GoalArtifacts({
    required this.tools,
    required this.mergedResponse,
    required this.mergedTrace,
    required this.mergedFunctionCalls,
  });
}

Set<String> _extractToolNames(ChatMessage modelMessage) {
  final tools = <String>{};
  final trace = modelMessage.debugTrace ?? '';
  final traceMatches =
      RegExp(r'Model requested tool `([a-zA-Z0-9_]+)`').allMatches(trace);
  for (final match in traceMatches) {
    final name = match.group(1);
    if (name != null && name.isNotEmpty) {
      tools.add(name);
    }
  }

  final functionCalls = modelMessage.debugFunctionCalls ?? '';
  final callMatches =
      RegExp(r'^([a-zA-Z0-9_]+):', multiLine: true).allMatches(functionCalls);
  for (final match in callMatches) {
    final name = match.group(1);
    if (name != null && name.isNotEmpty) {
      tools.add(name);
    }
  }
  return tools;
}

String _buildStateDiff({
  required CalendarSnapshot before,
  required CalendarSnapshot after,
}) {
  final beforeIds = before.byId.keys.toSet();
  final afterIds = after.byId.keys.toSet();
  final added = afterIds.difference(beforeIds).length;
  final removed = beforeIds.difference(afterIds).length;
  final common = beforeIds.intersection(afterIds);
  var changed = 0;
  for (final id in common) {
    final prev = before.byId[id]!;
    final next = after.byId[id]!;
    if (prev.title != next.title ||
        prev.start != next.start ||
        prev.end != next.end ||
        prev.status != next.status) {
      changed++;
    }
  }
  return '+$added / -$removed / ~$changed';
}

Future<_GoalArtifacts> _runGoalTurns({
  required AppProvider provider,
  required PlaygroundGoal goal,
}) async {
  final tools = <String>{};
  final responses = <String>[];
  final traces = <String>[];
  final functionCalls = <String>[];

  for (final prompt in goal.prompts) {
    await provider.handleUserQuery(prompt);
    final modelMessage = provider.chatMessages.lastWhere(
      (message) => message.role == 'model',
      orElse: () => ChatMessage(role: 'model', content: ''),
    );
    responses.add(modelMessage.content);
    traces.add(modelMessage.debugTrace ?? '');
    functionCalls.add(modelMessage.debugFunctionCalls ?? '');
    tools.addAll(_extractToolNames(modelMessage));
  }

  return _GoalArtifacts(
    tools: tools,
    mergedResponse: responses.join('\n'),
    mergedTrace: traces.join('\n'),
    mergedFunctionCalls: functionCalls.join('\n'),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final targetCalendarId = resolvePlaygroundTargetCalendarId();
  final runTag = DateTime.now().millisecondsSinceEpoch.toString();
  print(
    'PLAYGROUND_E2E_BOOT runPlaygroundE2E=$runPlaygroundE2E '
    'targetCalendarId=$targetCalendarId runTag=$runTag',
  );

  if (!runPlaygroundE2E) {
    print('PLAYGROUND_E2E_SKIPPED: RUN_PLAYGROUND_E2E=false');
    return;
  }

  final resolvedTargetCalendarId = targetCalendarId.trim();
  final model = resolveModelForPlayground(AppConstants.defaultModel);

  final calendarService = CalendarService(
    defaultCalendarIdOverride: resolvedTargetCalendarId,
  );
  final provider = AppProvider(
    calendarService: calendarService,
    aiService: AiService(),
    autoStartListeningOnInit: false,
    enableCsvLogging: false,
    enableVoiceStack: false,
  );

  var initialized = false;
  try {
    await provider.initialize();
    if (provider.errorMessage != null) {
      throw StateError(
        'Provider initialization failed: ${provider.errorMessage}',
      );
    }
    if (provider.currentModel != model) {
      await provider.saveDefaultModel(model);
      print('PLAYGROUND_E2E_MODEL_OVERRIDE applied=$model');
    }

    await hardResetJanuary2027(
      service: calendarService,
      targetCalendarId: resolvedTargetCalendarId,
    );
    final seeded = await seedPlaygroundMatrix(
      service: calendarService,
      targetCalendarId: resolvedTargetCalendarId,
    );
    print(
      'Playground seeded on $resolvedTargetCalendarId '
      'with ${seeded.totalSeeded} events (runTag=$runTag)',
    );
    initialized = true;

    print(
      'PLAYGROUND_E2E_TEST_START runTag=$runTag target=$resolvedTargetCalendarId',
    );
    final goals = buildStressGoals(runTag: runTag);
    final verificationContext = GoalVerificationContext(
      service: calendarService,
      targetCalendarId: resolvedTargetCalendarId,
      runTag: runTag,
    );
    final goalResults = <PlaygroundGoalResult>[];

    for (final goal in goals) {
      print('PLAYGROUND_E2E_GOAL_START ${goal.id} - ${goal.description}');
      final startedAt = DateTime.now();
      final snapshotBefore = await captureJanuarySnapshot(
        service: calendarService,
        targetCalendarId: resolvedTargetCalendarId,
      );

      bool executionFailed = false;
      String executionError = '';
      _GoalArtifacts? artifacts;
      GoalCheck? verification;
      try {
        await provider.resetConversationForTesting();
        artifacts = await _runGoalTurns(
          provider: provider,
          goal: goal,
        );
        verification = await goal.verify(verificationContext);
      } catch (e) {
        executionFailed = true;
        executionError = e.toString();
      }

      final snapshotAfter = await captureJanuarySnapshot(
        service: calendarService,
        targetCalendarId: resolvedTargetCalendarId,
      );
      final duration = DateTime.now().difference(startedAt);

      var passed = !executionFailed && (verification?.passed ?? false);
      final reasons = <String>[];
      final toolsUsed = artifacts?.tools ?? const <String>{};
      final mergedResponse = artifacts?.mergedResponse ?? '';

      if (executionFailed) {
        passed = false;
        reasons.add('Execution error: $executionError');
      } else if (verification != null && !verification.passed) {
        reasons.add(verification.reason);
      } else {
        reasons.add('Verification ok');
      }

      final missingTools = goal.requiredTools
          .where((tool) => !toolsUsed.contains(tool))
          .toList();
      final loweredResponse = mergedResponse.toLowerCase();
      final missingKeywords = goal.requiredResponseKeywords
          .where((keyword) => !loweredResponse.contains(keyword))
          .toList();
      if (missingTools.isNotEmpty) {
        passed = false;
        reasons.add('Missing required tools: ${missingTools.join(', ')}');
      }
      if (missingKeywords.isNotEmpty) {
        passed = false;
        reasons.add('Missing response keywords: ${missingKeywords.join(', ')}');
      }

      goalResults.add(
        PlaygroundGoalResult(
          id: goal.id,
          description: goal.description,
          passed: passed,
          reason: reasons.join(' | '),
          toolsUsed: toolsUsed.isEmpty ? '-' : toolsUsed.join(','),
          responseSnippet: mergedResponse.length > 220
              ? '${mergedResponse.substring(0, 220)}...'
              : mergedResponse,
          stateDiff: _buildStateDiff(
            before: snapshotBefore,
            after: snapshotAfter,
          ),
          duration: duration,
        ),
      );
      print(
        'PLAYGROUND_E2E_GOAL_DONE ${goal.id} passed=$passed '
        'reason=${reasons.join(' | ')}',
      );
    }

    final aggregate = aggregateResults(goalResults);
    final report = buildMarkdownReport(goalResults, aggregate);
    print(report);
    print(
      'PLAYGROUND_E2E_AGGREGATE passRate=${aggregate.passRate} '
      'threshold=${aggregate.threshold} gate=${aggregate.gatePassed}',
    );

    final failedGoals = goalResults.where((result) => !result.passed).toList();
    final maxFailuresToPrint = min(6, failedGoals.length);
    final failureSummary = failedGoals
        .take(maxFailuresToPrint)
        .map((result) => '${result.id}: ${result.reason}')
        .join(' || ');

    if (!aggregate.gatePassed) {
      throw StateError(
        'Aggregate gate failed: passRate=${(aggregate.passRate * 100).toStringAsFixed(1)}%, '
        'threshold=${(aggregate.threshold * 100).toStringAsFixed(1)}%. '
        'Sample failures: $failureSummary',
      );
    }

    print('PLAYGROUND_E2E_FINAL PASS');
  } finally {
    if (initialized) {
      try {
        await hardResetJanuary2027(
          service: calendarService,
          targetCalendarId: resolvedTargetCalendarId,
        );
      } catch (e) {
        print('PLAYGROUND_E2E_CLEANUP_WARNING $e');
      }
      provider.dispose();
    }
  }
}

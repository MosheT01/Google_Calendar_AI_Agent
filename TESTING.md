# Testing Guide

This project uses two lanes:

1. `safe lane` (default): no real calendar writes, uses fakes/mocks.
2. `playground lane` (explicit): real calendar + real model on a dedicated test calendar.

## Safety Lock

All real-calendar lanes are locked to this calendar ID:

`58c4b0ccda887d9a1c0c2231af395b70a302c1d332e67189aebf3c4b941d6b37@group.calendar.google.com`

If any other `TEST_TARGET_CALENDAR_ID` or `TEST_TARGET_CALENDAR_URL` is passed, the run fails fast.

## Test Architecture

- `unit tests`: pure logic (formatters, constants, entities).
- `provider tests`: `AppProvider` state and orchestration.
- `widget tests`: UI behavior.
- `safe e2e-style flow`: web chat flow with fakes.
- `real playground lanes`: real Calendar API and real Gemini/tool-calling.

## Paths

- Safe tests: `google_calendar_ai_agent/test/*`
- Real playground tests: `google_calendar_ai_agent/test/playground/*`
- Real-stack runner: `google_calendar_ai_agent/lib/playground_e2e/*`
- Fakes: `google_calendar_ai_agent/test/support/fakes.dart`

## Safe Commands

Run from `google_calendar_ai_agent/`:

```bash
flutter test
flutter test --coverage
flutter test test/e2e/app_web_flow_test.dart -d chrome
flutter analyze
```

## Real Calendar Integration Lane

This lane hits real calendar APIs with strict guards:

- January 2027 only
- test titles must include `test_event_in_`
- cleanup removes only tagged January 2027 test artifacts

PowerShell:

```powershell
$env:RUN_REAL_CALENDAR_TESTS='true'
flutter test test/playground/calendar_real_jan_2027_test.dart -r expanded
```

bash/zsh:

```bash
RUN_REAL_CALENDAR_TESTS=true flutter test test/playground/calendar_real_jan_2027_test.dart -r expanded
```

## Real LLM Goal Lane

This lane uses real model + real calendar tools against the locked playground calendar:

PowerShell:

```powershell
$env:RUN_REAL_LLM_E2E='true'
flutter test test/playground/llm_goal_e2e_test.dart -r expanded
```

bash/zsh:

```bash
RUN_REAL_LLM_E2E=true flutter test test/playground/llm_goal_e2e_test.dart -r expanded
```

## Real-Stack Playground E2E (Chrome)

This is the full app-path lane:

- real `AppProvider.handleUserQuery`
- real `AiService` with `SystemPrompt.build()`
- real `CalendarService`
- hard reset + deterministic seed of January 2027 each run
- 20 goals + aggregate gate
- voice stack disabled only for this lane

### Required Defines

- `RUN_PLAYGROUND_E2E=true` (legacy `RUN_PRODUCTION_PLAYGROUND_E2E` still accepted)
- `E2E_WEB_FIREBASE_OPTIONS_B64`
- optional `E2E_PASS_THRESHOLD` (default `1.0`)
- optional `LLM_E2E_MODEL`

### Local Firebase Config

1. Copy template:
   - `google_calendar_ai_agent/test/playground/playground.local.example.json`
2. Create local file:
   - `google_calendar_ai_agent/test/playground/playground.local.json`
3. Fill web Firebase values.

This local file is gitignored.

### Run (PowerShell)

```powershell
$raw = Get-Content test/playground/playground.local.json -Raw
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($raw))

flutter run -d chrome --target lib/playground_e2e/playground_real_stack_runner.dart `
  --dart-define=RUN_PLAYGROUND_E2E=true `
  --dart-define=E2E_WEB_FIREBASE_OPTIONS_B64=$b64 `
  --dart-define=E2E_PASS_THRESHOLD=1.0 `
  --dart-define=LLM_E2E_MODEL=gemini-2.5-flash
```

### Run (bash/zsh)

```bash
E2E_B64="$(base64 -w 0 test/playground/playground.local.json)"

flutter run -d chrome --target lib/playground_e2e/playground_real_stack_runner.dart \
  --dart-define=RUN_PLAYGROUND_E2E=true \
  --dart-define=E2E_WEB_FIREBASE_OPTIONS_B64="$E2E_B64" \
  --dart-define=E2E_PASS_THRESHOLD=1.0 \
  --dart-define=LLM_E2E_MODEL=gemini-2.5-flash
```

### Logs

- Marker prefix: `PLAYGROUND_E2E_*`
- Recommended log path:
  - `google_calendar_ai_agent/.tmp/runner_runs/run_<timestamp>/flutter_run.out.log`

## Troubleshooting

- If auth fails, verify `assets/service_account.json`.
- If web startup fails, verify `E2E_WEB_FIREBASE_OPTIONS_B64`.
- If model quota is hit, rerun after quota reset or lower parallel activity.

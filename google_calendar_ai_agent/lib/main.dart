// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import './GoogleAPIs/textToSpeechAPI.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const CalendarApp());

class CalendarApp extends StatelessWidget {
  const CalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Calendar Assistant',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CalendarScreen(),
    );
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<calendar.Event> upcomingEvents = [];
  List<Map<String, String>> chatMessages = [];
  final queryController = TextEditingController();
  String? errorMessage;
  late calendar.CalendarApi calendarApi;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextToSpeechAPI _textToSpeechAPI =
      TextToSpeechAPI(); // Initialize TTS API
  bool _isListening = false;
  String _lastVoiceInput = '';
  final ScrollController _scrollController = ScrollController();
  late ChatSession _chat;
  bool _isChatInitialized = false;
  final int daysOfAccess = 60;
  String _currentModel = 'gemini-2.0-flash-exp'; // Default model
  bool _isLoading = true; // State to track loading status

  @override
  void initState() {
    logToCsv('newSession', "newSession");
    _startLoadingMessages();
    super.initState();

    // Start initialization
    initializeApp();
  }

  Future<void> initializeApp() async {
    try {
      // Load default model
      await loadDefaultModel();

      // Perform other initializations
      await loadChatHistory();
      await initializeCalendarApi();
      _initSpeechToText();
      initializeChat();

      // Set loading to false after initialization completes
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print("Error initializing app: $e");
      setState(() {
        _isLoading = false; // Stop loading even if an error occurs
        errorMessage = "Failed to initialize the app. Please try again.";
      });
    }
  }

  void _changeModel(String selectedModel) {
    setState(() {
      _currentModel = selectedModel;
    });

    // Save the selected model to shared preferences
    saveDefaultModel(selectedModel);

    // Reinitialize the Gemini Chat with the new model
    initializeChat();
    print("Changed model to: $_currentModel");
  }

  Future<void> loadDefaultModel() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentModel =
          prefs.getString('default_model') ?? 'gemini-2.0-flash-exp';
    });
    print("Loaded default model: $_currentModel");
  }

  Future<void> saveDefaultModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_model', model);
  }

  Future<void> _scrollToBottom() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
          // duration: Duration(milliseconds: 300),
          // curve: Curves.easeOut,
        );
      }
    });
  }

  void _initSpeechToText() async {
    print("Initializing Speech-to-Text...");
    bool available = await _speech.initialize(
      onStatus: (status) => print("Speech-to-Text Status: $status"),
      onError: (error) {
        print("Speech-to-Text Error: $error");
        _toggleListening();
      },
    );
    if (!available) {
      print("Speech-to-Text is NOT available.");
    } else {
      print("Speech-to-Text initialized successfully.");
      _toggleListening();
    }
  }

  void _toggleListening() async {
    if (_isListening) {
      print("Stopping Speech-to-Text...");
      await _speech
          .stop(); // Use await to ensure it completes before proceeding
      setState(() => _isListening = false);
      return; // Exit to avoid restarting
    }

    print("Starting Speech-to-Text...");
    // Stop TTS if it's speaking
    _audioPlayer.stop();

    bool available = await _speech.initialize(
      onStatus: (status) {
        print("Speech-to-Text Status: $status");
        if (status == "notListening") {
          setState(() => _isListening = false);
        }
        if (status == "done") {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        print("Speech-to-Text Error: $error");
        setState(() => _isListening = false);
      },
    );

    if (available) {
      print("Speech-to-Text is available.");
      setState(() => _isListening = true);
      _speech.listen(
          onResult: (result) {
            print("Speech-to-Text Result: ${result.recognizedWords}");
            setState(() => _lastVoiceInput = result.recognizedWords);
            if (result.finalResult) {
              print("Final Speech-to-Text Result: $_lastVoiceInput");
              setState(() => _isListening = false);
              handleUserQuery(_lastVoiceInput);
            }
          },
          listenOptions: stt.SpeechListenOptions(
            autoPunctuation: true,
            enableHapticFeedback: true,
            cancelOnError: false,
            onDevice: false,
          ),
          pauseFor: const Duration(seconds: 5));
    } else {
      print("The user has denied microphone permissions.");
    }
  }

  Future<void> initializeCalendarApi() async {
    try {
      print("Initializing Calendar API...");
      final credentials = jsonDecode(
        await rootBundle.loadString('assets/service_account.json'),
      );

      final accountCredentials =
          ServiceAccountCredentials.fromJson(credentials);

      final authClient = await clientViaServiceAccount(
        accountCredentials,
        [calendar.CalendarApi.calendarScope],
      );

      calendarApi = calendar.CalendarApi(authClient);
      print("Calendar API initialized successfully.");
      await fetchUpcomingEvents();
    } catch (e) {
      print("Error initializing Calendar API: $e");
      setState(() {
        errorMessage = "Failed to initialize Calendar API: $e";
      });
    }
  }

  Future<List<calendar.Event>> fetchEventsForUpcomingPeriod() async {
    print("Fetching events for the time period...");
    try {
      final now = DateTime.now().toUtc();
      final startOfRange = now.subtract(const Duration(days: 1));
      final endOfRange = startOfRange.add(Duration(days: daysOfAccess));

      final eventsResult = await calendarApi.events.list(
        'mousatams@gmail.com',
        timeMin: startOfRange,
        timeMax: endOfRange,
        singleEvents: true,
        orderBy: 'startTime',
      );

      print("Fetched ${eventsResult.items?.length ?? 0} events.");

      const TranslateLanguage sourceLanguage = TranslateLanguage.hebrew;
      const TranslateLanguage targetLanguage = TranslateLanguage.english;
      final onDeviceTranslator = OnDeviceTranslator(
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );

      final nonLatinRegex =
          RegExp(r'[^\x00-\x7F]'); // Regex to detect non-Latin characters

      final List<calendar.Event> translatedEvents =
          await Future.wait(eventsResult.items?.map((event) async {
                String summary = event.summary ?? 'No Title';

                // Remove all instances of [מוסא טמס]
                summary = summary.replaceAllMapped(
                    RegExp(r'\[מוסא טמס\]'), (match) => '');

                // Translate non-Latin text
                if (nonLatinRegex.hasMatch(summary)) {
                  summary = await onDeviceTranslator.translateText(summary);
                }
                // if (event.description != null &&
                //     nonLatinRegex.hasMatch(event.description!)) {
                //   event.description = await onDeviceTranslator
                //       .translateText(event.description!);
                // }
                // if (event.location != null &&
                //     nonLatinRegex.hasMatch(event.location!)) {
                //   event.location =
                //       await onDeviceTranslator.translateText(event.location!);
                // }

                event.summary = summary;
                event.start?.dateTime = event.start?.dateTime?.toLocal();
                event.end?.dateTime = event.end?.dateTime?.toLocal();
                return event;
              }) ??
              []);

      onDeviceTranslator.close();

      return translatedEvents;
    } catch (e) {
      print("Error fetching events the time period: $e");
      return [];
    }
  }

  Future<void> fetchUpcomingEvents() async {
    final events = await fetchEventsForUpcomingPeriod();
    setState(() {
      upcomingEvents = events;
    });
  }

  String formatEventsForGPT(List<calendar.Event> events) {
    print("Formatting events for GPT...");
    final buffer = StringBuffer();
    for (var event in events) {
      final start = event.start?.dateTime ?? event.start?.date;
      final end = event.end?.dateTime ?? event.end?.date;
      buffer.writeln("Event ID: ${event.id ?? 'No ID'}");
      buffer.writeln("Event: ${event.summary ?? 'No Title'}");
      buffer.writeln("  Start: ${start?.toIso8601String() ?? 'Unknown'}");
      buffer.writeln("  End: ${end?.toIso8601String() ?? 'Unknown'}");
      if (event.description != null) {
        buffer.writeln("  Description: ${event.description}");
      }
      if (event.location != null) {
        buffer.writeln("  Location: ${event.location}");
      }
      buffer.writeln("------");
    }
    return buffer.toString();
  }

  Future<String> queryGeminiFlashWithCalendarData(String userQuery) async {
    if (!_isChatInitialized) {
      return "Error: Chat is not initialized.";
    }

    print("Querying Gemini AI with User Query: $userQuery");
    final formattedEvents = formatEventsForGPT(upcomingEvents);
    print("Formatted Events for AI Input:\n$formattedEvents");

    // Fetch free/busy data for the next period
    final now = DateTime.now();
    final end = now.add(Duration(days: daysOfAccess));
    final busyPeriods = await fetchFreeBusyData(now, end);

    // Format free and busy periods for GPT
    final freeBusyData = StringBuffer();
    freeBusyData.writeln("Busy periods:");
    for (var period in busyPeriods) {
      freeBusyData.writeln(
          "- ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(period['start']).toLocal())} to ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(period['end']).toLocal())}");
    }

    print("Formatted Free/Busy Data for AI Input:\n$freeBusyData");
    // Log the formatted free/busy data
    logger.log(
        Level.info, "Formatted Free/Busy Data for AI Input:\n$freeBusyData");

    // Include free/busy data in the prompt
    final prompt = '''
You are an AI assistant with access to the user's calendar and free/busy data for the next $daysOfAccess calendar days in israel.
adhere to the system instruction and respond strictly as instructed.

Today is ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())} (${DateFormat('EEEE').format(DateTime.now())}).


Here is the user's calendar data:
$formattedEvents

Here is the user's free/busy data:
$freeBusyData

The user query: $userQuery
''';
    setState(() {
      _isThinking = true;
    });

    try {
      final content = Content.text(prompt);
      final response = await _chat.sendMessage(content);
      print("AI Response: ${response.text}");
      var toReturn = response.text ?? "Error: No response received.";

      logToCsv(prompt, toReturn);
      setState(() {
        _isThinking = false;
      });

      return toReturn;
    } catch (e) {
      setState(() {
        _isThinking = false;
      });

      print("Error querying Gemini AI: $e");
      return "Error: $e";
    }
  }

  Future<void> logToCsv(String prompt, String response) async {
    try {
      // Check and request storage or manage storage permission
      if (await Permission.storage.isDenied ||
          await Permission.manageExternalStorage.isDenied) {
        var status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          print("Storage permission denied. Cannot log to CSV.");
          return;
        }
      }

      // Get the application's Download directory
      final directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        print("Download directory not found. Cannot log to CSV.");
        return;
      }

      final filePath = '${directory.path}/ai_logs.csv';
      final file = File(filePath);

      // Check if file exists, create and add headers if it doesn't
      if (!await file.exists()) {
        await file.writeAsString("Timestamp,Prompt,Response\n");
      }

      // Append the new log entry
      final timestamp = DateTime.now().toIso8601String();
      final csvLine =
          '"$timestamp","${prompt.replaceAll('"', '""')}","${response.replaceAll('"', '""')}"\n';

      await file.writeAsString(csvLine, mode: FileMode.append, flush: true);
      print("Logged to CSV at: $filePath");
    } catch (e) {
      print("Error logging to CSV: $e");
    }
  }

  Future<void> initializeChat() async {
    try {
      print("Initializing Gemini Chat...");
      final apiKey = jsonDecode(
        await rootBundle.loadString('assets/gemini_api_key.json'),
      )['api_key'];

      final model = GenerativeModel(
        model: _currentModel,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 2,
          maxOutputTokens: 1000,
        ),
        systemInstruction: Content.system(
            '''You are an AI assistant with access to the user's calendar for the next for the next $daysOfAccess calendar days in israel.
today = ${DateFormat('yyyy-MM-dd').format(DateTime.now())} and the day is ${DateFormat('EEEE').format(DateTime.now())}.
Your responses must strictly adhere to the following format:

**Response Modes:**
1. **Clarifying Mode**: Start your response with `mode=clarifying` followed by the clarification question.
   Example: `mode=clarifying What is the title of the event and what time is the event?`
   use this mode until you have the necessary information to execute the command then ask for confirmation before executing the command by switching to code_output mode.

2. **Code Output Mode**: Start your response with `mode=code_output` followed by a stack of commands in the format:
   `commandsToBeExecutedStack={command1|||command2|||...}` \n Reasoning: your reasoning here.
   Example: `mode=code_output commandsToBeExecutedStack={addEvent(title: "Lunch", startTime: "2025-01-02T12:00:00.000", endTime: "2025-01-02T13:00:00.000")} \n reasoning: The user wants to add a lunch event on January 2, 2025, from 12:00 PM to 1:00 PM.`
   You have access to these functions to manipulate the calendar: and only these! no more no less.
          1. addEvent(String title, DateTime startTime, {DateTime? endTime,String? description,String? location,String? colorId})
          2. updateEvent(String eventId,{String? title,DateTime? startTime,DateTime? endTime,String? description,String? location,String? colorId})
          3. deleteEvent(String eventId)
          for refrence colorOptions = {"1": "light purple","2": "light green","3": "purple","4": "tan","5": "yellow","6": "orange","7": "cyan","8": "gray", "9": "blue", "10": "dark green", "11": "red",}
          before using this mode you should always ask for confirmation before executing any command in clarifying mode.
          then in the next interaction you should switch to code_output mode to execute the command stack.

3. **Generic Response Mode**:Start your response with `mode=generic` followed by the response text. use this when you don't need to execute any commands for example when the user asks for information regrading the calendar data you already have.
   Example: `User: what do I have on my calendar tommorow?` Response: `mode=generic tommorow you have Event1 at 12:00 PM and Event2 at 2:00 PM`
   Example: `mode=generic Sure, I can help you with that.`
   in this mode you provide helpful insight like alerting when the user is trying to add an event that conflicts with an existing event.
   or when the user is trying to update an event that does not exist.
   or when the user has two events that conflict with each other.
   example: what do I have on my calendar tommorow? Response: mode=generic tommorow you have Event1 at 12:00 PM till 1:00 PM and Event2 at 12:30 PM till 1:30 PM ,be aware that Event1 and Event2 overlap each other, would you like to update any of them?.
   you have more freedom in this mode to provide any helpful information to the user be creative.

**Important Rules:**
- Do not include prefixes like "Assistant:" in your response.
- Do not add any explanation, context, or extra text.
- Your response must only contain the mode and the commands or questions as specified above.
- use the event IDs from the calendar data you have in the conversation history to update or delete events.
- when the user says "it" or "that" in the response you should refer to the last event mentioned in the conversation history.
- never mention event id to the user, only use them to update or delete events.
- when the user asks for information regarding the calendar data you already have, respond in generic mode.
- when the user asks to add an event that conflicts with an existing event, respond in generic mode.
- always responds in a neat and organised way that is best for text to speech.
- always add a confirmation step before executing any command,in this step explain to the user what you are about to do fully and ask for confirmation.
-if the user doent have any event for a timeslot in the calendar it means he is free at that time.
-before executing any command always ask for confirmation with the summery of the change before executing the command.
-dont over complicate the response, keep it simple and to the point.
-dont ask for too many confirmations, only ask for confirmation when you are about to execute a command,and dont ask too many questions if you already have all the neccaesary information to execute the command.

Respond strictly as instructed.
The minimum info needed to add an event is the title and start time; the end time defaults to 1 hour after the start time.
The minimum info needed to update an event is the event ID.
Use the event IDs from the calendar data above to update or delete events.
do not prefix your response with "model:" or anything similar other than the current mode.

 '''),
      );
      print("Chat messages before initializing chat: $chatMessages");
      final conversationHistory = chatMessages.map((message) {
        return Content.text('${message['role']}: ${message['content']}');
      }).toList();

      _chat = model.startChat(history: conversationHistory);

      _isChatInitialized = true;
      print("Gemini Chat initialized successfully.");
      print("Initialized chat with history: $conversationHistory");
    } catch (e) {
      print("Error initializing Gemini Chat: $e");
      setState(() {
        errorMessage = "Failed to initialize Gemini Chat: $e";
      });
    }
  }

  void executeCommandStack(List<String> commands) {
    print("Executing command stack: $commands");
    for (final command in commands.reversed) {
      if (command.startsWith('addEvent')) {
        final args = parseArguments(command);
        final title = args['title'];
        final startTime = args['startTime'] != null
            ? DateTime.parse(args['startTime']!)
            : null;
        final endTime =
            args['endTime'] != null ? DateTime.parse(args['endTime']!) : null;

        if (title != null && startTime != null) {
          addEvent(
            title,
            startTime,
            endTime: endTime,
            description: args['description'],
            location: args['location'],
            colorId: args['colorId'],
          );
        } else {
          print("Missing required arguments for addEvent.");
        }
      } else if (command.startsWith('updateEvent')) {
        final args = parseArguments(command);
        final eventId = args['eventId'];
        if (eventId != null) {
          updateEvent(
            eventId,
            title: args['title'],
            startTime: args['startTime'] != null
                ? DateTime.parse(args['startTime']!)
                : null,
            endTime: args['endTime'] != null
                ? DateTime.parse(args['endTime']!)
                : null,
            description: args['description'],
            location: args['location'],
            colorId: args['colorId'],
          );
        } else {
          print("Missing eventId for updateEvent.");
        }
      } else if (command.startsWith('deleteEvent')) {
        final args = parseArguments(command);
        final eventId = args['eventId'];
        if (eventId != null) {
          deleteEvent(eventId);
        } else {
          print("Missing eventId for deleteEvent.");
        }
      }
    }
  }

  Future<void> saveChatHistory() async {
    print("Attempting to save chat history: $chatMessages");
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonMessages = jsonEncode(chatMessages.map((entry) {
        return entry
            .map((key, value) => MapEntry(key.toString(), value.toString()));
      }).toList());
      await prefs.setString('chat_history', jsonMessages);
      print("Chat history saved successfully: $jsonMessages");
    } catch (e) {
      print("Error saving chat history: $e");
    }
  }

  final logger = Logger();

  bool _isThinking = false;

  Future<void> loadChatHistory() async {
    logger.i("Attempting to load chat history...");
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonMessages = prefs.getString('chat_history');
      if (jsonMessages != null) {
        logger.i("Raw JSON Loaded: $jsonMessages");
        final dynamicMessages = jsonDecode(jsonMessages) as List;
        setState(() {
          chatMessages = dynamicMessages
              .map((message) => Map<String, String>.from(message))
              .toList();
        });
        logger.i("Loaded chat history: $chatMessages");
      } else {
        logger.i("No chat history found.");
      }
    } catch (e) {
      logger.e("Error loading chat history: $e");
    }
  }

  Map<String, String> parseArguments(String command) {
    print("Parsing command arguments: $command");
    final args = <String, String>{};

    // Extract the content within the parentheses
    final regex = RegExp(r'\((.*)\)');
    final match = regex.firstMatch(command);
    if (match == null) {
      print("No arguments found in command: $command");
      return args;
    }

    // Get the content inside parentheses
    final arguments = match.group(1);
    if (arguments == null) {
      print("No arguments found within parentheses.");
      return args;
    }

    // Match key-value pairs with possible nested quotes
    final keyValueRegex = RegExp(r'(\w+)\s*:\s*(".*?"|[^,]+)');
    for (final match in keyValueRegex.allMatches(arguments)) {
      final key = match.group(1)?.trim();
      var value = match.group(2)?.trim();

      if (key != null && value != null) {
        // Remove surrounding quotes from the value if present
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        args[key] = value;
      }
    }

    print("Parsed arguments: $args");
    return args;
  }

  void handleUserQuery(String query) async {
    if (query.isEmpty) return;

    print("Handling user query: $query");

    // Add user message to chat
    setState(() {
      chatMessages.add({'role': 'user', 'content': query});
    });

    // Query GPT
    final response = await queryGeminiFlashWithCalendarData(query);

    print("Received GPT Response: $response");

    String cleanResponse(String response) {
      var toReturn = response.replaceAll(RegExp(r'(\n)+'), '\n');
      toReturn = toReturn.replaceAll(RegExp(r'\*'), '');
      toReturn = toReturn.replaceAll(RegExp(r'(?<!\n)\.\s'), '.\n\n');
      toReturn = toReturn.replaceAll(RegExp(r'(?<!\n),\s'), ',\n');
      return toReturn.replaceFirst(RegExp(r'^mode=\w+\s*'), '').trim();
    }

    if (response.startsWith('mode=clarifying')) {
      setState(() {
        chatMessages.add({'role': 'model', 'content': cleanResponse(response)});
      });

      _speak(cleanResponse(response).replaceAll('\n', ' '));
    } else if (response.startsWith('mode=code_output')) {
      final commandStack = extractCommandStack(response);
      executeCommandStack(commandStack);
      var cleanedResponse = "Executed ${commandStack.length} commands!";
      //log the original response to app logs
      print("Code Execution: $response");
      setState(() {
        chatMessages.add({
          'role': 'model',
          'content': cleanedResponse,
        });
      });
      //  _speak(cleanResponse(response));
      _speak("Executed ${commandStack.length} commands!");
    } else {
      // Generic response handling
      setState(() {
        chatMessages.add({'role': 'model', 'content': cleanResponse(response)});
      });
      _speak(cleanResponse(response).replaceAll('\n', ' '));
    }

    saveChatHistory(); // Save chat history after receiving a response
  }

  String formatTextWithPeriodsForSpeech(String text) {
    StringBuffer modifiedText = StringBuffer();
    int charCount = 0; // Counter for characters in the current segment
    bool hasPeriod = false; // Flag to check if the segment contains a period

    for (int i = 0; i < text.length; i++) {
      charCount++;

      // Mark if the current character is a period
      if (text[i] == '.') {
        hasPeriod = true;
      }

      // Add a period before the nearest space if no period exists in 100 characters
      if (charCount >= 100 && !hasPeriod && text[i] == ' ') {
        modifiedText.write('.'); // Insert a period
        modifiedText.write(' '); // Maintain proper spacing
        hasPeriod = true; // Mark that a period has been added
      }

      // Add the current character to the buffer
      modifiedText.write(text[i]);

      // Reset counters and flags after processing 100 characters
      if (charCount >= 100 && (text[i] == '.' || text[i] == ' ')) {
        charCount = 0;
        hasPeriod = false;
      }
    }

    // Log old and new texts for debugging
    print("Old Text: $text");
    print("New Text: $modifiedText");

    return modifiedText.toString();
  }

  Future<void> _speak(String text) async {
    if (_isListening) {
      print("Mic is active, skipping TTS.");
      return; // Skip TTS if the mic is listening
    }
    String modifiedText = formatTextWithPeriodsForSpeech(text);

    try {
      final audioContent = await _textToSpeechAPI
          .getSpeechAudio(modifiedText.toString()); // Fetch synthesized audio
      final audioBytes = base64Decode(audioContent);
      await _audioPlayer.play(BytesSource(audioBytes)); // Play audio
      _audioPlayer.onPlayerComplete.listen((event) async {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!_isListening) {
          _toggleListening();
        }
      });
      print("Playing audio for text: $text");
    } catch (e) {
      print("Error in TTS: $e");
    }
  }

  List<String> extractCommandStack(String response) {
    print("Extracting command stack from response: $response");

    final startIndex = response.indexOf('{');
    final endIndex = response.indexOf('}');
    if (startIndex != -1 && endIndex != -1) {
      final commandsString = response.substring(startIndex + 1, endIndex);
      return commandsString.split('|||').map((cmd) => cmd.trim()).toList();
    }

    print("No command stack found in response.");
    return [];
  }

  void addEvent(String title, DateTime startTime,
      {DateTime? endTime,
      String? description,
      String? location,
      String? colorId}) {
    print("Adding event: $title");

    // Set Israel timezone for start and end times
    final event = calendar.Event(
      summary: title,
      start: calendar.EventDateTime(
        dateTime: startTime.toUtc(),
        timeZone: 'Asia/Jerusalem', // Israel timezone
      ),
      end: calendar.EventDateTime(
        dateTime: (endTime ?? startTime.add(const Duration(hours: 1))).toUtc(),
        timeZone: 'Asia/Jerusalem', // Israel timezone
      ),
      description: description,
      location: location,
      colorId: colorId, // Add the colorId
    );

    calendarApi.events.insert(event, 'mousatams@gmail.com').then((value) {
      print("Event added: ${value.summary}");
      fetchUpcomingEvents();
    }).catchError((error) {
      print("Error adding event: $error");
    });
  }

  void updateEvent(String eventId,
      {String? title,
      DateTime? startTime,
      DateTime? endTime,
      String? description,
      String? location,
      String? colorId}) {
    print("Updating event: $eventId");

    calendarApi.events.get('mousatams@gmail.com', eventId).then((event) {
      if (title != null) event.summary = title;
      if (startTime != null) {
        event.start = calendar.EventDateTime(
          dateTime: startTime.toUtc(),
          timeZone: 'Asia/Jerusalem', // Israel timezone
        );
      }
      if (endTime != null) {
        event.end = calendar.EventDateTime(
          dateTime: endTime.toUtc(),
          timeZone: 'Asia/Jerusalem', // Israel timezone
        );
      }
      if (description != null) event.description = description;
      if (location != null) event.location = location;
      if (colorId != null) event.colorId = colorId;

      calendarApi.events
          .update(event, 'mousatams@gmail.com', eventId)
          .then((value) {
        print("Event updated: ${value.summary}");
        fetchUpcomingEvents();
      }).catchError((error) {
        print("Error updating event: $error");
      });
    }).catchError((error) {
      print("Error fetching event: $error");
    });
  }

  void deleteEvent(String eventId) {
    print("Deleting event: $eventId");
    calendarApi.events.delete('mousatams@gmail.com', eventId).then((_) {
      print("Event deleted: $eventId");
      fetchUpcomingEvents();
    });
  }

  Future<List<Map<String, dynamic>>> fetchFreeBusyData(
      DateTime start, DateTime end) async {
    print("Fetching FreeBusy data from $start to $end...");
    try {
      final request = calendar.FreeBusyRequest(
        timeMin: start.toUtc(),
        timeMax: end.toUtc(),
        items: [
          calendar.FreeBusyRequestItem(id: 'mousatams@gmail.com'),
        ],
      );

      final response = await calendarApi.freebusy.query(request);

      if (response.calendars != null &&
          response.calendars!['mousatams@gmail.com']?.busy != null) {
        final busyTimes = response.calendars!['mousatams@gmail.com']!.busy!;
        print("FreeBusy Data: $busyTimes");

        return busyTimes.map((period) {
          return {
            'start': period.start?.toIso8601String(),
            'end': period.end?.toIso8601String(),
          };
        }).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching FreeBusy data: $e");
      return [];
    }
  }

  final _loadingMessages = [
    "Initializing the app...",
    "Loading the AI assistant...",
    "Setting up the chat...",
    "Loading the calendar data...",
    "Almost there...",
    "Preparing your schedule...",
    "Fetching events...",
    "Optimizing performance...",
    "Finalizing setup...",
    "Loading user preferences...",
    "Syncing with Google Calendar...",
    "Analyzing past events...",
    "Setting up notifications...",
    "Configuring voice recognition...",
    "Loading language models...",
    "Preparing translation services...",
    "Initializing text-to-speech...",
    "Setting up user interface...",
    "Almost done...",
  ];
  var _loadingMessageIndex = 0;

  void _startLoadingMessages() async {
    while (_isLoading) {
      await Future.delayed(const Duration(milliseconds: 750));
      if (!_isLoading) break; // Stop updating if loading is complete
      setState(() {
        _loadingMessageIndex =
            (_loadingMessageIndex + 1) % _loadingMessages.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while the app initializes
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Color.fromARGB(255, 246, 110, 142),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
              const SizedBox(height: 20),
              Text(
                _loadingMessages[_loadingMessageIndex],
                style: GoogleFonts.lato(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Main chat screen
    return Scaffold(
      // Pastel pink app bar with circular border
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70.0),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFF7F9C), // a pastel/pink color
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: AppBar(
            backgroundColor:
                Colors.transparent, // Make AppBar background transparent
            forceMaterialTransparency: true,
            bottomOpacity: 0.0,
            elevation: 0, // remove shadow for a cleaner look
            centerTitle: true,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Leading avatar
                const CircleAvatar(
                  backgroundColor: Color(0xFFFF7F9C),
                  backgroundImage: NetworkImage(
                    'https://www.iconarchive.com/download/i26941/noctuline/wall-e/EVE.ico',
                  ),
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Bella",
                      style: GoogleFonts.lato(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "Online",
                      style: GoogleFonts.lato(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                onSelected: (String selectedModel) {
                  _changeModel(selectedModel); // Change the model on selection
                },
                itemBuilder: (BuildContext context) => [
                  const PopupMenuItem(
                      value: 'gemini-1.5-flash-8b',
                      child: Text('Gemini 1.5 Flash 8B')),
                  const PopupMenuItem(
                      value: 'gemini-1.5-flash',
                      child: Text('Gemini 1.5 Flash')),
                  const PopupMenuItem(
                      value: 'gemini-2.0-flash-exp',
                      child: Text('Gemini 2.0 Flash Exp')),
                ],
                icon: const Icon(Icons.more_vert, color: Colors.white),
              ),
            ],
          ),
        ),
      ),

      // Use a lighter pink/cream as the background
      backgroundColor: const Color(0xFFFFF8F8),

      body: Column(
        children: [
          // The main chat list
          Expanded(
            child: _buildChatBubbleAndScrollToBottom(),
          ),

          // The input section at the bottom
          _buildInputSection(),
        ],
      ),
    );
  }

  // Builds the bottom input section
  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            // The text input
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 40.0,
                    maxHeight: 150.0,
                  ),
                  child: Scrollbar(
                    child: TextField(
                      controller: queryController,
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: "Type a message...",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {}); // to update button icon
                      },
                      onSubmitted: (value) {
                        if (value.isNotEmpty) {
                          handleUserQuery(value);
                          queryController.clear();
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Microphone or send button
            if (_isListening)
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.red,
                child: IconButton(
                  icon: const Icon(Icons.mic, color: Colors.white),
                  onPressed: _toggleListening,
                ),
              )
            else
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFFF7F9C),
                child: IconButton(
                  icon: Icon(
                    queryController.text.trim().isEmpty
                        ? Icons.mic
                        : Icons.send,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    final text = queryController.text.trim();
                    if (text.isNotEmpty) {
                      handleUserQuery(text);
                      queryController.clear();
                      setState(() {});
                    } else {
                      _toggleListening();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Build the chat bubble list and scroll to bottom
  Widget _buildChatBubbleAndScrollToBottom() {
    final listView = _buildChatListView();
    _scrollToBottom();
    return listView;
  }

  // List of chat bubbles
  Widget _buildChatListView() {
    return ListView.builder(
      controller: _scrollController,
      itemCount: _isThinking ? chatMessages.length + 1 : chatMessages.length,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      itemBuilder: (context, index) {
        if (_isThinking && index == chatMessages.length) {
          // Add "Thinking..." bubble at the end if _isThinking is true
          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              _buildChatBubble('Thinking...', false),
              const SizedBox(width: 8),
              const CircularProgressIndicator(
                color: Colors.red,
                strokeWidth: 2,
              ),
            ],
          );
        }
        final message = chatMessages[index];
        final isUser = message['role'] == 'user';
        return _buildChatBubble(message['content'] ?? '', isUser);
      },
    );
  }

  // Single chat bubble
  Widget _buildChatBubble(String message, bool isUser) {
    // Adjust the colors to pink for user and white for assistant
    const Color userBubbleColor = Color(0xFFFFDEE2); // pinkish
    final Color assistantBubbleColor = Colors.grey.shade200; // white
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? userBubbleColor : assistantBubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: SelectableText(
          message,
          style: GoogleFonts.lato(
            fontSize: 16,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
          textAlign: TextAlign.left, // Ensures proper alignment for paragraphs
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

void main() => runApp(CalendarApp());

class CalendarApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Calendar Assistant',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: CalendarScreen(),
    );
  }
}

class CalendarScreen extends StatefulWidget {
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
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  String _lastVoiceInput = '';
  final ScrollController _scrollController = ScrollController();
  late ChatSession _chat;
  bool _isChatInitialized = false;
  final int daysOfAccess = 60;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    loadChatHistory().then((_) {
      initializeCalendarApi().then((_) {
        _initSpeechToText();
        initializeChat();
      });
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
      _speech.stop();
      setState(() => _isListening = false);
    } else {
      print("Starting Speech-to-Text...");
      // Stop TTS if it's speaking
      await _flutterTts.stop();

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
                _toggleListening(); // Stop listening automatically
                handleUserQuery(_lastVoiceInput);
              }
            },
            listenOptions: stt.SpeechListenOptions(
              autoPunctuation: true,
              enableHapticFeedback: true,
              cancelOnError: false,
            ));
      } else {
        print("The user has denied microphone permissions.");
      }
    }
  }

  void _initTextToSpeech() {
    _flutterTts.setLanguage('en-US');
    _flutterTts.setVolume(1.0);
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setPitch(1.0);
    _flutterTts.setCompletionHandler(() {
      print("TTS completed.");
      _toggleListening(); // Automatically restart listening after speech
    });
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
      final startOfRange = now.subtract(Duration(days: 1));
      final endOfRange = startOfRange.add(Duration(days: daysOfAccess));

      final eventsResult = await calendarApi.events.list(
        'mousatams@gmail.com',
        timeMin: startOfRange,
        timeMax: endOfRange,
        singleEvents: true,
        orderBy: 'startTime',
      );

      print("Fetched ${eventsResult.items?.length ?? 0} events.");
      return eventsResult.items?.map((event) {
            event.start?.dateTime = event.start?.dateTime?.toLocal();
            event.end?.dateTime = event.end?.dateTime?.toLocal();
            return event;
          }).toList() ??
          [];
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
    final freePeriods = calculateFreePeriods(busyPeriods, now, end);

    // Format free and busy periods for GPT
    final freeBusyData = StringBuffer();
    freeBusyData.writeln("Busy periods:");
    for (var period in busyPeriods) {
      freeBusyData.writeln(
          "- ${DateTime.parse(period['start']).toLocal()} to ${DateTime.parse(period['end']).toLocal()}");
    }
    freeBusyData.writeln("Free periods:");
    for (var period in freePeriods) {
      freeBusyData.writeln("- ${period['start']} to ${period['end']}");
    }

    // Include free/busy data in the prompt
    final prompt = '''
You are an AI assistant with access to the user's calendar and free/busy data for the $daysOfAccess calendar days in israel.
adhere to the system instruction and respond strictly as instructed.

Today is ${DateFormat('yyyy-MM-dd').format(DateTime.now())} (${DateFormat('EEEE').format(DateTime.now())}).

Here is the user's calendar data:
$formattedEvents

Here is the user's free/busy data:
$freeBusyData

The user query: $userQuery
''';

    try {
      final content = Content.text(prompt);
      final response = await _chat.sendMessage(content);
      print("AI Response: ${response.text}");
      return response.text ?? "Error: No response received.";
    } catch (e) {
      print("Error querying Gemini AI: $e");
      return "Error: $e";
    }
  }

  Future<void> initializeChat() async {
    try {
      print("Initializing Gemini Chat...");
      final apiKey = jsonDecode(
        await rootBundle.loadString('assets/gemini_api_key.json'),
      )['api_key'];

      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          topK: 80,
          topP: 0.9,
          temperature: 2,
          maxOutputTokens: 1000,
        ),
        systemInstruction: Content.system(
            '''You are an AI assistant with access to the user's calendar for the next two weeks.
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
          for refrence colorOptions = {"1": "Lavender","2": "Sage","3": "Grape","4": "Flamingo","5": "Banana","6": "Tangerine","7": "Peacock","8": "Graphite", "9": "Blueberry", "10": "Basil", "11": "Tomato",}
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
- if you come accross anything that is not english text,translare it to english before responding and respond with the english translation.
- always responds in a neat and organised way that is best for text to speech.
- always add a confirmation step before executing any command,in this step explain to the user what you are about to do fully and ask for confirmation.
-if the user doent have any event for a timeslot in the calendar it means he is free at that time.
-before executing any command always ask for confirmation with the summery of the change before executing the command.

Respond strictly as instructed.
The minimum info needed to add an event is the title and start time; the end time defaults to 1 hour after the start time.
The minimum info needed to update an event is the event ID.
Use the event IDs from the calendar data above to update or delete events.

 '''),
      );
      print("Chat messages before initializing chat: ${chatMessages}");
      final conversationHistory = chatMessages.map((message) {
        return Content.text('${message['role']}: ${message['content']}');
      }).toList();

      _chat = model.startChat(history: conversationHistory);

      _isChatInitialized = true;
      print("Gemini Chat initialized successfully.");
      print("Initialized chat with history: ${conversationHistory}");
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
    _scrollToBottom(); // Scroll to the latest message

    // Query GPT
    final response = await queryGeminiFlashWithCalendarData(query);

    print("Received GPT Response: $response");

    String cleanResponse(String response) {
      // Remove "mode=..." prefix from the response
      return response.replaceFirst(RegExp(r'^mode=\w+\s*'), '').trim();
    }

    if (response.startsWith('mode=clarifying')) {
      setState(() {
        chatMessages.add({'role': 'model', 'content': cleanResponse(response)});
      });

      _speak(cleanResponse(response));
    } else if (response.startsWith('mode=code_output')) {
      final commandStack = extractCommandStack(response);
      executeCommandStack(commandStack);
      setState(() {
        chatMessages.add({
          'role': 'model',
          'content': response,
        });
      });
      _speak(cleanResponse(response));
      _speak(
          "Executed ${commandStack.length} commands. Reason: ${cleanResponse(response).split('reasoning:').last.trim()}");
    } else {
      // Generic response handling
      setState(() {
        chatMessages.add({'role': 'model', 'content': cleanResponse(response)});
      });
      _speak(cleanResponse(response));
    }
    saveChatHistory(); // Save chat history after receiving a response
    _scrollToBottom(); // Scroll to the latest message
  }

  Future<void> _speak(String text) async {
    if (_isListening) {
      print("Mic is active, skipping TTS.");
      return; // Skip TTS if the mic is listening
    }

    print("Speaking Text: $text");
    await _flutterTts.speak(text);
    _flutterTts.setCompletionHandler(() {
      print("TTS completed, restarting mic...");
      _toggleListening(); // Automatically restart listening
    });
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
    final event = calendar.Event(
      summary: title,
      start: calendar.EventDateTime(dateTime: startTime.toUtc()),
      end: calendar.EventDateTime(
          dateTime: (endTime ?? startTime.add(Duration(hours: 1))).toUtc()),
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
      if (startTime != null)
        event.start = calendar.EventDateTime(dateTime: startTime.toUtc());
      if (endTime != null)
        event.end = calendar.EventDateTime(dateTime: endTime.toUtc());
      if (description != null) event.description = description;
      if (location != null) event.location = location;
      if (colorId != null) event.colorId = colorId; // Add the colorId

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

  Widget _buildChatBubble(String message, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue[300] : Colors.grey[300],
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: isUser ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
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

  List<Map<String, DateTime>> calculateFreePeriods(
      List<Map<String, dynamic>> busyPeriods, DateTime start, DateTime end) {
    busyPeriods.sort((a, b) =>
        DateTime.parse(a['start']!).compareTo(DateTime.parse(b['start']!)));

    List<Map<String, DateTime>> freePeriods = [];
    DateTime currentStart = start;

    for (final period in busyPeriods) {
      DateTime busyStart = DateTime.parse(period['start']);
      DateTime busyEnd = DateTime.parse(period['end']);

      if (currentStart.isBefore(busyStart)) {
        freePeriods.add({
          'start': currentStart,
          'end': busyStart,
        });
      }

      currentStart = busyEnd.isAfter(currentStart) ? busyEnd : currentStart;
    }

    if (currentStart.isBefore(end)) {
      freePeriods.add({
        'start': currentStart,
        'end': end,
      });
    }

    return freePeriods;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(child: Text('AI Calendar Assistant')),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController, // Attach the scroll controller
              itemCount: chatMessages.length,
              itemBuilder: (context, index) {
                final message = chatMessages[index];
                final isUser = message['role'] == 'user';
                return _buildChatBubble(message['content'] ?? '', isUser);
              },
            ),
          ),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              boxShadow: [BoxShadow(blurRadius: 2, color: Colors.black26)],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: queryController,
                        decoration: InputDecoration(
                          hintText: "Type a message...",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 20,
                          ),
                        ),
                        onSubmitted: (value) {
                          if (value.isNotEmpty) {
                            handleUserQuery(value);
                            queryController.clear();
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send, color: Colors.blue),
                      onPressed: () {
                        final text = queryController.text.trim();
                        if (text.isNotEmpty) {
                          handleUserQuery(text);
                          queryController.clear();
                        }
                      },
                    ),
                  ],
                ),
                SizedBox(height: 10),
                GestureDetector(
                  onTap: _toggleListening,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulsating animation
                      AnimatedOpacity(
                        opacity: _isListening ? 1.0 : 0.0,
                        duration: Duration(seconds: 1),
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withOpacity(0.3),
                          ),
                        ),
                      ),
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening ? Colors.red : Colors.grey,
                        ),
                        child: Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: 90,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

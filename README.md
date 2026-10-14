# AI Calendar Assistant

A personal assistant with a real voice and a real calendar. You talk to it the way you would talk to ChatGPT. It answers by reading and changing your Google Calendar.

I built the whole thing myself: the Flutter app, the model loop, the Calendar integration, and the hands-free voice path. It is the project I use every day, not a demo that stops at a chat bubble.

A current ChatGPT model can plug into a calendar and do most of this. When I started, that did not exist. There was no MCP, and there was no practical agentic model. Siri and Google Assistant could set a timer or drop one event on a calendar. They could not look at a real week, find a free slot, and then change the calendar in the same conversation.

The first version asked the model for one structured command and parsed that into a single calendar action. As the models got better, I rebuilt it. The app now gives Gemini a set of calendar tools and lets it call them in a loop: look, decide, write, read the result back, and continue until the request is done. That tool loop is the idea MCP later made standard. This project stayed current by replacing the old command parser with that agent.

```mermaid
flowchart LR
    subgraph first [First version]
        U1[User] --> M1[Model]
        M1 --> P1[One parsed command]
        P1 --> A1[One calendar action]
    end
    subgraph current [Current version]
        U2[User] --> M2[Gemini]
        M2 --> T2[Calendar tools]
        T2 --> M2
        M2 --> R2[Verified result]
        R2 --> U2
    end
```

[Five-minute demo](https://www.youtube.com/watch?v=GhVEaJZW7uU)

<a href="https://www.youtube.com/watch?v=GhVEaJZW7uU" target="_blank">
    <img src="https://img.youtube.com/vi/GhVEaJZW7uU/0.jpg" alt="AI Calendar Assistant demo on YouTube" width="320"/>
</a>

## What you can ask

- "What's my week looking like?"
- "Find a 2-hour free slot next week for lunch at noon."
- "Push my next meeting by an hour."
- "Add a green course block every Sunday in June, 12:30 to 3:30."

It can list, create, move, and delete events. If a time overlaps something already on the calendar, it says so and asks how to resolve it instead of silently double-booking you.

## Why it is more than a chatbot

Most calendar bots generate a polite sentence. This one has to be right, because the sentence is followed by a write to a live calendar.

1. You speak or type.
2. Gemini decides which calendar tool to call.
3. The app runs that tool against Google Calendar.
4. It reads the event back and checks that the change actually landed.
5. It speaks the result, then listens for the next request.

```mermaid
sequenceDiagram
    participant User
    participant App
    participant Gemini
    participant Calendar
    User->>App: Speak or type
    App->>Gemini: Request and tool list
    Gemini->>Calendar: listEvents or addEvent
    Calendar-->>Gemini: Tool result
    Gemini->>Calendar: Next tool if the request is not done
    Calendar-->>Gemini: Tool result
    Gemini-->>App: Final answer after the write is checked
    App->>User: Spoken reply, then listen again
```

A free-time question is answered from real open slots, not from a guess. A color like "green" is mapped to a real Calendar color. After a create, update, or delete, the app does not tell you it worked until the calendar agrees.

## What I built

| Piece | What it does |
| --- | --- |
| Flutter app | WhatsApp-style chat, voice button, interrupt, model picker |
| Gemini tool loop | `listEvents`, `addEvent`, `updateEvent`, `deleteEvent`, `getFreeBusy`, `findFreeSlots`, `getEventColors` |
| Google Calendar API | Service-account access across the calendars I use, including recurring events |
| Voice | On-device speech-to-text, device or cloud text-to-speech, English speech when the reply is not English |

```mermaid
flowchart TB
    Voice[Voice] --> STT[Speech to text]
    Typed[Typed text] --> App[Flutter app]
    STT --> App
    App --> Gemini[Gemini tool loop]
    Gemini --> Tools[Calendar tools]
    Tools --> API[Google Calendar API]
    API --> Tools
    Tools --> Gemini
    Gemini --> Check[Read the event back]
    Check --> TTS[Text to speech]
    TTS --> Voice
```

The loop is bounded. Every tool result is checked. If a call fails, the assistant retries when the error is recoverable, then tells you the real blocker instead of inventing a success.

## On the phone

- Hands-free: listen, act, speak, listen again.
- Interrupt while it is thinking or talking.
- Switch the Gemini model or the speech engine without restarting.
- In a debug build, each reply can show the prompt, the tool calls, and the trace. That is how I catch a bad calendar write before I trust it.

## Where it can go

The same shape is a booking agent: a person talks, the assistant checks a real calendar, and the appointment only exists after the API says it does. I built it for my own schedule first, because that is the only way to find out whether the agent is actually reliable.

## Notes

This is a personal project. Calendar access, Firebase, and speech keys stay private, so the repo is not a clone-and-run app. Behavior is covered by unit and widget tests that use fake calendar and model services. The live calendar suite is opt-in and only writes tagged events in January 2027. See [TESTING.md](TESTING.md).

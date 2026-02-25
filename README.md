# MIND — Voice-First AI Productivity Companion

A British AI productivity companion that speaks like a human, not a bot.

## What is MIND?

MIND is a next-generation voice-first AI productivity assistant built with Flutter. Unlike traditional task managers, MIND uses advanced natural language processing and human-like speech synthesis to create an intimate, conversational productivity experience.

### Why MIND is Different

- Human-Like Voice Engine: Research-calibrated speech synthesis with F0 declination, jitter/shimmer, and breath-group prosody
- Context-Aware AI: Understands your patterns, adapts to your energy levels, and knows when to push or support
- Emotional Intelligence: 13 emotion tags (quietly, firmly, warmly, drily, etc.) for nuanced communication
- Earphone-First Design: Intimate nudges delivered privately through earphones, never intrusive speaker announcements
- Privacy-First: AES-256 encryption, local-first storage, your data never leaves your device
- Digital Wellbeing: Tracks screen time, app usage, and focus patterns to provide intelligent insights

## Features

### Voice Pattern System
- 40+ Voice Patterns: From morning orientation to late-night wrap, each with unique prosody
- Adaptive Tone: Adjusts proximity, urgency, warmth, challenge, and brevity based on context
- Silence Intelligence: Knows when to speak, when to pause, and when to stay silent

### Advanced Speech Engine
- ElevenLabs-Grade TTS: Implements 2026 technique parity with commercial voice AI
- SSML Prosody: iOS AVSpeechUtterance with per-utterance timing control
- Syntagm Splitting: Text-structure-driven prosody for natural phrasing
- Speech Normalization: Handles numbers, symbols, abbreviations, and markdown

### Memory Architecture
- Episodic Memory: Remembers conversations, promises, and patterns
- Semantic Memory: Builds knowledge about your tasks and priorities
- Procedural Memory: Learns your workflows and preferences
- Encrypted Storage: SQLite with AES-256-CBC encryption

### Intelligent Nudging
- Background Service: Runs as foreground service for persistent awareness
- Earphone Detection: Real-time wired/Bluetooth earphone state monitoring
- Context-Aware Timing: Nudges based on task idle time, deferrals, and promises
- Escalation Patterns: From gentle reminders to direct challenges

### Digital Wellbeing Integration
- Screen Time Tracking: Android UsageStatsManager integration
- Focus Block Detection: Identifies and encourages deep work sessions
- Fragmentation Analysis: Detects scattered attention patterns
- Social Media Awareness: Gentle observations about time allocation

## Demo

> **Note**: Add screenshots or video demo here

```dart
// Example: MIND adapting to user state
Pattern: THIRD_DEFERRAL
Tone: challenge=0.7, brevity=0.6, silenceIntent=0.7
Output: "We keep circling this task. What is actually in the way?"
[3500ms silence — waits for real answer]
```

## Installation

### Prerequisites
- Flutter 3.0+
- Dart 3.0+
- iOS 12+ or Android 6.0+
- OpenAI API key

### Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/mind-voice-ai.git
cd mind-voice-ai

# Install dependencies
flutter pub get

# Run on your device
flutter run
```

### Configuration

1. API Keys: Add your OpenAI API key in the app settings
2. Permissions: Grant microphone, notification, and usage access permissions
3. Earphones: Connect earphones for the full experience

## Architecture

### Core Components

```
lib/
├── main.dart                 # Entry point + complete implementation
├── voice_engine/            # Speech synthesis system
│   ├── f0_contour_model     # Pitch declination & reset
│   ├── duration_model       # Rate variation & lengthening
│   ├── syntagm_splitter     # Phrase-level prosody
│   └── emotion_tags         # Emotional coloring
├── memory/                  # Encrypted memory layers
│   ├── episodic             # Conversation history
│   ├── semantic             # Task knowledge
│   └── procedural           # Workflow patterns
├── patterns/                # Voice pattern library
│   ├── pattern_selector     # Context-based pattern matching
│   └── pattern_profiles     # 40+ predefined patterns
└── wellbeing/              # Digital wellbeing tracking
    ├── screen_time          # Usage monitoring
    └── focus_detection      # Deep work identification
```

### Voice Engine Pipeline

```
User Input → AI Response → Emotion Tag Parser → Syntagm Splitter 
→ F0 Contour Model → Duration Model → SSML Generation → TTS Output
```

### Key Technologies

- Flutter TTS: Cross-platform text-to-speech
- Speech-to-Text: Real-time voice recognition
- SQLite + Encrypt: Secure local database
- Flutter Foreground Task: Background service management
- Audio Session: Earphone detection and audio routing
- App Usage: Digital wellbeing metrics

## Voice Pattern Examples

### Morning Orientation
```
Dimensions: proximity=0.4, warmth=0.7, pace=0.45
Output: "Morning. What is the one thing today?"
```

### Third Deferral (Challenge)
```
Dimensions: challenge=0.7, certainty=0.8, silenceIntent=0.7
Output: "Three deferrals. What is the real blocker?"
[3500ms pause]
```

### Task Complete
```
Dimensions: warmth=0.6, brevity=0.9, silenceIntent=0.85
Output: "Brilliant. Done."
[2800ms pause]
```

## Privacy & Security

- Local-First: All data stored on device
- AES-256 Encryption: Military-grade encryption for all stored data
- Secure Enclave: iOS Keychain / Android Keystore for key management
- No Tracking: No analytics, no telemetry, no third-party SDKs
- API Privacy: Only sends conversation context to OpenAI, never raw usage data

## Development

### Running Tests
```bash
flutter test
```

### Building for Production
```bash
# iOS
flutter build ios --release

# Android
flutter build apk --release
```

### Code Structure
- Single-file architecture: Entire app in `lib/main.dart` for maximum cohesion
- Research-driven: Voice engine based on acoustic phonetics research
- Pattern-based: Declarative voice patterns, not imperative logic

## Contributing

We welcome contributions! Here's how you can help:

1. Voice Patterns: Add new contextual patterns
2. Language Support: Extend beyond British English
3. Platform Features: iOS/Android-specific enhancements
4. Documentation: Improve guides and examples

### Contribution Guidelines

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## Research & Inspiration

MIND's voice engine is built on research from:

- Liberman (1967): Breath-group theory
- Ladd (1988): F0 declination models
- Cho & Keating (2009): Boundary-initial strengthening
- Turk & Shattuck-Hufnagel (2007): Prefinal lengthening
- ElevenLabs (2024-2026): Commercial voice AI techniques

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Flutter team for the framework
- OpenAI for GPT models
- The acoustic phonetics research community

## Contact & Support

- Issues: [GitHub Issues](https://github.com/yourusername/mind-voice-ai/issues)
- Discussions: [GitHub Discussions](https://github.com/yourusername/mind-voice-ai/discussions)


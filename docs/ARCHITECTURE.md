# 🏗️ MIND Architecture Documentation

## Overview

MIND is built as a single-file Flutter application (`lib/main.dart`) with a highly cohesive architecture. This document explains the core systems and their interactions.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User Interface                        │
│  (Flutter Material Design + Custom Voice-First Components)  │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────┴────────────────────────────────────────┐
│                    Application Layer                         │
│  • State Management (StatefulWidget + setState)              │
│  • Session Management                                        │
│  • Permission Handling                                       │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
┌───────▼──────┐ ┌──▼──────┐ ┌──▼────────────┐
│ Voice Engine │ │ AI Core │ │ Memory System │
└───────┬──────┘ └──┬──────┘ └──┬────────────┘
        │           │            │
┌───────▼───────────▼────────────▼────────────┐
│         Platform Services Layer              │
│  • Flutter TTS                               │
│  • Speech-to-Text                            │
│  • SQLite + Encryption                       │
│  • Foreground Service                        │
│  • Audio Session                             │
│  • App Usage Stats                           │
└──────────────────────────────────────────────┘
```

## Core Systems

### 1. Voice Pattern System

The voice pattern system is the heart of MIND's personality. It determines HOW the AI speaks based on context.

#### Components

**VoiceDimensions**
```dart
class VoiceDimensions {
  final double proximity;    // 0.0 = distant, 1.0 = intimate
  final double urgency;      // 0.0 = relaxed, 1.0 = urgent
  final double warmth;       // 0.0 = cold, 1.0 = warm
  final double challenge;    // 0.0 = supportive, 1.0 = confrontational
  final double brevity;      // 0.0 = verbose, 1.0 = terse
  final double certainty;    // 0.0 = uncertain, 1.0 = certain
  final double pace;         // 0.0 = slow, 1.0 = fast
  final double weight;       // 0.0 = light, 1.0 = heavy
  final double silenceIntent;// 0.0 = fill silence, 1.0 = hold silence
  final double irony;        // 0.0 = literal, 1.0 = ironic
}
```

**VoicePattern Enum**
40+ patterns covering:
- Session states (freshOpen, returnWithTask, morningOrient)
- Task states (taskIdle2h, overdueTask, taskComplete)
- User states (userOverwhelmed, userEnergised, userFatigued)
- Interaction patterns (excuseFirst through excuseFourth)
- Silence patterns (silenceThinking, silencePresent, silenceGone)

**PatternSelector**
Decision tree that maps context to pattern:
```dart
static VoicePattern select(PatternSelectorInput ctx) {
  // Priority order:
  // 1. Silence states
  // 2. Task completion
  // 3. Earphone-specific patterns
  // 4. Promise tracking
  // 5. Excuse escalation
  // 6. Task urgency
  // 7. User emotional state
  // 8. Time-of-day patterns
  // 9. Digital wellbeing patterns
  // 10. Default session patterns
}
```

### 2. Human Speech Engine

Research-calibrated speech synthesis that sounds human, not robotic.

#### The Three Laws of Human Speech

**Law 1: Stochastic Variation**
- Jitter: Period-to-period F0 variation (0.5-2.0%)
- Shimmer: Amplitude variation (0.1-0.4 dB)
- Implementation: Gaussian noise on every TTS parameter

**Law 2: F0 Declination with Reset**
- Pitch falls 10-20 Hz over utterance
- Resets at phrase boundaries
- Final fall at utterance end

**Law 3: Rate-Pitch Covariation**
- Speed up → pitch rises
- Slow down → pitch falls
- Physiologically coupled

#### Components

**F0ContourModel**
```dart
class F0ContourModel {
  // Utterance-level pitch arc
  void beginUtterance({
    required int totalPhrases,
    required EmotionTag emotion,
    required bool isQuestion,
    required double urgency,
  });
  
  // Phrase-level pitch delta
  double nextPhrasePitchDelta();
  
  // Word-level micro-intonation
  double wordPitchDelta(String word, int wordIndex, int phraseLength);
}
```

**DurationModel**
```dart
class DurationModel {
  // Word-level rate variation
  double wordRateScale({
    required String word,
    required int wordIndex,
    required int phraseLength,
    required double urgency,
    required double emotionRateDelta,
  });
  
  // Pre-word hesitation pauses
  int preWordPause({
    required String word,
    required int wordIndex,
    required bool isPhraseFinal,
    required double urgency,
  });
}
```

**SyntagmSplitter**
```dart
class SyntagmSplitter {
  // Splits text into prosodic phrases
  static List<Syntagm> split(
    String text,
    VoiceDimensions dims,
    EmotionTag emotionTag,
    bool isEarphone,
  );
}
```

**EmotionTagParser**
```dart
class EmotionTagParser {
  // Extracts [emotion] tags from AI response
  static (String, EmotionTag) parse(String text);
  
  // Infers emotion from voice pattern
  static EmotionTag inferFromPattern(VoicePattern p);
}
```

### 3. Memory System

Three-layer memory architecture inspired by cognitive science.

#### Episodic Memory
- Stores conversation history
- Tracks promises and commitments
- Records task interactions
- Enables pattern recognition

```dart
class EpisodicMemory {
  Future<void> recordInteraction({
    required String userInput,
    required String aiResponse,
    required String taskContext,
    required DateTime timestamp,
  });
  
  Future<List<Interaction>> getRecentHistory(int limit);
  Future<List<Promise>> getActivePromises();
}
```

#### Semantic Memory
- Task knowledge base
- User preferences
- Domain concepts
- Relationship mapping

```dart
class SemanticMemory {
  Future<void> updateTaskKnowledge(Task task);
  Future<Map<String, dynamic>> getUserPreferences();
  Future<List<Task>> getRelatedTasks(String taskId);
}
```

#### Procedural Memory
- Workflow patterns
- Habit tracking
- Success patterns
- Failure patterns

```dart
class ProceduralMemory {
  Future<void> recordWorkflow(Workflow workflow);
  Future<List<Pattern>> getSuccessPatterns();
  Future<void> updateHabitStreak(String habitId);
}
```

#### Encryption
All memory layers use AES-256-CBC encryption:
```dart
class MemoryEncryption {
  final enc.Encrypter _encrypter;
  final enc.IV _iv;
  
  String encrypt(String plaintext);
  String decrypt(String ciphertext);
}
```

### 4. AI Integration

OpenAI GPT integration with context injection.

#### System Prompt Construction
```dart
String buildSystemPrompt({
  required VoicePattern pattern,
  required List<Task> tasks,
  required UserState userState,
  required List<Interaction> recentHistory,
}) {
  return '''
You are MIND — a British AI productivity companion.

${PatternSelector.buildPatternInjection(pattern)}

CURRENT CONTEXT:
${_buildTaskContext(tasks)}
${_buildUserStateContext(userState)}
${_buildHistoryContext(recentHistory)}

VOICE RULES:
- British English only
- Natural, conversational tone
- Use [emotion] tags when appropriate
- Follow pattern dimensions strictly
- Never explain yourself
- Never apologize
- Never use American spellings
''';
}
```

#### Response Processing
```dart
Future<String> processAIResponse(String rawResponse) async {
  // 1. Parse emotion tags
  final (cleanText, emotionTag) = EmotionTagParser.parse(rawResponse);
  
  // 2. Normalize speech
  final normalized = SpeechNormaliser.normalise(cleanText);
  
  // 3. Split into syntagms
  final syntagms = SyntagmSplitter.split(
    normalized,
    currentDimensions,
    emotionTag,
    isEarphoneConnected,
  );
  
  // 4. Generate speech
  await speakSyntagms(syntagms);
  
  return cleanText;
}
```

### 5. Background Service

Persistent awareness through foreground service.

#### Service Architecture
```dart
class MindBackgroundHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    // Initialize background context
    await _initializeMemory();
    await _loadTasks();
    await _startEarphoneMonitoring();
  }
  
  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    // Periodic checks (every 15 minutes)
    await _checkTaskIdleTime();
    await _checkPromises();
    await _checkEarphoneState();
    
    if (_shouldNudge()) {
      await _deliverNudge();
    }
  }
}
```

#### Earphone Detection
```dart
class EarphoneMonitor {
  Stream<bool> get earphoneStateStream;
  
  Future<void> startMonitoring() async {
    final session = await AudioSession.instance;
    session.configurationStream.listen((config) {
      final isConnected = config.outputDevices.any(
        (device) => device.type == AudioDeviceType.headphones ||
                    device.type == AudioDeviceType.bluetooth,
      );
      _earphoneStateController.add(isConnected);
    });
  }
}
```

### 6. Digital Wellbeing

Screen time and app usage tracking.

#### Usage Tracking
```dart
class WellbeingTracker {
  Future<UsageStats> getTodayStats() async {
    final endDate = DateTime.now();
    final startDate = DateTime(endDate.year, endDate.month, endDate.day);
    
    final usageStats = await AppUsage().getAppUsage(startDate, endDate);
    
    return UsageStats(
      totalScreenTime: _calculateTotal(usageStats),
      unlockCount: await _getUnlockCount(),
      socialMediaTime: _calculateSocialTime(usageStats),
      longestFocusBlock: _findLongestFocus(usageStats),
      fragmentationScore: _calculateFragmentation(usageStats),
    );
  }
}
```

#### Pattern Detection
```dart
class PatternDetector {
  bool isCleanDay(UsageStats stats) =>
      stats.totalScreenTime < Duration(minutes: 60);
  
  bool isHeavyScreenDay(UsageStats stats) =>
      stats.totalScreenTime > Duration(minutes: 240);
  
  bool isFragmentedDay(UsageStats stats) =>
      stats.unlockCount > 60;
  
  bool hasNoFocusBlock(UsageStats stats) =>
      stats.longestFocusBlock < Duration(minutes: 20);
}
```

## Data Flow

### Voice Interaction Flow
```
User Speech
    ↓
Speech-to-Text
    ↓
Text Input
    ↓
Context Builder (Memory + Tasks + User State)
    ↓
Pattern Selector
    ↓
System Prompt Construction
    ↓
OpenAI API Call
    ↓
Response Processing
    ↓
Emotion Tag Parsing
    ↓
Speech Normalization
    ↓
Syntagm Splitting
    ↓
F0 Contour Generation
    ↓
Duration Modeling
    ↓
TTS Synthesis
    ↓
Audio Output
    ↓
Memory Recording
```

### Background Nudge Flow
```
Timer Trigger (15 min)
    ↓
Load Current Context
    ↓
Check Earphone State
    ↓
Calculate Task Idle Time
    ↓
Check Promise Status
    ↓
Evaluate Nudge Conditions
    ↓
Select Nudge Pattern
    ↓
Generate Nudge Text
    ↓
Deliver via TTS (if earphones connected)
    ↓
Record Nudge Event
    ↓
Update Nudge Streak
```

## Performance Considerations

### Memory Management
- Lazy loading of conversation history
- Periodic memory consolidation
- Automatic cleanup of old data
- Efficient SQLite queries with indexes

### Speech Synthesis
- Syntagm-level caching
- Async TTS queue
- Preloading common phrases
- Optimized SSML generation

### Background Service
- Minimal wake locks
- Efficient timer intervals
- Battery-aware scheduling
- Graceful degradation on low battery

## Security

### Encryption
- AES-256-CBC for all stored data
- Secure Enclave (iOS) / Keystore (Android) for keys
- No plaintext storage
- Encrypted database backups

### Privacy
- Local-first architecture
- No telemetry or analytics
- Optional cloud sync (future)
- User-controlled data export/deletion

### API Security
- API keys stored in secure storage
- HTTPS-only communication
- Request rate limiting
- Error message sanitization

## Testing Strategy

### Unit Tests
- Voice pattern selection logic
- Emotion tag parsing
- Speech normalization
- Memory encryption/decryption

### Integration Tests
- End-to-end voice interaction
- Background service behavior
- Memory system operations
- TTS output verification

### Manual Testing
- Real device testing (iOS + Android)
- Earphone detection accuracy
- Background service reliability
- Voice quality assessment

## Future Architecture

### Planned Enhancements
- Multi-language support
- Cloud sync with E2E encryption
- Wearable integration
- Desktop applications
- Team/family sharing
- Plugin system for extensions

### Scalability
- Modular architecture for feature additions
- Plugin-based voice pattern system
- Extensible memory layers
- Configurable AI providers

---

For implementation details, see the source code in `lib/main.dart`.

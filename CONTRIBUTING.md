# Contributing to MIND

Thank you for your interest in contributing to MIND! This document provides guidelines and instructions for contributing.

## 🎯 Ways to Contribute

### 1. Voice Patterns
Add new contextual voice patterns to the pattern library:
- Identify missing user states or contexts
- Define appropriate voice dimensions (proximity, urgency, warmth, etc.)
- Write natural British English templates
- Test with real usage scenarios

### 2. Speech Engine Improvements
Enhance the human-like speech synthesis:
- Improve F0 contour modeling
- Add language-specific phonetic rules
- Optimize prosody for different emotions
- Reduce latency in speech generation

### 3. Memory System
Improve the AI's memory and learning:
- Enhance episodic memory consolidation
- Add new semantic memory patterns
- Improve procedural learning algorithms
- Optimize database queries

### 4. Platform Features
Add platform-specific enhancements:
- iOS-specific features (Siri integration, widgets)
- Android-specific features (quick tiles, better background service)
- Wearable support (Apple Watch, Wear OS)
- Desktop support (macOS, Windows, Linux)

### 5. Documentation
Improve guides and examples:
- Add tutorials and how-to guides
- Create video demonstrations
- Write technical deep-dives
- Translate documentation

## 🚀 Getting Started

### Prerequisites
- Flutter 3.0+
- Dart 3.0+
- Git
- A code editor (VS Code, Android Studio, IntelliJ)

### Setup Development Environment

```bash
# Fork and clone the repository
git clone https://github.com/yourusername/mind-voice-ai.git
cd mind-voice-ai

# Install dependencies
flutter pub get

# Run tests
flutter test

# Run the app
flutter run
```

## 📝 Code Style

### Dart Style Guide
- Follow the [official Dart style guide](https://dart.dev/guides/language/effective-dart/style)
- Use `dart format` before committing
- Run `flutter analyze` to check for issues

### Voice Pattern Guidelines
```dart
// Good: Clear, concise, British English
'Right then — good to have you back.'

// Avoid: Verbose, American English, robotic
'Hello! It is great to see you again today!'
```

### Commit Messages
Use conventional commits format:
```
feat: add late-night wrap voice pattern
fix: correct F0 declination calculation
docs: update installation instructions
refactor: simplify syntagm splitter logic
test: add tests for emotion tag parser
```

## 🔍 Pull Request Process

1. **Create a Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make Changes**
   - Write clean, documented code
   - Add tests for new features
   - Update documentation as needed

3. **Test Thoroughly**
   ```bash
   flutter test
   flutter analyze
   dart format .
   ```

4. **Commit Changes**
   ```bash
   git add .
   git commit -m "feat: add your feature"
   ```

5. **Push to Your Fork**
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Open Pull Request**
   - Provide clear description of changes
   - Reference any related issues
   - Include screenshots/videos if applicable
   - Wait for review and address feedback

## 🧪 Testing Guidelines

### Unit Tests
```dart
test('emotion tag parser extracts tags correctly', () {
  final (text, tag) = EmotionTagParser.parse('[quietly] Hello there');
  expect(text, 'Hello there');
  expect(tag, EmotionTag.quietly);
});
```

### Integration Tests
- Test voice pattern selection logic
- Verify speech engine output
- Check memory system operations
- Validate encryption/decryption

### Manual Testing
- Test on real devices (iOS and Android)
- Verify earphone detection
- Check background service behavior
- Test with various user scenarios

## 🐛 Bug Reports

When reporting bugs, include:

1. **Description**: Clear description of the issue
2. **Steps to Reproduce**: Exact steps to trigger the bug
3. **Expected Behavior**: What should happen
4. **Actual Behavior**: What actually happens
5. **Environment**:
   - Flutter version
   - Dart version
   - Device/OS version
   - App version
6. **Logs**: Relevant error messages or stack traces
7. **Screenshots**: If applicable

## 💡 Feature Requests

When requesting features, include:

1. **Use Case**: Why is this feature needed?
2. **Proposed Solution**: How should it work?
3. **Alternatives**: Other approaches considered
4. **Additional Context**: Screenshots, mockups, examples

## 🎨 Voice Pattern Contribution Template

```dart
VoicePattern.yourNewPattern: const PatternProfile(
  dimensions: VoiceDimensions(
    proximity: 0.5,    // 0.0 = distant, 1.0 = intimate
    urgency: 0.5,      // 0.0 = relaxed, 1.0 = urgent
    warmth: 0.5,       // 0.0 = cold, 1.0 = warm
    challenge: 0.0,    // 0.0 = supportive, 1.0 = confrontational
    brevity: 0.5,      // 0.0 = verbose, 1.0 = terse
    certainty: 0.5,    // 0.0 = uncertain, 1.0 = certain
    pace: 0.5,         // 0.0 = slow, 1.0 = fast
    weight: 0.5,       // 0.0 = light, 1.0 = heavy
    silenceIntent: 0.3,// 0.0 = fill silence, 1.0 = hold silence
    irony: 0.0,        // 0.0 = literal, 1.0 = ironic
  ),
  templates: [
    'Your template here.',
    'Alternative template.',
  ],
  systemPromptHint: 'CONTEXT. Instructions for AI. Tone guidance.',
),
```

## 📚 Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [Flutter TTS Package](https://pub.dev/packages/flutter_tts)
- [Speech to Text Package](https://pub.dev/packages/speech_to_text)

## 🤝 Code of Conduct

### Our Pledge
We are committed to providing a welcoming and inclusive environment for all contributors.

### Our Standards
- Be respectful and considerate
- Welcome diverse perspectives
- Accept constructive criticism gracefully
- Focus on what's best for the community
- Show empathy towards others

### Unacceptable Behavior
- Harassment or discrimination
- Trolling or insulting comments
- Personal or political attacks
- Publishing others' private information
- Other unprofessional conduct

## 📞 Questions?

- Open a [GitHub Discussion](https://github.com/yourusername/mind-voice-ai/discussions)
- Check existing [Issues](https://github.com/yourusername/mind-voice-ai/issues)
- Email: your.email@example.com

---

Thank you for contributing to MIND! 🎉

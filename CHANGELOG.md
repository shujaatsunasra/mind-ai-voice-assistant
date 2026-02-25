# Changelog

All notable changes to MIND will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.0.0] - 2026-02-25

### Added
- 🎙️ ElevenLabs-grade voice synthesis with research-calibrated prosody
- 🎭 12 emotion tags (quietly, firmly, warmly, drily, urgently, heavily, brightly, sighs, pauses, settles, breathes, murmurs)
- 🧠 40+ voice patterns for contextual responses
- 🎧 Earphone-native nudge system with idle task detection (2h, 6h thresholds)
- 🔒 AES-256 encryption for all local data
- 📊 Digital wellbeing integration (screen time, focus blocks, social media tracking)
- 🗣️ Advanced speech features:
  - F0 declination with phrase boundary resets
  - Stochastic jitter and shimmer
  - Rate-pitch covariation
  - Prefinal lengthening
  - Syntagm-based prosody
- 💾 Three-layer memory system (episodic, semantic, procedural)
- 🎯 Promise tracking and accountability system
- 🌅 Time-aware patterns (morning orient, late night wrap)
- 📱 Background foreground service for always-on availability
- 🔐 Secure Enclave / Android Keystore integration
- 🎨 Dark mode UI with British aesthetic

### Technical
- Flutter 3.0+ with Dart 3.0+
- SQLite database for memory storage
- Audio session management for earphone detection
- Permission handling for microphone and speech recognition
- SSML support for iOS speech synthesis

### Security
- Local-first architecture (no cloud sync)
- Military-grade encryption at rest
- Zero tracking or telemetry
- Privacy-first design

## [Unreleased]

### Planned
- [ ] Multi-language support
- [ ] Custom voice training
- [ ] Calendar integration
- [ ] Habit tracking
- [ ] Team collaboration features
- [ ] Apple Watch companion app
- [ ] Widget support
- [ ] Siri shortcuts integration

---

## Version History

- **5.0.0** - Initial public release with complete voice engine
- **4.x.x** - Internal beta testing
- **3.x.x** - Voice pattern development
- **2.x.x** - Core task management
- **1.x.x** - Proof of concept

---

For more details, see the [commit history](https://github.com/yourusername/mind-ai-voice-assistant/commits/main).

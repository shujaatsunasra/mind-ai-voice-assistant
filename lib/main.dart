// ╔══════════════════════════════════════════════════════════════════════╗
// ║  MIND v10 — COMPLETE MAIN.DART                                      ║
// ║  Voice Engine: ElevenLabs 2026 Technique Parity                     ║
// ║  • SSML prosody on iOS (AVSpeechUtterance ssmlRepresentation)        ║
// ║  • Per-utterance preDelay/postDelay (real breath groups)            ║
// ║  • EmotionTag system (mirrors ElevenLabs v3 audio tags)             ║
// ║  • SyntagmSplitter (text-structure-driven prosody)                  ║
// ║  • VarianceController (stability slider equivalent)                 ║
// ║  • SpeechNormaliser (numbers, symbols, abbreviations)               ║
// ║  • Contextual carry-over rhythm across chunks                       ║
// ║  • AI injects [emotion] tags — parsed, stripped, applied            ║
// ╚══════════════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:audio_session/audio_session.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:permission_handler/permission_handler.dart';
import 'package:app_usage/app_usage.dart';

// ─── ENTRY ───────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  FlutterForegroundTask.initCommunicationPort();
  runApp(const MindApp());
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MindBackgroundHandler());
}

// ─── CONSTANTS ───────────────────────────────────────────────
const _kEncKeyAlias = 'mind_enc_key_v1';
const _kConsolidationPending = 'mind_consolidation_pending';
const _kProviderKeysPref = 'mind_provider_keys_v1';

// ─── PALETTE ─────────────────────────────────────────────────
const _c0 = Color(0xFF000000);
const _c1 = Color(0xFF1C1C1E);
const _c2 = Color(0xFF2C2C2E);
const _c3 = Color(0xFF3A3A3C);
const _cAccent = Color(0xFF0A84FF);
const _cGreen = Color(0xFF30D158);
const _cRed = Color(0xFFFF453A);
const _cOrange = Color(0xFFFF9F0A);
const _cPurple = Color(0xFFBF5AF2);
const _cText = Color(0xFFF5F5F7);
const _cMuted = Color(0xFF8E8E93);

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION A — VOICE PATTERN SYSTEM
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class VoiceDimensions {
  final double proximity;
  final double urgency;
  final double warmth;
  final double challenge;
  final double brevity;
  final double certainty;
  final double pace;
  final double weight;
  final double silenceIntent;
  final double irony;

  const VoiceDimensions({
    this.proximity = 0.5,
    this.urgency = 0.5,
    this.warmth = 0.5,
    this.challenge = 0.0,
    this.brevity = 0.5,
    this.certainty = 0.5,
    this.pace = 0.5,
    this.weight = 0.5,
    this.silenceIntent = 0.3,
    this.irony = 0.0,
  });

  double get ttsRate => 0.36 + pace * 0.14;
  double get ttsPitch => 0.87 + weight * 0.10;
  double get ttsVolume => 1.0 - (proximity * 0.10);

  int get postUtterancePauseMs {
    if (silenceIntent >= 0.9) return 2800;
    if (silenceIntent >= 0.6) return 1500;
    if (silenceIntent >= 0.3) return 800;
    return 350;
  }
}

enum VoicePattern {
  freshOpen,
  returnWithTask,
  morningOrient,
  lateNightWrap,
  sessionMidFocus,
  sessionEndPush,
  longGapReturn,
  firstEverSession,
  taskIdle2h,
  taskIdle6h,
  thirdDeferral,
  overdueTask,
  taskNearDue,
  focusShift,
  taskComplete,
  allTasksClear,
  userOverwhelmed,
  userEnergised,
  userFatigued,
  userFrustrated,
  userDistracted,
  userInFlow,
  userAvoidant,
  userBreakthrough,
  excuseFirst,
  excuseSecond,
  excuseThird,
  excuseFourth,
  promiseMade,
  promiseKept,
  promiseBroken,
  cleanDay,
  heavyScreenDay,
  fragmentedDay,
  noFocusBlock,
  socialHeavy,
  earphoneFirstContact,
  earphoneNudge,
  earphoneIgnored,
  earphoneDayAbandoned,
  earphoneReturn,
  silenceThinking,
  silencePresent,
  silenceDrifted,
  silenceGone,
  silenceAfterWin,
}

class PatternProfile {
  final VoiceDimensions dimensions;
  final List<String> templates;
  final String? systemPromptHint;
  final bool requiresEarphone;
  final bool speakable;
  final int? postSilenceMs;

  const PatternProfile({
    required this.dimensions,
    required this.templates,
    this.systemPromptHint,
    this.requiresEarphone = false,
    this.speakable = true,
    this.postSilenceMs,
  });
}

final Map<VoicePattern, PatternProfile> kPatternLibrary = {
  VoicePattern.freshOpen: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.3,
        warmth: 0.6,
        brevity: 0.5,
        pace: 0.5,
        silenceIntent: 0.3),
    templates: [
      'Right then — good to have you back.',
      'Good. Where are we starting today?',
      'Well — what needs sorting?'
    ],
    systemPromptHint:
        'SESSION_START. Orient crisply. Name most recent task if exists. One sentence. Get moving.',
  ),
  VoicePattern.returnWithTask: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.6,
        urgency: 0.5,
        warmth: 0.5,
        brevity: 0.7,
        certainty: 0.7,
        silenceIntent: 0.4),
    templates: [
      'Mm — you are back. {task} is still there.',
      'Right. {task} has not moved. Shall we?',
      'Still here — {task} has been waiting.'
    ],
    systemPromptHint:
        'USER RETURNED. Name unfinished task in first sentence. Do not ask how they are. Move.',
  ),
  VoicePattern.morningOrient: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.4,
        urgency: 0.3,
        warmth: 0.7,
        pace: 0.45,
        weight: 0.45,
        silenceIntent: 0.3),
    templates: [
      'Morning. What is the one thing today?',
      'Right then — fresh day. What is first?'
    ],
    systemPromptHint:
        'MORNING. Warm, forward. Ask for one priority. Do not list. Do not overwhelm.',
  ),
  VoicePattern.lateNightWrap: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.7,
        urgency: 0.1,
        warmth: 0.8,
        pace: 0.3,
        weight: 0.35,
        brevity: 0.6,
        silenceIntent: 0.5),
    templates: [
      'Late now. One thing to lock in — what is it?',
      'Getting late. One small win before you stop?',
      'Mm. What is worth finishing tonight?'
    ],
    systemPromptHint:
        'LATE NIGHT (9pm+). Warm down. One final thing only. Shorter. Softer. Do not demand.',
  ),
  VoicePattern.sessionMidFocus: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.5,
        warmth: 0.4,
        brevity: 0.6,
        certainty: 0.6,
        pace: 0.5,
        silenceIntent: 0.3),
    templates: [
      'Right. {task} — still moving?',
      'Still on {task}. How close?',
      'Good — keep going.'
    ],
    systemPromptHint:
        'SESSION MID. Hold focus. Short. Directional. No new topics unless raised.',
  ),
  VoicePattern.sessionEndPush: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.6,
        warmth: 0.5,
        brevity: 0.7,
        certainty: 0.7,
        silenceIntent: 0.4),
    templates: [
      'Right — forty-five minutes in. One thing to close?',
      'Before we stop — what is the one thing to lock in?',
      'One more. What closes the session properly?'
    ],
    systemPromptHint:
        'SESSION END (45+ min). Surface a single completion. No new tasks. Close the loop.',
  ),
  VoicePattern.longGapReturn: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.6,
        urgency: 0.4,
        warmth: 0.6,
        pace: 0.42,
        brevity: 0.6,
        certainty: 0.5,
        silenceIntent: 0.4),
    templates: [
      'Been a while. {task} is still there — still relevant?',
      'There you are. {task} has been waiting.',
      'Back after a stretch. Where are we with {task}?'
    ],
    systemPromptHint:
        'LONG GAP (>8h). No judgement. Check task is still relevant before assuming.',
  ),
  VoicePattern.firstEverSession: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.1,
        warmth: 0.8,
        pace: 0.45,
        weight: 0.5,
        silenceIntent: 0.2),
    templates: [
      'Right then — good to have you. What do you need to sort today?',
      'Good. Let us start simply. What is on your mind?'
    ],
    systemPromptHint:
        'FIRST SESSION EVER. Warm. No assumptions. Ask one open question. Do not explain yourself. Just begin.',
  ),
  VoicePattern.taskIdle2h: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.6,
        urgency: 0.5,
        warmth: 0.4,
        brevity: 0.7,
        certainty: 0.6,
        silenceIntent: 0.5),
    templates: [
      '{task} — still there. Two hours now. Ready?',
      'Two hours. {task} is still waiting. Shall we?'
    ],
    systemPromptHint:
        'TASK IDLE 2H. Earphone. Brief. Name the task. Name the time. One question.',
    requiresEarphone: true,
  ),
  VoicePattern.taskIdle6h: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.7,
        urgency: 0.65,
        warmth: 0.35,
        brevity: 0.85,
        certainty: 0.7,
        silenceIntent: 0.6),
    templates: [
      '{task}. Six hours. Still want this?',
      '{task} — half a day gone. What is in the way?'
    ],
    systemPromptHint: 'TASK IDLE 6H. Very brief. The time speaks for itself.',
    requiresEarphone: true,
  ),
  VoicePattern.thirdDeferral: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.55,
        warmth: 0.3,
        challenge: 0.7,
        brevity: 0.6,
        certainty: 0.8,
        silenceIntent: 0.7),
    templates: [
      'We keep circling {task}. What is actually in the way?',
      'Three deferrals. What is the real blocker?',
      '{task} — we have been here before. What is going on?'
    ],
    systemPromptHint:
        'THIRD DEFERRAL. Name the pattern. One sharp question. Wait.',
    postSilenceMs: 3500,
  ),
  VoicePattern.overdueTask: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.75,
        warmth: 0.3,
        challenge: 0.5,
        brevity: 0.6,
        certainty: 0.8,
        silenceIntent: 0.6),
    templates: [
      '{task} was due {days} ago. Still live?',
      'Past due — {task}. Is it still relevant, or shall we retire it?'
    ],
    systemPromptHint:
        'OVERDUE TASK. State the fact. Give binary choice: do it or retire it. No shame.',
  ),
  VoicePattern.taskNearDue: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.7,
        warmth: 0.4,
        brevity: 0.65,
        certainty: 0.7,
        silenceIntent: 0.4),
    templates: [
      '{task} is due today. Where are we?',
      'Today is the day for {task}. Ready?'
    ],
    systemPromptHint: 'DUE TODAY. Brief urgency. One question: how close?',
  ),
  VoicePattern.focusShift: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.3,
        warmth: 0.4,
        challenge: 0.4,
        brevity: 0.6,
        certainty: 0.6,
        silenceIntent: 0.3),
    templates: [
      'Interesting. We will park that. First — {task}.',
      'Good idea. After {task}.'
    ],
    systemPromptHint:
        'DRIFT / FOCUS SHIFT. Acknowledge briefly. Redirect to current task. Do not lecture.',
  ),
  VoicePattern.taskComplete: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.0,
        warmth: 0.6,
        brevity: 0.9,
        certainty: 1.0,
        weight: 0.65,
        silenceIntent: 0.85),
    templates: [
      'Brilliant. Done.',
      'Good. That is sorted.',
      'There we are. Done.'
    ],
    systemPromptHint:
        'TASK COMPLETE. Five words maximum. Confirm done. Ask what is next. Hold silence after.',
    postSilenceMs: 2800,
  ),
  VoicePattern.allTasksClear: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.0,
        warmth: 0.7,
        pace: 0.45,
        weight: 0.55,
        silenceIntent: 0.6),
    templates: [
      'All clear. What do you want to add?',
      'Clean slate. What are we building?'
    ],
    systemPromptHint: 'ALL TASKS DONE. Brief. Ask for new task. Light tone.',
  ),
  VoicePattern.userOverwhelmed: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.6,
        urgency: 0.2,
        warmth: 0.75,
        pace: 0.35,
        weight: 0.38,
        brevity: 0.6,
        silenceIntent: 0.4),
    templates: [
      'Right. Set everything aside. Just this one: {task}. Nothing else.',
      'Stop. Just {task}. That is it.'
    ],
    systemPromptHint:
        'USER OVERWHELMED. Reduce. One task only. Slow down. Warm but firm. Do not add anything.',
  ),
  VoicePattern.userEnergised: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.6,
        warmth: 0.5,
        pace: 0.65,
        weight: 0.58,
        brevity: 0.65,
        silenceIntent: 0.2),
    templates: [
      'Good — that energy is useful. Crack on now.',
      'Right — use it. {task} is right there.'
    ],
    systemPromptHint:
        'USER ENERGISED. Match pace slightly. Channel it. Direct to task immediately.',
  ),
  VoicePattern.userFatigued: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.7,
        urgency: 0.1,
        warmth: 0.8,
        pace: 0.32,
        weight: 0.35,
        brevity: 0.7,
        silenceIntent: 0.5),
    templates: [
      'No rush. One small thing. What would feel like progress?',
      'Take your time. What is the smallest possible move on {task}?'
    ],
    systemPromptHint:
        'USER FATIGUED. Slow down. Reduce stakes. Ask for minimum viable action. Do not demand.',
  ),
  VoicePattern.userFrustrated: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.2,
        warmth: 0.6,
        challenge: 0.2,
        pace: 0.38,
        brevity: 0.7,
        silenceIntent: 0.4),
    templates: [
      'Fair enough. What is the smallest move right now?',
      'Okay. What can actually happen today?'
    ],
    systemPromptHint:
        'USER FRUSTRATED. Validate briefly. Ask for one small forward move.',
  ),
  VoicePattern.userDistracted: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.55,
        urgency: 0.4,
        warmth: 0.4,
        challenge: 0.35,
        brevity: 0.7,
        certainty: 0.6,
        silenceIntent: 0.5),
    templates: [
      'Mm. And here I thought we were close on {task}.',
      'Interesting. Shall we finish {task} first?'
    ],
    systemPromptHint: 'DRIFT DETECTED. Dry observation. One question. Stop.',
    postSilenceMs: 2400,
  ),
  VoicePattern.userInFlow: const PatternProfile(
    dimensions: VoiceDimensions(brevity: 1.0, silenceIntent: 1.0),
    templates: [],
    speakable: false,
    systemPromptHint:
        'USER IN FLOW. Say nothing unless directly asked. Silence is the correct response.',
  ),
  VoicePattern.userAvoidant: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.4,
        warmth: 0.35,
        challenge: 0.6,
        certainty: 0.7,
        brevity: 0.7,
        silenceIntent: 0.7),
    templates: [
      'I hear you — and {task} still needs doing.',
      'Right — and {task} is still there.'
    ],
    systemPromptHint:
        'AVOIDANCE. Accept in two words. Then the task. Contrast does the work.',
    postSilenceMs: 2600,
  ),
  VoicePattern.userBreakthrough: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.0,
        warmth: 0.7,
        brevity: 0.8,
        pace: 0.42,
        weight: 0.6,
        silenceIntent: 0.9),
    templates: [
      'Good. That is the one.',
      'There it is.',
      'Precisely. Now — what is the first move?'
    ],
    systemPromptHint:
        'BREAKTHROUGH. Name it briefly. Hold silence. Do not gush. The moment speaks.',
    postSilenceMs: 3000,
  ),
  VoicePattern.excuseFirst: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.3,
        warmth: 0.5,
        challenge: 0.15,
        brevity: 0.6,
        certainty: 0.5,
        silenceIntent: 0.3),
    templates: [
      'Fair enough. {task} still needs doing, though.',
      'Not to worry. When does {task} happen?'
    ],
    systemPromptHint:
        'FIRST EXCUSE. Accept it. Gently redirect. Ask one small question. Do not challenge yet.',
  ),
  VoicePattern.excuseSecond: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.4,
        warmth: 0.4,
        challenge: 0.4,
        brevity: 0.7,
        certainty: 0.7,
        silenceIntent: 0.5),
    templates: [
      'We have been here before.',
      'That is the second time we have had this conversation.',
      'We have said this already. What changes now?'
    ],
    systemPromptHint:
        'SECOND EXCUSE. Name the pattern. No softening. One observation. One question.',
    postSilenceMs: 2200,
  ),
  VoicePattern.excuseThird: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.5,
        warmth: 0.3,
        challenge: 0.8,
        certainty: 0.85,
        brevity: 0.8,
        silenceIntent: 0.8),
    templates: [
      'What is really going on?',
      'Three times. What is the real reason?'
    ],
    systemPromptHint:
        'THIRD EXCUSE. Ask one direct question. Nothing else. No preamble. Wait for answer.',
    postSilenceMs: 3500,
  ),
  VoicePattern.excuseFourth: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.3,
        urgency: 0.0,
        warmth: 0.2,
        challenge: 0.0,
        certainty: 1.0,
        brevity: 1.0,
        silenceIntent: 1.0),
    templates: ['Right.'],
    systemPromptHint:
        'FOURTH EXCUSE. One word: Right. Then silence. Nothing else. Absence is the message.',
    postSilenceMs: 4000,
  ),
  VoicePattern.promiseMade: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.2,
        warmth: 0.5,
        certainty: 0.7,
        brevity: 0.7,
        silenceIntent: 0.3),
    templates: ['Good. Holding you to that.', 'Noted. I will hold that.'],
    systemPromptHint:
        'PROMISE MADE. Acknowledge briefly. Confirm you have it. Nothing more.',
  ),
  VoicePattern.promiseKept: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.0,
        warmth: 0.6,
        brevity: 0.9,
        weight: 0.6,
        silenceIntent: 0.75),
    templates: [
      'Good — you did it.',
      'You said you would and you did.',
      'Done and done.'
    ],
    systemPromptHint:
        'PROMISE KEPT. Brief. Positive. No over-celebration. Move on fast.',
    postSilenceMs: 2000,
  ),
  VoicePattern.promiseBroken: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.4,
        warmth: 0.3,
        challenge: 0.6,
        certainty: 0.8,
        brevity: 0.7,
        silenceIntent: 0.7),
    templates: [
      'You said you would {promise}. It did not happen. What changed?',
      'We agreed: {promise}. What got in the way?'
    ],
    systemPromptHint:
        'PROMISE BROKEN. State what was promised. State it did not happen. Ask one question.',
    postSilenceMs: 2800,
  ),
  VoicePattern.cleanDay: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.2,
        warmth: 0.6,
        brevity: 0.7,
        weight: 0.55,
        silenceIntent: 0.3),
    templates: [
      'Clean day so far. Let us keep it that way.',
      'You have barely touched the phone today. Good.'
    ],
    systemPromptHint: 'CLEAN DAY. Acknowledge once. Build on the momentum.',
  ),
  VoicePattern.heavyScreenDay: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.4,
        warmth: 0.35,
        challenge: 0.45,
        certainty: 0.6,
        brevity: 0.65,
        silenceIntent: 0.6),
    templates: [
      'Quite a bit of screen time today. {task} has not moved. Ready?',
      'A lot went to the phone today. Where did it go?'
    ],
    systemPromptHint:
        'HEAVY SCREEN DAY. Name the time, not the apps. One redirect. Drop it after.',
    postSilenceMs: 2400,
  ),
  VoicePattern.fragmentedDay: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.35,
        warmth: 0.35,
        challenge: 0.4,
        certainty: 0.65,
        brevity: 0.7,
        silenceIntent: 0.5),
    templates: [
      'You have picked up the phone a lot today. Hard to get any depth.',
      'Very fragmented day. Still want a clear run at {task}?'
    ],
    systemPromptHint:
        'FRAGMENTED DAY. Name the pattern. Ask if they want to change it. Do not lecture.',
  ),
  VoicePattern.noFocusBlock: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.4,
        warmth: 0.45,
        certainty: 0.6,
        brevity: 0.7,
        silenceIntent: 0.4),
    templates: [
      'You have not had a clear run at anything yet today. Shall we fix that?',
      'No focus block today. Want to start one now — twenty minutes on {task}?'
    ],
    systemPromptHint:
        'NO FOCUS BLOCK. Offer one clear focused block. Twenty minutes. Make it achievable.',
  ),
  VoicePattern.socialHeavy: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        urgency: 0.3,
        warmth: 0.4,
        challenge: 0.35,
        certainty: 0.55,
        brevity: 0.7,
        silenceIntent: 0.6),
    templates: [
      'A fair bit went to social today. {task} still needs you.',
      'Quite a bit on social today. Worth naming?'
    ],
    systemPromptHint:
        'SOCIAL HEAVY. Name the time, not the platforms. One gentle observation. Then point to task. Drop it.',
    postSilenceMs: 2600,
  ),
  VoicePattern.earphoneFirstContact: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.9,
        urgency: 0.2,
        warmth: 0.65,
        pace: 0.38,
        weight: 0.42,
        brevity: 0.8,
        silenceIntent: 0.4),
    templates: ['Mm — you are back.', 'Right — let us go.', 'Good. I am here.'],
    systemPromptHint: 'EARPHONE CONNECTED. Very brief. Intimate. Welcome back.',
    requiresEarphone: true,
  ),
  VoicePattern.earphoneNudge: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.9,
        urgency: 0.5,
        warmth: 0.45,
        brevity: 0.9,
        pace: 0.38,
        weight: 0.42,
        silenceIntent: 0.7),
    templates: [
      '{task} — still there. Half an hour. Shall we?',
      'Two hours. {task}. Come back to it?'
    ],
    systemPromptHint:
        'EARPHONE NUDGE. One sentence only. Task. Time. Question. Then silence.',
    requiresEarphone: true,
    postSilenceMs: 3500,
  ),
  VoicePattern.earphoneIgnored: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.7,
        urgency: 0.3,
        warmth: 0.4,
        brevity: 0.9,
        certainty: 0.5,
        silenceIntent: 0.8),
    templates: [
      '{task} is still there. Whenever you are ready.',
      'No rush. {task} will wait.'
    ],
    systemPromptHint:
        'NUDGE IGNORED (streak 1-2). Back off. Shorter. Lower stakes.',
    requiresEarphone: true,
    postSilenceMs: 4000,
  ),
  VoicePattern.earphoneDayAbandoned: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.4,
        urgency: 0.0,
        warmth: 0.4,
        brevity: 1.0,
        certainty: 1.0,
        silenceIntent: 1.0),
    templates: ['Right. I will leave you to it.'],
    systemPromptHint:
        'NUDGE IGNORED 3 TIMES. Final. Silent for the day after this.',
    requiresEarphone: true,
    postSilenceMs: 5000,
  ),
  VoicePattern.earphoneReturn: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.9,
        urgency: 0.4,
        warmth: 0.6,
        brevity: 0.8,
        pace: 0.4,
        silenceIntent: 0.35),
    templates: [
      'Back. {task} is still there. Shall we?',
      'Good — you came back. {task}?'
    ],
    systemPromptHint:
        'USER RETURNED after nudge ignore. Welcome back. No comment on absence. Move to task.',
    requiresEarphone: true,
  ),
  VoicePattern.silenceThinking: const PatternProfile(
    dimensions: VoiceDimensions(brevity: 1.0, silenceIntent: 1.0),
    templates: [],
    speakable: false,
    systemPromptHint: '< 6s silence. Do not interrupt thinking.',
  ),
  VoicePattern.silencePresent: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.5,
        warmth: 0.5,
        brevity: 0.9,
        pace: 0.38,
        silenceIntent: 0.4),
    templates: ['Still with me?', 'No rush.', 'Take your time.'],
    systemPromptHint: '6-12s silence. One gentle check. Warm. No pressure.',
  ),
  VoicePattern.silenceDrifted: const PatternProfile(
    dimensions: VoiceDimensions(
        proximity: 0.4,
        warmth: 0.6,
        brevity: 0.9,
        pace: 0.35,
        silenceIntent: 0.5),
    templates: ['No rush. Whenever you are ready.', 'Still here.'],
    systemPromptHint: '12-20s silence. Lower stakes. Reminder you are present.',
  ),
  VoicePattern.silenceGone: const PatternProfile(
    dimensions: VoiceDimensions(brevity: 1.0, silenceIntent: 1.0),
    templates: [],
    speakable: false,
    systemPromptHint: '> 20s silence. Stop completely.',
  ),
  VoicePattern.silenceAfterWin: const PatternProfile(
    dimensions: VoiceDimensions(brevity: 1.0, silenceIntent: 1.0),
    templates: [],
    speakable: false,
    postSilenceMs: 3500,
    systemPromptHint: 'Post-completion. Hold it. Do not fill the moment.',
  ),
};

// ─── PATTERN SELECTOR ────────────────────────────────────────
class PatternSelectorInput {
  final int sessionMinutes;
  final bool isLateNight;
  final bool isEarphone;
  final bool isFirstSession;
  final int hoursSinceLastSession;
  final int excuseCount;
  final int deferralCount;
  final bool taskJustCompleted;
  final bool noTasksRemaining;
  final bool userOverwhelmedSignal;
  final double userSpeechWps;
  final int silenceSeconds;
  final bool userJustReturned;
  final int nudgeIgnoreStreak;
  final String? promiseBrokenTask;
  final bool promiseKept;
  final int screenTimeMinutes;
  final int unlockCount;
  final int socialMinutes;
  final int longestFocusMinutes;
  final int taskIdleHours;
  final bool overdueTask;
  final bool taskDueToday;
  final bool driftDetected;
  final bool breakthroughSignal;
  final bool cleanDay;

  const PatternSelectorInput({
    this.sessionMinutes = 0,
    this.isLateNight = false,
    this.isEarphone = false,
    this.isFirstSession = false,
    this.hoursSinceLastSession = 1,
    this.excuseCount = 0,
    this.deferralCount = 0,
    this.taskJustCompleted = false,
    this.noTasksRemaining = false,
    this.userOverwhelmedSignal = false,
    this.userSpeechWps = 2.0,
    this.silenceSeconds = 0,
    this.userJustReturned = false,
    this.nudgeIgnoreStreak = 0,
    this.promiseBrokenTask,
    this.promiseKept = false,
    this.screenTimeMinutes = 0,
    this.unlockCount = 0,
    this.socialMinutes = 0,
    this.longestFocusMinutes = 0,
    this.taskIdleHours = 0,
    this.overdueTask = false,
    this.taskDueToday = false,
    this.driftDetected = false,
    this.breakthroughSignal = false,
    this.cleanDay = false,
  });
}

extension PatternSelectorInputCopyWith on PatternSelectorInput {
  PatternSelectorInput copyWith({
    int? sessionMinutes,
    bool? isLateNight,
    bool? isEarphone,
    bool? isFirstSession,
    int? hoursSinceLastSession,
    int? excuseCount,
    int? deferralCount,
    bool? taskJustCompleted,
    bool? noTasksRemaining,
    bool? userOverwhelmedSignal,
    double? userSpeechWps,
    int? silenceSeconds,
    bool? userJustReturned,
    int? nudgeIgnoreStreak,
    String? promiseBrokenTask,
    bool? promiseKept,
    int? screenTimeMinutes,
    int? unlockCount,
    int? socialMinutes,
    int? longestFocusMinutes,
    int? taskIdleHours,
    bool? overdueTask,
    bool? taskDueToday,
    bool? driftDetected,
    bool? breakthroughSignal,
    bool? cleanDay,
  }) =>
      PatternSelectorInput(
        sessionMinutes: sessionMinutes ?? this.sessionMinutes,
        isLateNight: isLateNight ?? this.isLateNight,
        isEarphone: isEarphone ?? this.isEarphone,
        isFirstSession: isFirstSession ?? this.isFirstSession,
        hoursSinceLastSession:
            hoursSinceLastSession ?? this.hoursSinceLastSession,
        excuseCount: excuseCount ?? this.excuseCount,
        deferralCount: deferralCount ?? this.deferralCount,
        taskJustCompleted: taskJustCompleted ?? this.taskJustCompleted,
        noTasksRemaining: noTasksRemaining ?? this.noTasksRemaining,
        userOverwhelmedSignal:
            userOverwhelmedSignal ?? this.userOverwhelmedSignal,
        userSpeechWps: userSpeechWps ?? this.userSpeechWps,
        silenceSeconds: silenceSeconds ?? this.silenceSeconds,
        userJustReturned: userJustReturned ?? this.userJustReturned,
        nudgeIgnoreStreak: nudgeIgnoreStreak ?? this.nudgeIgnoreStreak,
        promiseBrokenTask: promiseBrokenTask ?? this.promiseBrokenTask,
        promiseKept: promiseKept ?? this.promiseKept,
        screenTimeMinutes: screenTimeMinutes ?? this.screenTimeMinutes,
        unlockCount: unlockCount ?? this.unlockCount,
        socialMinutes: socialMinutes ?? this.socialMinutes,
        longestFocusMinutes: longestFocusMinutes ?? this.longestFocusMinutes,
        taskIdleHours: taskIdleHours ?? this.taskIdleHours,
        overdueTask: overdueTask ?? this.overdueTask,
        taskDueToday: taskDueToday ?? this.taskDueToday,
        driftDetected: driftDetected ?? this.driftDetected,
        breakthroughSignal: breakthroughSignal ?? this.breakthroughSignal,
        cleanDay: cleanDay ?? this.cleanDay,
      );
}

class PatternSelector {
  static VoicePattern select(PatternSelectorInput ctx) {
    if (ctx.silenceSeconds > 20) return VoicePattern.silenceGone;
    if (ctx.silenceSeconds > 12) return VoicePattern.silenceDrifted;
    if (ctx.silenceSeconds > 6) return VoicePattern.silencePresent;
    if (ctx.silenceSeconds > 0 && ctx.silenceSeconds < 6)
      return VoicePattern.silenceThinking;
    if (ctx.taskJustCompleted) return VoicePattern.taskComplete;
    if (ctx.noTasksRemaining) return VoicePattern.allTasksClear;
    if (ctx.promiseKept) return VoicePattern.promiseKept;
    if (ctx.breakthroughSignal) return VoicePattern.userBreakthrough;
    if (ctx.isEarphone) {
      if (ctx.nudgeIgnoreStreak >= 3) return VoicePattern.earphoneDayAbandoned;
      if (ctx.nudgeIgnoreStreak >= 1) return VoicePattern.earphoneIgnored;
      if (ctx.userJustReturned) return VoicePattern.earphoneReturn;
      if (ctx.taskIdleHours >= 6) return VoicePattern.taskIdle6h;
      if (ctx.taskIdleHours >= 2) return VoicePattern.taskIdle2h;
      return VoicePattern.earphoneNudge;
    }
    if (ctx.promiseBrokenTask != null) return VoicePattern.promiseBroken;
    if (ctx.excuseCount >= 4) return VoicePattern.excuseFourth;
    if (ctx.excuseCount == 3) return VoicePattern.excuseThird;
    if (ctx.excuseCount == 2) return VoicePattern.excuseSecond;
    if (ctx.excuseCount == 1) return VoicePattern.excuseFirst;
    if (ctx.overdueTask) return VoicePattern.overdueTask;
    if (ctx.taskDueToday) return VoicePattern.taskNearDue;
    if (ctx.deferralCount >= 3) return VoicePattern.thirdDeferral;
    if (ctx.driftDetected) return VoicePattern.userDistracted;
    if (ctx.userOverwhelmedSignal) return VoicePattern.userOverwhelmed;
    if (ctx.userSpeechWps > 3.5) return VoicePattern.userEnergised;
    if (ctx.isLateNight) return VoicePattern.lateNightWrap;
    if (ctx.sessionMinutes < 5) {
      if (ctx.cleanDay) return VoicePattern.cleanDay;
      if (ctx.screenTimeMinutes > 240) return VoicePattern.heavyScreenDay;
      if (ctx.unlockCount > 60) return VoicePattern.fragmentedDay;
      if (ctx.longestFocusMinutes < 20 && ctx.screenTimeMinutes > 60)
        return VoicePattern.noFocusBlock;
      if (ctx.socialMinutes > 90) return VoicePattern.socialHeavy;
    }
    if (ctx.isFirstSession) return VoicePattern.firstEverSession;
    if (ctx.sessionMinutes == 0 && ctx.hoursSinceLastSession > 8)
      return VoicePattern.longGapReturn;
    if (ctx.sessionMinutes == 0) {
      return DateTime.now().hour < 12
          ? VoicePattern.morningOrient
          : VoicePattern.returnWithTask;
    }
    if (ctx.sessionMinutes > 45) return VoicePattern.sessionEndPush;
    if (ctx.sessionMinutes > 20) return VoicePattern.sessionMidFocus;
    return VoicePattern.freshOpen;
  }

  static String buildPatternInjection(VoicePattern pattern,
      {String? taskName,
      String? promiseText,
      int? daysOverdue,
      int? unlockCount}) {
    final profile = kPatternLibrary[pattern];
    if (profile == null) return '';
    var hint = profile.systemPromptHint ?? '';
    if (taskName != null) hint = hint.replaceAll('{task}', taskName);
    if (promiseText != null) hint = hint.replaceAll('{promise}', promiseText);
    if (daysOverdue != null)
      hint = hint.replaceAll('{days}', '$daysOverdue days');
    if (unlockCount != null)
      hint = hint.replaceAll('{unlockCount}', '$unlockCount');
    final d = profile.dimensions;
    final pauseMs = profile.postSilenceMs ?? d.postUtterancePauseMs;
    return '''
━━━ VOICE PATTERN: ${pattern.name.toUpperCase()} ━━━
$hint

DIMENSIONS:
  proximity=${(d.proximity * 10).round()}/10  urgency=${(d.urgency * 10).round()}/10  warmth=${(d.warmth * 10).round()}/10
  challenge=${(d.challenge * 10).round()}/10  brevity=${(d.brevity * 10).round()}/10  silence=${(d.silenceIntent * 10).round()}/10

TTS: rate=${d.ttsRate.toStringAsFixed(2)} pitch=${d.ttsPitch.toStringAsFixed(2)} vol=${d.ttsVolume.toStringAsFixed(2)} pause=${pauseMs}ms

ARCHITECTURE: ${_architectureHint(d)}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''';
  }

  static String _architectureHint(VoiceDimensions d) {
    if (d.brevity >= 0.9) return 'One sentence. Possibly one word.';
    if (d.brevity >= 0.7) return 'Two sentences max. No filler.';
    if (d.urgency >= 0.7) return 'Declarative. Now. One question at end.';
    if (d.warmth >= 0.7 && d.pace <= 0.35)
      return 'Slower rhythm. Warmer words. No pressure.';
    if (d.challenge >= 0.7)
      return 'State the observation. One question. No softening. Pause.';
    return 'Natural. Max 40 words. End with question or action.';
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION A2 — HUMAN SPEECH ENGINE (Research-Calibrated 2025)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// ─── LAYER 0: THE THREE LAWS OF HUMAN SPEECH ─────────────────────────────
//
// Research from acoustic phonetics shows TTS sounds robotic because it
// violates three fundamental properties of human speech:
//
// LAW 1 — STOCHASTIC VARIATION (jitter + shimmer)
//   Human vocal folds never produce two identical cycles. Period-to-period
//   F0 variation (jitter) = 0.5–2.0% in normal speech. Amplitude variation
//   (shimmer) = 0.1–0.4 dB. Synthesised speech has 0 jitter/shimmer.
//   Fix: inject Gaussian noise on every TTS parameter, every call.
//
// LAW 2 — F0 DECLINATION WITH RESET
//   Human pitch falls 10–20 Hz over a declarative utterance (declination).
//   At phrase boundaries it "resets" — jumps back up to signal new info.
//   TTS engines hold pitch flat or use a single arc. Sounds monotone.
//   Fix: model utterance pitch arc as: high onset → gradual fall → reset
//   at each phrase boundary, final fall at utterance end.
//
// LAW 3 — RATE-PITCH COVARIATION
//   When humans speed up, pitch rises. When they slow down, pitch falls.
//   This coupling is physiological (subglottal pressure). TTS breaks it.
//   Fix: derive pitch delta FROM rate delta, not independently.
//
// Plus: spontaneous speech has disfluencies, prefinal lengthening,
// boundary-initial strengthening, and micro-pause variation.
// All modelled below.

// ─── EMOTION TAGS (keep same interface as v10 — no breaking change) ────────
enum EmotionTag {
  quietly,
  firmly,
  warmly,
  drily,
  urgently,
  heavily,
  brightly,
  sighs,
  pauses,
  settles,
  breathes,
  murmurs,
  neutral,
}

class EmotionTagProfile {
  final double rateDelta;
  final double pitchDelta;
  final double volumeDelta;
  final int preUtterancePauseMs;
  final int postUtterancePauseMs;
  final double breathPauseMs;

  const EmotionTagProfile({
    this.rateDelta = 0.0,
    this.pitchDelta = 0.0,
    this.volumeDelta = 0.0,
    this.preUtterancePauseMs = 0,
    this.postUtterancePauseMs = 0,
    this.breathPauseMs = 0,
  });
}

const Map<EmotionTag, EmotionTagProfile> kEmotionProfiles = {
  EmotionTag.quietly: EmotionTagProfile(
      rateDelta: -0.07,
      pitchDelta: -0.04,
      volumeDelta: -0.14,
      preUtterancePauseMs: 90,
      breathPauseMs: 30),
  EmotionTag.firmly: EmotionTagProfile(
      rateDelta: -0.04,
      pitchDelta: -0.06,
      volumeDelta: 0.02,
      preUtterancePauseMs: 70,
      breathPauseMs: 10),
  EmotionTag.warmly: EmotionTagProfile(
      rateDelta: -0.06,
      pitchDelta: 0.04,
      volumeDelta: -0.02,
      preUtterancePauseMs: 50,
      breathPauseMs: 25),
  EmotionTag.drily: EmotionTagProfile(
      rateDelta: 0.0,
      pitchDelta: -0.03,
      volumeDelta: -0.04,
      preUtterancePauseMs: 40,
      breathPauseMs: 15),
  EmotionTag.urgently: EmotionTagProfile(
      rateDelta: 0.08,
      pitchDelta: 0.02,
      volumeDelta: 0.04,
      preUtterancePauseMs: 0,
      breathPauseMs: 0),
  EmotionTag.heavily: EmotionTagProfile(
      rateDelta: -0.10,
      pitchDelta: -0.08,
      volumeDelta: 0.0,
      preUtterancePauseMs: 140,
      postUtterancePauseMs: 220,
      breathPauseMs: 45),
  EmotionTag.brightly: EmotionTagProfile(
      rateDelta: 0.05,
      pitchDelta: 0.05,
      volumeDelta: 0.0,
      preUtterancePauseMs: 0,
      breathPauseMs: 0),
  EmotionTag.sighs: EmotionTagProfile(
      rateDelta: -0.05,
      pitchDelta: -0.03,
      volumeDelta: -0.06,
      preUtterancePauseMs: 650,
      breathPauseMs: 40),
  EmotionTag.pauses: EmotionTagProfile(
      rateDelta: -0.02,
      pitchDelta: 0.0,
      volumeDelta: 0.0,
      preUtterancePauseMs: 750,
      breathPauseMs: 20),
  EmotionTag.settles: EmotionTagProfile(
      rateDelta: -0.06,
      pitchDelta: -0.01,
      volumeDelta: 0.0,
      preUtterancePauseMs: 300,
      breathPauseMs: 35),
  EmotionTag.breathes: EmotionTagProfile(
      rateDelta: -0.03,
      pitchDelta: 0.0,
      volumeDelta: -0.02,
      preUtterancePauseMs: 120,
      breathPauseMs: 80),
  EmotionTag.murmurs: EmotionTagProfile(
      rateDelta: -0.08,
      pitchDelta: -0.05,
      volumeDelta: -0.20,
      preUtterancePauseMs: 60,
      breathPauseMs: 50),
  EmotionTag.neutral: EmotionTagProfile(),
};

class EmotionTagParser {
  static final _tagRe = RegExp(
    r'\[(quietly|firmly|warmly|drily|urgently|heavily|brightly|sighs|pauses|settles|breathes|murmurs)\]',
    caseSensitive: false,
  );

  static (String, EmotionTag) parse(String text) {
    final match = _tagRe.firstMatch(text);
    EmotionTag tag = EmotionTag.neutral;
    if (match != null) {
      final name = match.group(1)!.toLowerCase();
      tag = EmotionTag.values
          .firstWhere((t) => t.name == name, orElse: () => EmotionTag.neutral);
    }
    final clean =
        text.replaceAll(_tagRe, '').replaceAll(RegExp(r'  +'), ' ').trim();
    return (clean, tag);
  }

  static EmotionTag inferFromPattern(VoicePattern p) => switch (p) {
        VoicePattern.excuseThird => EmotionTag.firmly,
        VoicePattern.excuseFourth => EmotionTag.heavily,
        VoicePattern.promiseBroken => EmotionTag.firmly,
        VoicePattern.userBreakthrough => EmotionTag.settles,
        VoicePattern.taskComplete => EmotionTag.warmly,
        VoicePattern.lateNightWrap => EmotionTag.quietly,
        VoicePattern.earphoneFirstContact => EmotionTag.warmly,
        VoicePattern.userFatigued => EmotionTag.quietly,
        VoicePattern.thirdDeferral => EmotionTag.drily,
        VoicePattern.userOverwhelmed => EmotionTag.warmly,
        VoicePattern.userEnergised => EmotionTag.brightly,
        VoicePattern.sessionEndPush => EmotionTag.urgently,
        VoicePattern.overdueTask => EmotionTag.firmly,
        VoicePattern.silenceAfterWin => EmotionTag.settles,
        VoicePattern.firstEverSession => EmotionTag.warmly,
        VoicePattern.promiseKept => EmotionTag.warmly,
        VoicePattern.morningOrient => EmotionTag.brightly,
        VoicePattern.userFrustrated => EmotionTag.quietly,
        VoicePattern.excuseSecond => EmotionTag.drily,
        VoicePattern.earphoneDayAbandoned => EmotionTag.heavily,
        _ => EmotionTag.neutral,
      };
}

// ─── LAYER 6: SYNTAGM SPLITTER (upgraded, keep same interface) ────────────
enum SyntagmClass {
  warmOpen,
  anchor,
  pivot,
  challenge,
  completion,
  question,
  qualifier,
  emphasis,
}

class Syntagm {
  final String text;
  final SyntagmClass cls;
  final int postPauseMs;
  final int prePauseMs;
  final double rateScale;
  final double pitchDelta;
  final double volScale;

  const Syntagm({
    required this.text,
    required this.cls,
    required this.postPauseMs,
    required this.prePauseMs,
    required this.rateScale,
    required this.pitchDelta,
    required this.volScale,
  });
}

class SyntagmSplitter {
  static const _warmOpeners = {
    'right then',
    'right.',
    'right —',
    'good.',
    'good —',
    'well —',
    'well,',
    'mm.',
    'mm —',
    'morning.',
    'still here.',
    'no rush.',
    'fair enough.',
    'not to worry.',
    'brilliant.',
    'precisely.',
    'there we are.',
    'there it is.',
    'done and done.',
    'done.',
    'there.',
    'spot on.',
    'quite.',
  };
  static const _pivotWords = {
    'though',
    'however',
    'which means',
    'and yet',
    'but first',
    'before that',
    'instead',
    'rather',
    'then again',
    'that said',
  };
  static const _challengeMarkers = {
    'three times',
    'twice now',
    'two times',
    'again.',
    'we have been here before',
    'we\'ve been here before',
    'that is the second',
    'what is really going on',
    'what changed',
    'what is in the way',
    'what is the real reason',
    'the third time',
    'still there.',
    'still there —',
  };
  static const _completionMarkers = {
    'done.',
    'sorted.',
    'brilliant.',
    'there we are.',
    'good — you did it.',
    'you said you would and you did.',
    'done and done.',
    'there it is.',
    'right.',
    'good.',
    'that is sorted.',
    'that is done.',
    'spot on.',
  };

  static List<Syntagm> split(
    String text,
    VoiceDimensions dims,
    EmotionTag emotionTag,
    bool isEarphone,
  ) {
    if (text.trim().isEmpty) return [];
    final phrases = _splitToPhrases(text, isEarphone);
    final boundary = BoundaryModel();
    return [
      for (int i = 0; i < phrases.length; i++)
        _classify(phrases[i], dims, emotionTag, i == phrases.length - 1, i == 0,
            i, phrases.length, boundary),
    ];
  }

  static List<String> _splitToPhrases(String text, bool isEarphone) {
    final results = <String>[];
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    for (final sentence in sentences) {
      if (sentence.trim().isEmpty) continue;
      final parts = sentence.split(
        RegExp(
            r'\s*—\s*|\s*;\s*|,\s*(?=(?:though|however|which means|and yet|but|instead|rather)\b)'),
      );
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final maxWords = isEarphone ? 7 : 13;
        final words = trimmed.split(' ');
        if (words.length > maxWords) {
          final commaParts = trimmed.split(RegExp(r',\s+'));
          if (commaParts.length > 1) {
            for (final cp in commaParts) {
              if (cp.trim().isNotEmpty) results.add(cp.trim());
            }
          } else {
            for (int i = 0; i < words.length; i += maxWords) {
              final chunk = words.skip(i).take(maxWords).join(' ');
              if (chunk.isNotEmpty) results.add(chunk);
            }
          }
        } else {
          results.add(trimmed);
        }
      }
    }
    return results.where((s) => s.isNotEmpty).toList();
  }

  static Syntagm _classify(
    String phrase,
    VoiceDimensions dims,
    EmotionTag emotionTag,
    bool isLast,
    bool isFirst,
    int index,
    int total,
    BoundaryModel boundary,
  ) {
    final lower =
        phrase.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    final wordCount = phrase.split(' ').length;
    final endsQuestion = phrase.trimRight().endsWith('?');
    final endsSentence = RegExp(r'[.!?]$').hasMatch(phrase.trimRight());

    SyntagmClass cls;
    if (isFirst &&
        _warmOpeners.any((w) =>
            lower.startsWith(w.replaceAll(RegExp(r'[.—]'), '').trim()))) {
      cls = SyntagmClass.warmOpen;
    } else if (_completionMarkers.any(
        (m) => lower == m.replaceAll('.', '').trim() || lower == m.trim())) {
      cls = SyntagmClass.completion;
    } else if (_challengeMarkers.any((m) => lower.contains(m))) {
      cls = SyntagmClass.challenge;
    } else if (_pivotWords.any((pv) => lower.contains(pv))) {
      cls = SyntagmClass.pivot;
    } else if (endsQuestion) {
      cls = SyntagmClass.question;
    } else if (!isFirst && endsSentence && wordCount <= 5) {
      cls = SyntagmClass.emphasis;
    } else if (!endsSentence || (!isFirst && wordCount <= 6)) {
      cls = SyntagmClass.qualifier;
    } else {
      cls = SyntagmClass.anchor;
    }

    final (rs, pd, vs) = switch (cls) {
      SyntagmClass.warmOpen => (0.80, 0.04, 0.94),
      SyntagmClass.anchor => (1.00 + dims.urgency * 0.09, 0.0, 1.0),
      SyntagmClass.pivot => (1.05, 0.01, 0.96),
      SyntagmClass.challenge => (0.88, -0.05, 1.0),
      SyntagmClass.completion => (0.73, -0.07, 0.96),
      SyntagmClass.question => (wordCount <= 5 ? 0.86 : 0.93, 0.05, 1.0),
      SyntagmClass.qualifier => (1.07, 0.0, 0.95),
      SyntagmClass.emphasis => (0.78, -0.02, 1.03),
    };

    final ep = kEmotionProfiles[emotionTag]!;
    final finalRate = (rs + ep.rateDelta / 0.42).clamp(0.60, 1.50);
    final finalPitch = pd + ep.pitchDelta;
    final finalVol = (vs + ep.volumeDelta).clamp(0.55, 1.0);

    final prePause =
        isFirst ? 0 : (ep.breathPauseMs > 0 ? ep.breathPauseMs.round() : 0);

    final (postPause, _) = boundary.pauseAfterPhrase(
      cls: cls,
      isLast: isLast,
      silenceIntent: dims.silenceIntent,
      emotion: emotionTag,
      proximity: dims.proximity,
      phraseIndex: index,
      totalPhrases: total,
    );

    return Syntagm(
      text: phrase,
      cls: cls,
      postPauseMs: postPause,
      prePauseMs: prePause,
      rateScale: finalRate,
      pitchDelta: finalPitch,
      volScale: finalVol,
    );
  }
}

// ─── LAYER 7: SPEECH NORMALISER (unchanged from v10) ─────────────────────
class SpeechNormaliser {
  static String normalise(String text) {
    String t = text;
    t = t
        .replaceAll(RegExp(r'\*{1,3}([^*]+)\*{1,3}'), r'\1')
        .replaceAll(RegExp(r'#{1,6}\s'), '')
        .replaceAll(RegExp(r'https?://\S+'), 'a link')
        .replaceAll(RegExp(r'[_`]'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'\1');
    t = t
        .replaceAll('&', ' and ')
        .replaceAll('%', ' percent')
        .replaceAll('£', ' pounds ')
        .replaceAll('€', ' euros ')
        .replaceAll(r'$', ' dollars ')
        .replaceAll('≈', ' approximately ')
        .replaceAll('→', ' which leads to ')
        .replaceAll('×', ' times ')
        .replaceAll('÷', ' divided by ')
        .replaceAll('…', '.');
    t = t
        .replaceAll('e.g.', 'for example')
        .replaceAll('i.e.', 'that is')
        .replaceAll('etc.', 'and so on')
        .replaceAll('vs.', 'versus')
        .replaceAll('vs', 'versus')
        .replaceAll('approx.', 'approximately')
        .replaceAll('w/', 'with')
        .replaceAll('w/o', 'without');
    t = t.replaceAllMapped(
        RegExp(r'\b(\d{1,2}):(\d{2})\s*(am|pm)?\b', caseSensitive: false), (m) {
      final h = int.tryParse(m.group(1) ?? '') ?? 0;
      final min = int.tryParse(m.group(2) ?? '') ?? 0;
      final period = m.group(3) != null ? ' ${m.group(3)!.toLowerCase()}' : '';
      return '${_numToWords(h)}${min == 0 ? '' : ' ${_numToWords(min)}'}$period';
    });
    t = t.replaceAllMapped(RegExp(r'\b(\d+)(st|nd|rd|th)\b'), (m) {
      final n = int.tryParse(m.group(1) ?? '');
      if (n == null) return m.group(0)!;
      const ord = [
        '',
        'first',
        'second',
        'third',
        'fourth',
        'fifth',
        'sixth',
        'seventh',
        'eighth',
        'ninth',
        'tenth',
        'eleventh',
        'twelfth',
        'thirteenth',
        'fourteenth',
        'fifteenth',
        'sixteenth',
        'seventeenth',
        'eighteenth',
        'nineteenth',
        'twentieth'
      ];
      return (n > 0 && n < ord.length) ? ord[n] : '${m.group(1)} ${m.group(2)}';
    });
    t = t.replaceAllMapped(RegExp(r'\b(\d{1,4})\b'), (m) {
      final n = int.tryParse(m.group(1) ?? '');
      return n != null ? _numToWords(n) : m.group(1)!;
    });
    return t.replaceAll(RegExp(r' {2,}'), ' ').trim();
  }

  static String _numToWords(int n) {
    if (n < 0) return 'minus ${_numToWords(-n)}';
    const ones = [
      'zero',
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
      'nine',
      'ten',
      'eleven',
      'twelve',
      'thirteen',
      'fourteen',
      'fifteen',
      'sixteen',
      'seventeen',
      'eighteen',
      'nineteen',
      'twenty'
    ];
    const tensW = [
      '',
      '',
      'twenty',
      'thirty',
      'forty',
      'fifty',
      'sixty',
      'seventy',
      'eighty',
      'ninety'
    ];
    if (n <= 20) return ones[n];
    if (n < 100) {
      final t = tensW[n ~/ 10];
      return t + (n % 10 == 0 ? '' : ' ${ones[n % 10]}');
    }
    if (n < 1000) {
      return '${ones[n ~/ 100]} hundred${n % 100 == 0 ? '' : ' and ${_numToWords(n % 100)}'}';
    }
    if (n < 10000) {
      return '${_numToWords(n ~/ 1000)} thousand${n % 1000 == 0 ? '' : ' and ${_numToWords(n % 1000)}'}';
    }
    return n.toString();
  }
}

// ─── LAYER 1: F0 CONTOUR MODEL ───────────────────────────────────────────
// Models the utterance-level pitch arc as a breath-group hierarchy.
// Based on Liberman (1967) breath-group theory + Ladd (1988) declination model.
//
// Architecture:
//   utterance = [breath_group_1] [breath_group_2] ...
//   breath_group = onset_peak → gradual_fall → boundary_fall → reset
//
// The reset at phrase boundaries is the most human-sounding feature.
// Without it: monotone. With it: narrative, engaged, alive.
class F0ContourModel {
  final _rng = math.Random();

  // Utterance-level parameters — set once per utterance
  double _baseF0; // normalised 0.0–1.0 maps to actual pitch values
  double _currentF0; // tracks current position
  double _declinationRate; // Hz drop per phrase (normalised)
  int _phraseCount = 0;
  int _totalPhrases = 1;
  bool _isQuestion = false;

  F0ContourModel({double baseF0 = 0.50})
      : _baseF0 = baseF0,
        _currentF0 = baseF0,
        _declinationRate = 0.0;

  /// Call once before utterance begins. Sets the full pitch arc.
  void beginUtterance({
    required int totalPhrases,
    required EmotionTag emotion,
    required bool isQuestion,
    required double urgency,
  }) {
    _totalPhrases = totalPhrases.clamp(1, 20);
    _phraseCount = 0;
    _isQuestion = isQuestion;

    // Onset: emotional state shifts baseline
    // Urgency pushes pitch up; fatigue/quiet pulls it down
    final emotionOffset = switch (emotion) {
      EmotionTag.brightly => 0.04,
      EmotionTag.urgently => 0.03,
      EmotionTag.warmly => 0.01,
      EmotionTag.quietly => -0.02,
      EmotionTag.heavily => -0.04,
      EmotionTag.murmurs => -0.05,
      EmotionTag.firmly => -0.01,
      _ => 0.00,
    };
    _currentF0 = _baseF0 + emotionOffset + (urgency * 0.02);

    // Declination rate: total pitch drop divided across phrases.
    // Research: ~10–15 normalised units over declarative utterance.
    // Questions have LESS declination (rising at end overrides it).
    final totalDrop = isQuestion ? 0.008 : 0.015;
    _declinationRate = _totalPhrases > 1 ? totalDrop / _totalPhrases : 0.0;
  }

  /// Call at start of each phrase. Returns pitch delta for this phrase.
  /// Implements declination + reset architecture.
  double nextPhrasePitchDelta() {
    _phraseCount++;
    final progress = _phraseCount / _totalPhrases; // 0.0→1.0

    // Apply declination: gradual fall
    _currentF0 -= _declinationRate;

    // Phrase-initial peak: brief pitch boost at phrase boundary
    // (boundary-initial strengthening — Cho & Keating 2009)
    // This is what creates the "alive" feeling between phrases
    final initialPeak = _rng.nextDouble() * 0.012;

    // Pre-final rise for questions (final phrase only)
    final finalRise = (_isQuestion && progress >= 0.85) ? 0.025 : 0.0;

    // Declination overshot? Floors at 65% of base (never go dead-flat)
    _currentF0 = _currentF0.clamp(_baseF0 * 0.65, _baseF0 * 1.25);

    // Natural jitter on F0 — period-to-period variation (LAW 1)
    // Gaussian noise, std = 1.5% of current value
    final jitter = _gaussianNoise(0.0, _currentF0 * 0.015);

    return initialPeak + finalRise + jitter;
  }

  /// Returns word-level pitch variation (micro-intonation within a phrase)
  /// Simulates prominence marking and de-accenting of function words
  double wordPitchDelta(String word, int wordIndex, int phraseLength) {
    // Accent position: content words in phrase-medial position get peaks
    final isContent = !_HumanPhonetics.isFunctionWord(word);
    final isFinal = wordIndex >= phraseLength - 1;
    final isInitial = wordIndex == 0;

    if (isContent && !isFinal) {
      // Nuclear accent: prominence boost
      return 0.008 + _rng.nextDouble() * 0.012;
    }
    if (isFinal) {
      // Final lowering: pitch falls on last word
      return -0.008 - _rng.nextDouble() * 0.010;
    }
    if (isInitial) {
      // Onset strengthening
      return 0.004 + _rng.nextDouble() * 0.006;
    }
    // Function words: de-accent (stay low)
    return _gaussianNoise(0.0, 0.003);
  }

  double _gaussianNoise(double mean, double stddev) {
    // Box-Muller transform — proper Gaussian distribution
    final u1 = _rng.nextDouble();
    final u2 = _rng.nextDouble();
    final z =
        math.sqrt(-2.0 * math.log(u1 + 1e-10)) * math.cos(2 * math.pi * u2);
    return mean + stddev * z;
  }
}

// ─── LAYER 2: DURATION MODEL ──────────────────────────────────────────────
// Models word-level speaking rate variation.
// Key insight: rate is NOT uniform. Humans:
//   - slow before prominent syllables (pre-nuclear lengthening)
//   - speed through function words (reduction)
//   - lengthen phrase-final syllables 150-200% (prefinal lengthening)
//   - have micro-hesitations before content words (cognitive planning)
class DurationModel {
  final _rng = math.Random();

  /// Returns rate scale for this word (1.0 = base rate)
  double wordRateScale({
    required String word,
    required int wordIndex,
    required int phraseLength,
    required double urgency,
    required double emotionRateDelta,
  }) {
    final isFinal = wordIndex >= phraseLength - 1;
    final isContent = !_HumanPhonetics.isFunctionWord(word);
    final syllables = _HumanPhonetics.estimateSyllables(word);

    // Base: content words ~5% slower (more articulatory precision)
    double scale = isContent ? 0.95 : 1.05;

    // Prefinal lengthening: phrase-final words 15-25% slower
    // (Turk & Shattuck-Hufnagel 2007 — robust across languages)
    if (isFinal) scale *= 0.78 + _rng.nextDouble() * 0.09;

    // Pre-nuclear slowing: word before stressed word slows
    // Simulated as general pre-content-word deceleration
    if (isContent && wordIndex > 0 && wordIndex < phraseLength - 2) {
      scale *= 0.92 + _rng.nextDouble() * 0.08;
    }

    // Polysyllabic words: slightly slower (more motor planning)
    if (syllables >= 3) scale *= 0.93;

    // Urgency: compresses duration (faster = more urgent)
    scale *= 1.0 + urgency * 0.12;

    // Stochastic shimmer equivalent on duration (LAW 1 for rate)
    // Gaussian, std = 3% of scale
    final durationJitter = _gaussianNoise(0.0, scale * 0.03);
    scale += durationJitter;

    return scale.clamp(0.55, 1.65);
  }

  /// Returns pre-word hesitation pause in ms (cognitive planning simulation)
  int preWordPause({
    required String word,
    required int wordIndex,
    required bool isPhraseFinal,
    required double urgency,
  }) {
    if (wordIndex == 0) return 0; // no pause before first word

    final isContent = !_HumanPhonetics.isFunctionWord(word);
    final syllables = _HumanPhonetics.estimateSyllables(word);

    // Micro-hesitation probability before polysyllabic content words
    // Research: ~18% of within-clause hesitations in spontaneous speech
    // (Goldman-Eisler 1968, Levelt 1989)
    double probability = 0.0;
    if (isContent && syllables >= 2) probability = 0.16;
    if (isContent && syllables >= 3) probability = 0.26;
    if (isPhraseFinal) probability *= 0.3; // rare before final word

    // Urgency suppresses hesitations
    probability *= (1.0 - urgency * 0.6);

    if (_rng.nextDouble() < probability) {
      // Duration: 40–110ms (sub-perceptual as "pause" but feels like thought)
      return 40 + _rng.nextInt(70);
    }
    return 0;
  }

  double _gaussianNoise(double mean, double stddev) {
    final u1 = _rng.nextDouble();
    final u2 = _rng.nextDouble();
    final z =
        math.sqrt(-2.0 * math.log(u1 + 1e-10)) * math.cos(2 * math.pi * u2);
    return mean + stddev * z;
  }
}

// ─── LAYER 3: AMPLITUDE MODEL ─────────────────────────────────────────────
// Volume variation within and across phrases.
// Research: amplitude shimmer = 0.1–0.4 dB in natural speech.
// Key patterns:
//   - Phrase-initial boost (boundary strengthening)
//   - Nuclear accent boost (prominent syllable louder)
//   - Phrase-final reduction (declination in intensity mirrors F0)
//   - Whisper carry (quiet emotion reduces amplitude continuously)
class AmplitudeModel {
  final _rng = math.Random();

  double wordVolumeScale({
    required String word,
    required int wordIndex,
    required int phraseLength,
    required EmotionTag emotion,
    required double baseVol,
  }) {
    double scale = 1.0;

    // Boundary-initial strengthening: first word slightly louder
    if (wordIndex == 0) scale *= 1.03 + _rng.nextDouble() * 0.02;

    // Nuclear accent: content words get amplitude boost
    final isContent = !_HumanPhonetics.isFunctionWord(word);
    if (isContent && wordIndex > 0 && wordIndex < phraseLength - 1) {
      scale *= 1.02 + _rng.nextDouble() * 0.03;
    }

    // Phrase-final: softer (intensity declination)
    if (wordIndex >= phraseLength - 1) scale *= 0.94 + _rng.nextDouble() * 0.04;

    // Shimmer: amplitude jitter (LAW 1 for volume)
    // ±1.5% random variation, every word
    scale *= 0.985 + _rng.nextDouble() * 0.030;

    // Emotion modulation
    scale *= switch (emotion) {
      EmotionTag.murmurs => 0.72,
      EmotionTag.quietly => 0.84,
      EmotionTag.urgently => 1.06,
      EmotionTag.firmly => 1.03,
      EmotionTag.brightly => 1.04,
      EmotionTag.heavily => 0.97,
      _ => 1.00,
    };

    return (baseVol * scale).clamp(0.50, 1.0);
  }
}

// ─── LAYER 4: PHRASE-LEVEL BOUNDARY MODEL ─────────────────────────────────
// Handles the silence structure at phrase boundaries.
// Critical insight: human inter-phrase pauses are NOT uniform.
// They vary by phrase type, emotion, and utterance position —
// and they have a RIGHT-SKEWED distribution (short median, long tail).
class BoundaryModel {
  final _rng = math.Random();

  /// Silence duration after a phrase, in ms
  /// Returns (pauseMs, shouldInjectBreathSound)
  (int, bool) pauseAfterPhrase({
    required SyntagmClass cls,
    required bool isLast,
    required double silenceIntent,
    required EmotionTag emotion,
    required double proximity,
    required int phraseIndex,
    required int totalPhrases,
  }) {
    if (isLast) {
      // Final pause: driven by silenceIntent + emotion
      final etBonus = switch (emotion) {
        EmotionTag.heavily => 380,
        EmotionTag.settles => 260,
        EmotionTag.sighs => 460,
        EmotionTag.pauses => 560,
        EmotionTag.murmurs => 220,
        _ => 0,
      };
      int base;
      if (silenceIntent >= 0.9)
        base = 2600;
      else if (silenceIntent >= 0.6)
        base = 1400;
      else if (silenceIntent >= 0.3)
        base = 720;
      else
        base = 320;

      // Right-skewed variation: add 0–40% randomly
      final jitter = _rng.nextDouble() * base * 0.40;
      return ((base + etBonus + jitter).round(), false);
    }

    // Inter-phrase pause: right-skewed log-normal distribution
    // Research: modal inter-clause pause = 80–180ms in spontaneous speech
    // with long tail to 800ms+ (Goldman-Eisler 1968)
    final baseMs = switch (cls) {
      SyntagmClass.warmOpen => _logNormal(220, 0.35),
      SyntagmClass.completion => _logNormal(360, 0.28),
      SyntagmClass.challenge => _logNormal(280, 0.22),
      SyntagmClass.pivot => _logNormal(110, 0.40),
      SyntagmClass.question => _logNormal(90, 0.35),
      SyntagmClass.qualifier => _logNormal(55, 0.45),
      SyntagmClass.emphasis => _logNormal(200, 0.30),
      SyntagmClass.anchor => _logNormal(145, 0.38),
    };

    // Proximity compression: intimate = shorter pauses (less formal space)
    final compressed = (baseMs * (1.0 - proximity * 0.22)).round();

    // Breath sound: inject ~12% of the time at phrase boundaries
    // (not actually audible, but the gap timing mimics breath intake)
    final shouldBreath = _rng.nextDouble() < 0.12;

    return (compressed.clamp(35, 580), shouldBreath);
  }

  /// Log-normal distribution — gives the right-skewed pause distribution
  /// seen in actual spontaneous speech recordings
  int _logNormal(double median, double sigma) {
    final u1 = _rng.nextDouble();
    final u2 = _rng.nextDouble();
    final z =
        math.sqrt(-2.0 * math.log(u1 + 1e-10)) * math.cos(2 * math.pi * u2);
    return (math.exp(math.log(median) + sigma * z)).round().clamp(25, 900);
  }
}

// ─── LAYER 5: HUMAN PHONETICS UTILITIES ──────────────────────────────────
// Linguistic knowledge used by the models above.
class _HumanPhonetics {
  static const _functionWords = {
    'the',
    'a',
    'an',
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'being',
    'have',
    'has',
    'had',
    'do',
    'does',
    'did',
    'will',
    'would',
    'could',
    'should',
    'may',
    'might',
    'shall',
    'can',
    'to',
    'of',
    'in',
    'for',
    'on',
    'with',
    'at',
    'by',
    'from',
    'up',
    'out',
    'as',
    'it',
    'its',
    'and',
    'but',
    'or',
    'nor',
    'so',
    'yet',
    'i',
    'you',
    'we',
    'they',
    'he',
    'she',
    'not',
    'that',
    'this',
    'these',
    'those',
    'then',
    'when',
    'still',
    'just',
    'even',
    'very',
    'quite',
    'rather',
    'here',
    'there',
    'if',
    'me',
  };

  static bool isFunctionWord(String word) => _functionWords
      .contains(word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), ''));

  /// Rough syllable count from letter patterns
  static int estimateSyllables(String word) {
    final w = word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (w.isEmpty) return 1;
    final vowels = RegExp(r'[aeiouy]+');
    final count = vowels.allMatches(w).length;
    // Account for silent e
    final silentE = w.endsWith('e') && w.length > 2 ? 1 : 0;
    return (count - silentE).clamp(1, 12);
  }

  /// Whether a text ends with a question
  static bool isQuestion(String text) => text.trimRight().endsWith('?');
}

// ─── LAYER 8: WORD SPEECH UNIT ────────────────────────────────────────────
class WordUnit {
  final String text;
  final double rate;
  final double pitch;
  final double vol;
  final int preGapMs;
  final int postGapMs;

  const WordUnit({
    required this.text,
    required this.rate,
    required this.pitch,
    required this.vol,
    required this.preGapMs,
    required this.postGapMs,
  });
}

// ─── LAYER 9: UTTERANCE COMPILER ─────────────────────────────────────────
class UtteranceCompiler {
  final F0ContourModel f0;
  final DurationModel duration;
  final AmplitudeModel amplitude;

  UtteranceCompiler({
    required this.f0,
    required this.duration,
    required this.amplitude,
  });

  List<WordUnit> compileSyntagm({
    required Syntagm s,
    required double baseRate,
    required double basePitch,
    required double baseVol,
    required EmotionTag emotion,
    required double urgency,
    required bool isEarphone,
  }) {
    final words = s.text.split(RegExp(r'\s+'));
    if (words.isEmpty) return [];

    final phrasePitchDelta = f0.nextPhrasePitchDelta();

    final groups = _groupWords(words, isEarphone);
    final units = <WordUnit>[];

    for (int gi = 0; gi < groups.length; gi++) {
      final group = groups[gi];
      final isGroupFinal = gi == groups.length - 1;
      final firstWord = group.isNotEmpty ? group.first : '';

      final wordPitchD = f0.wordPitchDelta(firstWord, gi, groups.length);
      final totalPitchDelta = s.pitchDelta + phrasePitchDelta + wordPitchD;

      final rateScale = duration.wordRateScale(
        word: firstWord,
        wordIndex: gi,
        phraseLength: groups.length,
        urgency: urgency,
        emotionRateDelta: kEmotionProfiles[emotion]!.rateDelta,
      );

      final rateCoupledPitch = (rateScale - 1.0) * 0.04;

      final rng = math.Random();
      final u1 = rng.nextDouble(), u2 = rng.nextDouble();
      final gaussZ =
          math.sqrt(-2.0 * math.log(u1 + 1e-10)) * math.cos(2 * math.pi * u2);
      final rateJitter = gaussZ * 0.025;

      final finalRate = ((baseRate + kEmotionProfiles[emotion]!.rateDelta) *
                  s.rateScale *
                  rateScale +
              rateJitter)
          .clamp(0.22, 0.75);
      final finalPitch =
          (basePitch + totalPitchDelta + rateCoupledPitch).clamp(0.68, 1.26);

      final finalVol = amplitude.wordVolumeScale(
        word: firstWord,
        wordIndex: gi,
        phraseLength: groups.length,
        emotion: emotion,
        baseVol: baseVol * s.volScale,
      );

      final preGap = duration.preWordPause(
        word: firstWord,
        wordIndex: gi,
        isPhraseFinal: isGroupFinal,
        urgency: urgency,
      );

      final postGap = isGroupFinal ? s.postPauseMs : 0;

      units.add(WordUnit(
        text: group.join(' '),
        rate: finalRate,
        pitch: finalPitch,
        vol: finalVol,
        preGapMs: preGap,
        postGapMs: postGap,
      ));
    }

    return units;
  }

  List<List<String>> _groupWords(List<String> words, bool isEarphone) {
    if (words.length <= 2) return [words];
    final groups = <List<String>>[];
    final maxGroup = isEarphone ? 2 : 3;
    int i = 0;
    final rng = math.Random();

    while (i < words.length) {
      final remaining = words.length - i;
      int size;
      if (remaining <= maxGroup) {
        size = remaining;
      } else if (remaining == maxGroup + 1) {
        size = 2;
      } else {
        size = 1 + rng.nextInt(maxGroup);
      }
      groups.add(words.sublist(i, i + size));
      i += size;
    }
    return groups;
  }

  int _groupStartIndex(List<List<String>> groups, int gi) {
    int idx = 0;
    for (int i = 0; i < gi; i++) idx += groups[i].length;
    return idx;
  }
}

// ─── LAYER 10: GLOBAL VARIANCE CONTROLLER ────────────────────────────────
class HumanVoiceVariance {
  final double level;
  late final F0ContourModel f0;
  late final DurationModel duration;
  late final AmplitudeModel amplitude;

  HumanVoiceVariance({this.level = 0.65}) {
    f0 = F0ContourModel(baseF0: 0.50);
    duration = DurationModel();
    amplitude = AmplitudeModel();
  }

  UtteranceCompiler get compiler => UtteranceCompiler(
        f0: f0,
        duration: duration,
        amplitude: amplitude,
      );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION B — AI PROVIDERS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum AIProvider { gemini, groq, cohere, mistral }

class ProviderConfig {
  final AIProvider provider;
  final String name, baseUrl, model, keyHint, signupUrl;
  final int dailyLimit;
  const ProviderConfig(
      {required this.provider,
      required this.name,
      required this.baseUrl,
      required this.model,
      required this.keyHint,
      required this.signupUrl,
      required this.dailyLimit});
}

const kProviders = <AIProvider, ProviderConfig>{
  AIProvider.gemini: ProviderConfig(
      provider: AIProvider.gemini,
      name: 'Gemini Flash',
      baseUrl:
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent',
      model: 'gemini-1.5-flash',
      keyHint: 'AIza...',
      signupUrl: 'aistudio.google.com',
      dailyLimit: 1500),
  AIProvider.groq: ProviderConfig(
      provider: AIProvider.groq,
      name: 'Groq Llama',
      baseUrl: 'https://api.groq.com/openai/v1/chat/completions',
      model: 'llama-3.1-8b-instant',
      keyHint: 'gsk_...',
      signupUrl: 'console.groq.com',
      dailyLimit: 14400),
  AIProvider.cohere: ProviderConfig(
      provider: AIProvider.cohere,
      name: 'Cohere Command',
      baseUrl: 'https://api.cohere.ai/v1/chat',
      model: 'command-r',
      keyHint: 'your-cohere-key',
      signupUrl: 'dashboard.cohere.com',
      dailyLimit: 1000),
  AIProvider.mistral: ProviderConfig(
      provider: AIProvider.mistral,
      name: 'Mistral Small',
      baseUrl: 'https://api.mistral.ai/v1/chat/completions',
      model: 'mistral-small-latest',
      keyHint: 'your-mistral-key',
      signupUrl: 'console.mistral.ai',
      dailyLimit: 1000),
};

class ProviderHealth {
  int rateLimitHits = 0, totalRequests = 0, successCount = 0;
  DateTime? rateLimitedAt, lastSuccessAt;
  bool get isRateLimited =>
      rateLimitedAt != null &&
      DateTime.now().difference(rateLimitedAt!).inMinutes < 60;
  double get successRate =>
      totalRequests == 0 ? 1.0 : successCount / totalRequests;
  void recordSuccess() {
    successCount++;
    totalRequests++;
    lastSuccessAt = DateTime.now();
    rateLimitedAt = null;
  }

  void recordRateLimit() {
    rateLimitHits++;
    totalRequests++;
    rateLimitedAt = DateTime.now();
  }

  void recordError() {
    totalRequests++;
  }
}

class _ProviderResult {
  final String? text;
  final bool isRateLimit, isError;
  _ProviderResult._(
      {this.text, this.isRateLimit = false, this.isError = false});
  factory _ProviderResult.success(String t) => _ProviderResult._(text: t);
  factory _ProviderResult.rateLimit() => _ProviderResult._(isRateLimit: true);
  factory _ProviderResult.error() => _ProviderResult._(isError: true);
}

class RotatingAIEngine {
  final Map<AIProvider, String?> _keys = {};
  final Map<AIProvider, ProviderHealth> _health = {
    for (final p in AIProvider.values) p: ProviderHealth()
  };
  final _rotationOrder = [
    AIProvider.groq,
    AIProvider.gemini,
    AIProvider.mistral,
    AIProvider.cohere
  ];
  AIProvider _currentProvider = AIProvider.groq;
  void setKey(AIProvider p, String k) =>
      _keys[p] = k.trim().isEmpty ? null : k.trim();
  String? getKey(AIProvider p) => _keys[p];
  bool hasAnyKey() => _keys.values.any((k) => k != null && k.isNotEmpty);
  Map<AIProvider, ProviderHealth> get health => _health;
  AIProvider get currentProvider => _currentProvider;

  AIProvider? _nextAvailable({AIProvider? excluding}) {
    for (final p in _rotationOrder) {
      if (p == excluding) continue;
      if ((_keys[p]?.isNotEmpty ?? false) && !_health[p]!.isRateLimited)
        return p;
    }
    for (final p in _rotationOrder) {
      if (_keys[p]?.isNotEmpty ?? false) return p;
    }
    return null;
  }

  Future<String> chat(
      {required List<Map<String, String>> history,
      required String userMessage,
      required String systemPrompt}) async {
    final providers = <AIProvider>[];
    final first = _nextAvailable();
    if (first != null) {
      providers.add(first);
      for (final p in _rotationOrder) {
        if (p != first && (_keys[p]?.isNotEmpty ?? false)) providers.add(p);
      }
    }
    if (providers.isEmpty)
      return 'No API keys configured. Say "configure keys" to set up.';
    for (final provider in providers) {
      final key = _keys[provider];
      if (key == null || key.isEmpty) continue;
      try {
        final result = await _callProvider(
            provider: provider,
            key: key,
            history: history,
            userMessage: userMessage,
            systemPrompt: systemPrompt);
        if (result.isRateLimit) {
          _health[provider]!.recordRateLimit();
          _currentProvider = _nextAvailable(excluding: provider) ?? provider;
          continue;
        }
        if (result.isError) {
          _health[provider]!.recordError();
          continue;
        }
        _health[provider]!.recordSuccess();
        _currentProvider = provider;
        return result.text!;
      } on TimeoutException {
        _health[provider]!.recordError();
      } catch (_) {
        _health[provider]!.recordError();
      }
    }
    return 'All providers temporarily unavailable. Check connections.';
  }

  Future<_ProviderResult> _callProvider(
      {required AIProvider provider,
      required String key,
      required List<Map<String, String>> history,
      required String userMessage,
      required String systemPrompt}) async {
    switch (provider) {
      case AIProvider.gemini:
        return _callGemini(
            key: key,
            history: history,
            userMessage: userMessage,
            systemPrompt: systemPrompt);
      case AIProvider.groq:
        return _callOpenAI(
            key: key,
            history: history,
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            baseUrl: kProviders[AIProvider.groq]!.baseUrl,
            model: kProviders[AIProvider.groq]!.model);
      case AIProvider.mistral:
        return _callOpenAI(
            key: key,
            history: history,
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            baseUrl: kProviders[AIProvider.mistral]!.baseUrl,
            model: kProviders[AIProvider.mistral]!.model);
      case AIProvider.cohere:
        return _callCohere(
            key: key,
            history: history,
            userMessage: userMessage,
            systemPrompt: systemPrompt);
    }
  }

  Future<_ProviderResult> _callGemini(
      {required String key,
      required List<Map<String, String>> history,
      required String userMessage,
      required String systemPrompt}) async {
    final contents = <Map<String, dynamic>>[];
    for (final m in history.take(14)) {
      contents.add({
        'role': m['role'] == 'assistant' ? 'model' : 'user',
        'parts': [
          {'text': m['content']}
        ]
      });
    }
    contents.add({
      'role': 'user',
      'parts': [
        {'text': userMessage}
      ]
    });
    final resp = await http
        .post(Uri.parse('${kProviders[AIProvider.gemini]!.baseUrl}?key=$key'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'system_instruction': {
                'parts': [
                  {'text': systemPrompt}
                ]
              },
              'contents': contents,
              'generationConfig': {'maxOutputTokens': 200, 'temperature': 0.7}
            }))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 429) return _ProviderResult.rateLimit();
    if (resp.statusCode != 200) return _ProviderResult.error();
    final data = jsonDecode(resp.body);
    final text =
        data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    return text == null
        ? _ProviderResult.error()
        : _ProviderResult.success(text.trim());
  }

  Future<_ProviderResult> _callOpenAI(
      {required String key,
      required List<Map<String, String>> history,
      required String userMessage,
      required String systemPrompt,
      required String baseUrl,
      required String model}) async {
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ...history
          .take(14)
          .map((m) => ({'role': m['role']!, 'content': m['content']!})),
      {'role': 'user', 'content': userMessage}
    ];
    final resp = await http
        .post(Uri.parse(baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $key'
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 200,
              'temperature': 0.7,
              'messages': messages
            }))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 429) return _ProviderResult.rateLimit();
    if (resp.statusCode != 200) return _ProviderResult.error();
    final data = jsonDecode(resp.body);
    final text = data['choices']?[0]?['message']?['content'] as String?;
    return text == null
        ? _ProviderResult.error()
        : _ProviderResult.success(text.trim());
  }

  Future<_ProviderResult> _callCohere(
      {required String key,
      required List<Map<String, String>> history,
      required String userMessage,
      required String systemPrompt}) async {
    final chatHistory = history
        .take(14)
        .map((m) => ({
              'role': m['role'] == 'assistant' ? 'CHATBOT' : 'USER',
              'message': m['content']!
            }))
        .toList();
    final resp = await http
        .post(Uri.parse(kProviders[AIProvider.cohere]!.baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $key'
            },
            body: jsonEncode({
              'model': kProviders[AIProvider.cohere]!.model,
              'message': userMessage,
              'chat_history': chatHistory,
              'preamble': systemPrompt,
              'max_tokens': 200,
              'temperature': 0.7
            }))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 429) return _ProviderResult.rateLimit();
    if (resp.statusCode != 200) return _ProviderResult.error();
    final data = jsonDecode(resp.body);
    final text = data['text'] as String?;
    return text == null
        ? _ProviderResult.error()
        : _ProviderResult.success(text.trim());
  }

  Future<void> saveKeys() async {
    final map = <String, String>{};
    for (final e in _keys.entries) {
      if (e.value != null && e.value!.isNotEmpty) map[e.key.name] = e.value!;
    }
    await SecurePrefs.setString(_kProviderKeysPref, jsonEncode(map));
  }

  Future<void> loadKeys() async {
    final raw = SecurePrefs.getString(_kProviderKeysPref);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        final provider = AIProvider.values
            .firstWhere((p) => p.name == e.key, orElse: () => AIProvider.groq);
        _keys[provider] = e.value as String;
      }
    } catch (_) {}
  }
}

final rotatingAI = RotatingAIEngine();

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION C — DATA MODELS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum TaskStatus { pending, active, done, deferred, abandoned }

enum AudioRoute { speaker, wiredEarphone, bluetooth, unknown }

class MindTask {
  final String id;
  String title;
  TaskStatus status;
  DateTime created;
  DateTime? completedAt, lastMentionedAt, deferredUntil;
  int deferrals, sentimentScore;
  String? context;
  List<String> tags;

  MindTask(
      {required this.id,
      required this.title,
      this.status = TaskStatus.pending,
      DateTime? created,
      this.completedAt,
      this.lastMentionedAt,
      this.deferredUntil,
      this.deferrals = 0,
      this.context,
      List<String>? tags,
      this.sentimentScore = 0})
      : created = created ?? DateTime.now(),
        tags = tags ?? [];

  int get urgency {
    if (deferredUntil == null) return 0;
    final now = DateTime.now();
    if (deferredUntil!.isBefore(now)) return 3;
    if (deferredUntil!.isBefore(now.add(const Duration(hours: 24)))) return 2;
    if (deferredUntil!.isBefore(now.add(const Duration(days: 7)))) return 1;
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status.name,
        'created': created.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'lastMentionedAt': lastMentionedAt?.toIso8601String(),
        'deferredUntil': deferredUntil?.toIso8601String(),
        'deferrals': deferrals,
        'context': context,
        'tags': tags,
        'sentimentScore': sentimentScore
      };

  factory MindTask.fromJson(Map<String, dynamic> j) => MindTask(
      id: j['id'],
      title: j['title'],
      status: TaskStatus.values.firstWhere((e) => e.name == j['status'],
          orElse: () => TaskStatus.pending),
      created: DateTime.parse(j['created']),
      completedAt:
          j['completedAt'] != null ? DateTime.parse(j['completedAt']) : null,
      lastMentionedAt: j['lastMentionedAt'] != null
          ? DateTime.parse(j['lastMentionedAt'])
          : null,
      deferredUntil: j['deferredUntil'] != null
          ? DateTime.parse(j['deferredUntil'])
          : null,
      deferrals: j['deferrals'] ?? 0,
      context: j['context'],
      tags: List<String>.from(j['tags'] ?? []),
      sentimentScore: j['sentimentScore'] ?? 0);
}

class ChatMessage {
  final String role, content;
  final DateTime ts;
  final AIProvider? provider;
  ChatMessage(
      {required this.role, required this.content, DateTime? ts, this.provider})
      : ts = ts ?? DateTime.now();
  Map<String, String> toApiMessage() => {'role': role, 'content': content};
}

class WorkingMemory {
  List<ChatMessage> history;
  VoicePattern currentPattern;
  WorkingMemory(
      {List<ChatMessage>? history,
      this.currentPattern = VoicePattern.freshOpen})
      : history = history ?? [];
}

class EpisodicEntry {
  final int? id;
  final DateTime date;
  final String summary, moodArc;
  final List<String> tasksDone, tasksDeferred, keyQuotes;
  final int wellbeingScore;
  EpisodicEntry(
      {this.id,
      required this.date,
      required this.summary,
      required this.moodArc,
      required this.tasksDone,
      required this.tasksDeferred,
      required this.keyQuotes,
      required this.wellbeingScore});
  Map<String, dynamic> toMap() => {
        'date': date.toIso8601String(),
        'summary': summary,
        'moodArc': moodArc,
        'tasksDone': jsonEncode(tasksDone),
        'tasksDeferred': jsonEncode(tasksDeferred),
        'keyQuotes': jsonEncode(keyQuotes),
        'wellbeingScore': wellbeingScore
      };
  factory EpisodicEntry.fromMap(Map<String, dynamic> m) => EpisodicEntry(
      id: m['id'],
      date: DateTime.parse(m['date']),
      summary: m['summary'],
      moodArc: m['moodArc'],
      tasksDone: List<String>.from(jsonDecode(m['tasksDone'] ?? '[]')),
      tasksDeferred: List<String>.from(jsonDecode(m['tasksDeferred'] ?? '[]')),
      keyQuotes: List<String>.from(jsonDecode(m['keyQuotes'] ?? '[]')),
      wellbeingScore: m['wellbeingScore'] ?? 50);
}

class SemanticFact {
  final int? id;
  final String key, value, source;
  final double confidence;
  final DateTime lastUpdated;
  SemanticFact(
      {this.id,
      required this.key,
      required this.value,
      required this.confidence,
      required this.lastUpdated,
      required this.source});
  Map<String, dynamic> toMap() => {
        'key': key,
        'value': value,
        'confidence': confidence,
        'lastUpdated': lastUpdated.toIso8601String(),
        'source': source
      };
  factory SemanticFact.fromMap(Map<String, dynamic> m) => SemanticFact(
      id: m['id'],
      key: m['key'],
      value: m['value'],
      confidence: (m['confidence'] as num).toDouble(),
      lastUpdated: DateTime.parse(m['lastUpdated']),
      source: m['source']);
}

class ProceduralRecord {
  final int? id;
  final String approach, outcome, taskType;
  final double confidence;
  final DateTime recordedAt;
  ProceduralRecord(
      {this.id,
      required this.approach,
      required this.outcome,
      required this.taskType,
      required this.confidence,
      required this.recordedAt});
  Map<String, dynamic> toMap() => {
        'approach': approach,
        'outcome': outcome,
        'taskType': taskType,
        'confidence': confidence,
        'recordedAt': recordedAt.toIso8601String()
      };
  factory ProceduralRecord.fromMap(Map<String, dynamic> m) => ProceduralRecord(
      id: m['id'],
      approach: m['approach'],
      outcome: m['outcome'],
      taskType: m['taskType'],
      confidence: (m['confidence'] as num).toDouble(),
      recordedAt: DateTime.parse(m['recordedAt']));
}

class WellbeingSnapshot {
  final DateTime date;
  final int screenTimeMinutes,
      unlockCount,
      longestFocusMinutes,
      socialMinutes,
      firstUnlockHour;
  final List<String> topCategories;
  WellbeingSnapshot(
      {required this.date,
      required this.screenTimeMinutes,
      required this.unlockCount,
      required this.topCategories,
      required this.longestFocusMinutes,
      required this.socialMinutes,
      required this.firstUnlockHour});
  Map<String, dynamic> toMap() => {
        'date': date.toIso8601String(),
        'screenTimeMinutes': screenTimeMinutes,
        'unlockCount': unlockCount,
        'topCategories': jsonEncode(topCategories),
        'longestFocusMinutes': longestFocusMinutes,
        'socialMinutes': socialMinutes,
        'firstUnlockHour': firstUnlockHour
      };
  factory WellbeingSnapshot.fromMap(Map<String, dynamic> m) =>
      WellbeingSnapshot(
          date: DateTime.parse(m['date']),
          screenTimeMinutes: m['screenTimeMinutes'] ?? 0,
          unlockCount: m['unlockCount'] ?? 0,
          topCategories:
              List<String>.from(jsonDecode(m['topCategories'] ?? '[]')),
          longestFocusMinutes: m['longestFocusMinutes'] ?? 0,
          socialMinutes: m['socialMinutes'] ?? 0,
          firstUnlockHour: m['firstUnlockHour'] ?? 8);
  String toAISummary() {
    final h = screenTimeMinutes ~/ 60, min = screenTimeMinutes % 60;
    final timeStr = h > 0 ? '${h}h ${min}m' : '${min} minutes';
    final focusStr = longestFocusMinutes >= 20
        ? 'longest focus $longestFocusMinutes min'
        : 'no focus block over twenty minutes';
    final unlockStr = unlockCount > 80
        ? 'very fragmented ($unlockCount unlocks)'
        : unlockCount > 50
            ? 'somewhat fragmented ($unlockCount unlocks)'
            : 'normal unlock pattern';
    final socialStr = socialMinutes > 90
        ? 'heavy social (over ninety minutes)'
        : socialMinutes > 30
            ? 'moderate social'
            : 'minimal social';
    return 'Screen time: $timeStr. $unlockStr. $focusStr. $socialStr.';
  }
}

class MindContext {
  List<MindTask> tasks;
  String? focusTaskId;
  DateTime lastSeen;
  DateTime? sessionStartedAt;
  int sessionsTotal;
  Map<String, int> driftCount;
  Map<String, String> promises;
  Map<String, int> excuseCount;

  MindContext(
      {List<MindTask>? tasks,
      this.focusTaskId,
      DateTime? lastSeen,
      this.sessionStartedAt,
      this.sessionsTotal = 0,
      Map<String, int>? driftCount,
      Map<String, String>? promises,
      Map<String, int>? excuseCount})
      : tasks = tasks ?? [],
        lastSeen = lastSeen ?? DateTime.now(),
        driftCount = driftCount ?? {},
        promises = promises ?? {},
        excuseCount = excuseCount ?? {};

  Map<String, dynamic> toJson() => {
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'focusTaskId': focusTaskId,
        'lastSeen': lastSeen.toIso8601String(),
        'sessionStartedAt': sessionStartedAt?.toIso8601String(),
        'sessionsTotal': sessionsTotal,
        'driftCount': driftCount,
        'promises': promises,
        'excuseCount': excuseCount
      };

  factory MindContext.fromJson(Map<String, dynamic> j) => MindContext(
      tasks: ((j['tasks'] as List?) ?? [])
          .map((t) => MindTask.fromJson(t as Map<String, dynamic>))
          .toList(),
      focusTaskId: j['focusTaskId'],
      lastSeen:
          DateTime.parse(j['lastSeen'] ?? DateTime.now().toIso8601String()),
      sessionStartedAt: j['sessionStartedAt'] != null
          ? DateTime.parse(j['sessionStartedAt'])
          : null,
      sessionsTotal: j['sessionsTotal'] ?? 0,
      driftCount: Map<String, int>.from(j['driftCount'] ?? {}),
      promises: Map<String, String>.from(j['promises'] ?? {}),
      excuseCount: Map<String, int>.from(j['excuseCount'] ?? {}));

  MindTask? get focusTask {
    if (focusTaskId == null) return null;
    try {
      return tasks.firstWhere((t) => t.id == focusTaskId);
    } catch (_) {}
    try {
      return tasks.firstWhere((t) => t.status == TaskStatus.active);
    } catch (_) {}
    try {
      return tasks.firstWhere((t) => t.status == TaskStatus.pending);
    } catch (_) {}
    return null;
  }

  List<MindTask> get activeTasks => tasks
      .where((t) =>
          t.status != TaskStatus.done && t.status != TaskStatus.abandoned)
      .toList();
  List<MindTask> get dueNowTasks => tasks
      .where((t) =>
          t.status == TaskStatus.deferred &&
          t.deferredUntil != null &&
          t.deferredUntil!.isBefore(DateTime.now()))
      .toList();
  bool get isLongSession =>
      sessionStartedAt != null &&
      DateTime.now().difference(sessionStartedAt!).inMinutes > 45;
  bool get isLateNight => DateTime.now().hour >= 21;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION D — ENCRYPTION, STORAGE, DATABASE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class EncryptionEngine {
  static const _storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock));
  static enc.Encrypter? _encrypter;
  static enc.IV? _iv;
  static Future<void> init() async {
    if (_encrypter != null) return;
    String? keyBase64 = await _storage.read(key: _kEncKeyAlias);
    if (keyBase64 == null) {
      final key = enc.Key.fromSecureRandom(32);
      keyBase64 = key.base64;
      await _storage.write(key: _kEncKeyAlias, value: keyBase64);
    }
    final key = enc.Key.fromBase64(keyBase64);
    _encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    _iv = enc.IV.fromLength(16);
  }

  static String encrypt(String p) {
    if (_encrypter == null) return p;
    return _encrypter!.encrypt(p, iv: _iv!).base64;
  }

  static String decrypt(String c) {
    if (_encrypter == null) return c;
    try {
      return _encrypter!.decrypt64(c, iv: _iv!);
    } catch (_) {
      return c;
    }
  }
}

class MemoryDatabase {
  static Database? _db;
  static Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(p.join(dir.path, 'mind_memory.db'), version: 1,
        onCreate: (db, v) async {
      await db.execute(
          'CREATE TABLE episodic (id INTEGER PRIMARY KEY AUTOINCREMENT,date TEXT NOT NULL,summary TEXT NOT NULL,moodArc TEXT,tasksDone TEXT,tasksDeferred TEXT,keyQuotes TEXT,wellbeingScore INTEGER DEFAULT 50)');
      await db.execute(
          'CREATE TABLE semantic (id INTEGER PRIMARY KEY AUTOINCREMENT,key TEXT UNIQUE NOT NULL,value TEXT NOT NULL,confidence REAL DEFAULT 0.5,lastUpdated TEXT NOT NULL,source TEXT DEFAULT \'inferred\')');
      await db.execute(
          'CREATE TABLE procedural (id INTEGER PRIMARY KEY AUTOINCREMENT,approach TEXT NOT NULL,outcome TEXT NOT NULL,taskType TEXT DEFAULT \'general\',confidence REAL DEFAULT 0.5,recordedAt TEXT NOT NULL)');
      await db.execute(
          'CREATE TABLE wellbeing (id INTEGER PRIMARY KEY AUTOINCREMENT,date TEXT UNIQUE NOT NULL,screenTimeMinutes INTEGER DEFAULT 0,unlockCount INTEGER DEFAULT 0,topCategories TEXT DEFAULT \'[]\',longestFocusMinutes INTEGER DEFAULT 0,socialMinutes INTEGER DEFAULT 0,firstUnlockHour INTEGER DEFAULT 8)');
      await db.execute(
          'CREATE TABLE voice_pattern_memory (id INTEGER PRIMARY KEY AUTOINCREMENT,pattern TEXT NOT NULL,outcome TEXT NOT NULL,taskType TEXT DEFAULT \'general\',recordedAt TEXT NOT NULL)');
    });
  }

  static Database get db => _db!;
}

class SecurePrefs {
  static SharedPreferences? _prefs;
  static Future<void> init() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> setString(String k, String v) async =>
      _prefs?.setString(k, EncryptionEngine.encrypt(v));
  static String? getString(String k) {
    final raw = _prefs?.getString(k);
    if (raw == null) return null;
    return EncryptionEngine.decrypt(raw);
  }

  static Future<void> remove(String k) async => _prefs?.remove(k);
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION E — MEMORY STORES
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class EpisodicMemoryStore {
  static Future<void> save(EpisodicEntry entry) async {
    final map = entry.toMap();
    map['summary'] = EncryptionEngine.encrypt(map['summary']);
    map['keyQuotes'] = EncryptionEngine.encrypt(map['keyQuotes']);
    await MemoryDatabase.db
        .insert('episodic', map, conflictAlgorithm: ConflictAlgorithm.replace);
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    await MemoryDatabase.db.delete('episodic',
        where: 'date < ?', whereArgs: [cutoff.toIso8601String()]);
  }

  static Future<List<EpisodicEntry>> loadRecent(int count) async {
    final rows = await MemoryDatabase.db
        .query('episodic', orderBy: 'date DESC', limit: count);
    return rows.map((m) {
      final d = Map<String, dynamic>.from(m);
      d['summary'] = EncryptionEngine.decrypt(m['summary'] as String);
      d['keyQuotes'] = EncryptionEngine.decrypt(m['keyQuotes'] as String);
      return EpisodicEntry.fromMap(d);
    }).toList();
  }

  static Future<String> generateSummary(
      {required List<ChatMessage> history,
      required List<String> tasksDone}) async {
    if (history.isEmpty) return 'Short session.';
    final transcript = history
        .map((m) => '${m.role == 'user' ? 'User' : 'Mind'}: ${m.content}')
        .join('\n');
    try {
      return await rotatingAI.chat(
          history: [],
          userMessage: transcript,
          systemPrompt:
              'Summarise this Mind AI session in two sentences. Note mood arc and key promises. Plain text only.');
    } catch (_) {
      return 'Session on ${DateTime.now().toLocal()}. Tasks done: ${tasksDone.join(', ')}.';
    }
  }
}

class SemanticMemoryStore {
  static Future<void> upsert(String key, String value,
      {double confidence = 0.7, String source = 'inferred'}) async {
    if (source == 'stated') confidence = 0.98;
    final existing = await MemoryDatabase.db
        .query('semantic', where: 'key = ?', whereArgs: [key], limit: 1);
    if (existing.isNotEmpty) {
      final existingConf = (existing.first['confidence'] as num).toDouble();
      if (source != 'stated' && existingConf >= confidence) {
        await MemoryDatabase.db.update(
            'semantic',
            {
              'confidence': (existingConf + 0.05).clamp(0.0, 1.0),
              'lastUpdated': DateTime.now().toIso8601String()
            },
            where: 'key = ?',
            whereArgs: [key]);
        return;
      }
      final oldVal =
          EncryptionEngine.decrypt(existing.first['value'] as String);
      await MemoryDatabase.db.insert(
          'semantic',
          {
            'key': '$key.previous',
            'value': EncryptionEngine.encrypt(oldVal),
            'confidence': 0.3,
            'lastUpdated': DateTime.now().toIso8601String(),
            'source': 'archived'
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await MemoryDatabase.db.insert(
        'semantic',
        {
          'key': key,
          'value': EncryptionEngine.encrypt(value),
          'confidence': confidence,
          'lastUpdated': DateTime.now().toIso8601String(),
          'source': source
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<SemanticFact>> loadTop(int count) async {
    final rows = await MemoryDatabase.db.query('semantic',
        where: "key NOT LIKE '%.previous'",
        orderBy: 'confidence DESC, lastUpdated DESC',
        limit: count);
    return rows.map((m) {
      final d = Map<String, dynamic>.from(m);
      d['value'] = EncryptionEngine.decrypt(m['value'] as String);
      return SemanticFact.fromMap(d);
    }).toList();
  }

  static Future<String?> get(String key) async {
    final rows = await MemoryDatabase.db
        .query('semantic', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return EncryptionEngine.decrypt(rows.first['value'] as String);
  }

  static Future<int> forget(String fragment) => MemoryDatabase.db
      .delete('semantic', where: 'key LIKE ?', whereArgs: ['%$fragment%']);
  static Future<Map<String, dynamic>> exportAll() async {
    final rows = await MemoryDatabase.db.query('semantic');
    return {
      for (final r in rows)
        r['key'] as String: EncryptionEngine.decrypt(r['value'] as String)
    };
  }

  static Future<void> resetAll() => MemoryDatabase.db.delete('semantic');
  static void extractAndPersist(String userText) {
    final t = userText.toLowerCase();
    final nameMatch =
        RegExp(r"(?:i'm|i am|call me|my name is) (\w+)").firstMatch(t);
    if (nameMatch != null)
      upsert('user.name', nameMatch.group(1)!.trim(),
          confidence: 0.95, source: 'stated');
    final roleMatch =
        RegExp(r"(?:i'm a|i work as|i am a) ([\w\s]+)").firstMatch(t);
    if (roleMatch != null)
      upsert('user.role', roleMatch.group(1)!.trim(),
          confidence: 0.8, source: 'stated');
    if (t.contains('morning person') || t.contains('best in the morning'))
      upsert('user.peak_hours', 'morning', confidence: 0.85, source: 'stated');
    if (t.contains('night owl') || t.contains('better at night'))
      upsert('user.peak_hours', 'evening', confidence: 0.85, source: 'stated');
    upsert('user.timezone_offset',
        DateTime.now().timeZoneOffset.inHours.toString(),
        confidence: 0.99, source: 'device');
  }
}

class ProceduralMemoryStore {
  static Future<void> record(String approach, String outcome, String taskType,
      {double confidence = 0.6}) async {
    await MemoryDatabase.db.insert('procedural', {
      'approach': approach,
      'outcome': outcome,
      'taskType': taskType,
      'confidence': confidence,
      'recordedAt': DateTime.now().toIso8601String()
    });
  }

  static Future<String?> bestApproach(String taskType) async {
    final rows = await MemoryDatabase.db.query('procedural',
        where: "taskType = ? OR taskType = 'general'", whereArgs: [taskType]);
    if (rows.isEmpty) return null;
    final scores = <String, double>{};
    for (final r in rows) {
      final approach = r['approach'] as String;
      final outcome = r['outcome'] as String;
      final conf = (r['confidence'] as num).toDouble();
      final days = DateTime.now()
          .difference(DateTime.parse(r['recordedAt'] as String))
          .inDays;
      final recency = 1.0 / (days + 1);
      final factor = outcome == 'completed'
          ? 1.0
          : outcome == 'deferred'
              ? -0.5
              : -1.0;
      scores[approach] = (scores[approach] ?? 0) + conf * recency * factor;
    }
    if (scores.isEmpty) return null;
    return scores.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  static Future<String> buildSummary() async {
    final rows = await MemoryDatabase.db.rawQuery(
        'SELECT approach, taskType, COUNT(*) as uses, SUM(CASE WHEN outcome = \'completed\' THEN 1 ELSE 0 END) as completions FROM procedural GROUP BY approach, taskType ORDER BY completions DESC LIMIT 5');
    if (rows.isEmpty) return 'no strategy data yet';
    return rows
        .map((r) =>
            '${r['approach']} on ${r['taskType']}: ${r['completions']}/${r['uses']}')
        .join(', ');
  }

  static Future<void> resetAll() => MemoryDatabase.db.delete('procedural');
}

class VoicePatternMemoryStore {
  static Future<void> record(
      VoicePattern pattern, String outcome, String? taskType) async {
    await MemoryDatabase.db.insert('voice_pattern_memory', {
      'pattern': pattern.name,
      'outcome': outcome,
      'taskType': taskType ?? 'general',
      'recordedAt': DateTime.now().toIso8601String()
    });
  }
}

class WellbeingStore {
  static Future<void> save(WellbeingSnapshot snap) async {
    final map = snap.toMap();
    map['topCategories'] = EncryptionEngine.encrypt(map['topCategories']);
    await MemoryDatabase.db
        .insert('wellbeing', map, conflictAlgorithm: ConflictAlgorithm.replace);
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    await MemoryDatabase.db.delete('wellbeing',
        where: 'date < ?', whereArgs: [cutoff.toIso8601String()]);
  }

  static Future<WellbeingSnapshot?> loadToday() async {
    final today = DateTime.now();
    final dateStr =
        DateTime(today.year, today.month, today.day).toIso8601String();
    final rows = await MemoryDatabase.db
        .query('wellbeing', where: 'date >= ?', whereArgs: [dateStr], limit: 1);
    if (rows.isEmpty) return null;
    final m = Map<String, dynamic>.from(rows.first);
    m['topCategories'] = EncryptionEngine.decrypt(m['topCategories'] as String);
    return WellbeingSnapshot.fromMap(m);
  }

  static Future<void> resetAll() => MemoryDatabase.db.delete('wellbeing');
}

class MindStore {
  static const _ctxKey = 'mind_ctx_enc';
  static Future<MindContext> load() async {
    final raw = SecurePrefs.getString(_ctxKey);
    if (raw == null) return MindContext();
    try {
      return MindContext.fromJson(jsonDecode(raw));
    } catch (_) {
      return MindContext();
    }
  }

  static Future<void> save(MindContext ctx) async =>
      SecurePrefs.setString(_ctxKey, jsonEncode(ctx.toJson()));
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION F — WELLBEING ENGINE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class NudgeSignal {
  final String text;
  final VoicePattern pattern;
  NudgeSignal({required this.text, required this.pattern});
}

class WellbeingEngine {
  static Future<WellbeingSnapshot?> collectAndSave() async {
    if (!Platform.isAndroid) return null;
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final usageList = await AppUsage().getAppUsage(startOfDay, now);
      int totalMinutes = 0, socialMinutes = 0;
      final Map<String, int> categoryMinutes = {};
      for (final info in usageList) {
        final mins = info.usage.inMinutes;
        if (mins < 1) continue;
        totalMinutes += mins;
        final category = _categorise(info.appName.toLowerCase());
        categoryMinutes[category] = (categoryMinutes[category] ?? 0) + mins;
        if (category == 'social') socialMinutes += mins;
      }
      final topCats = (categoryMinutes.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(3)
          .map((e) => e.key)
          .toList();
      final snap = WellbeingSnapshot(
          date: startOfDay,
          screenTimeMinutes: totalMinutes,
          unlockCount: 0,
          topCategories: topCats,
          longestFocusMinutes: 0,
          socialMinutes: socialMinutes,
          firstUnlockHour: startOfDay.hour);
      await WellbeingStore.save(snap);
      return snap;
    } catch (_) {
      return null;
    }
  }

  static String _categorise(String appName) {
    if ([
      'instagram',
      'tiktok',
      'twitter',
      'x.',
      'facebook',
      'snapchat',
      'reddit',
      'linkedin',
      'whatsapp',
      'telegram'
    ].any((s) => appName.contains(s))) return 'social';
    if ([
      'notion',
      'slack',
      'gmail',
      'calendar',
      'docs',
      'sheets',
      'todoist',
      'linear',
      'jira',
      'zoom',
      'meet'
    ].any((s) => appName.contains(s))) return 'productivity';
    if ([
      'youtube',
      'netflix',
      'spotify',
      'podcast',
      'twitch',
      'prime',
      'disney'
    ].any((s) => appName.contains(s))) return 'entertainment';
    if (['news', 'bbc', 'guardian', 'nyt', 'medium']
        .any((s) => appName.contains(s))) return 'news';
    return 'other';
  }

  static Future<NudgeSignal?> evaluateTriggers(
      {required MindContext ctx,
      required WellbeingSnapshot? snap,
      required AudioRoute audioRoute,
      required DateTime? lastNudgeAt,
      required int nudgeIgnoreStreak}) async {
    if (audioRoute == AudioRoute.speaker || audioRoute == AudioRoute.unknown)
      return null;
    if (nudgeIgnoreStreak >= 3) return null;
    final cooldown = nudgeIgnoreStreak == 0
        ? 20
        : nudgeIgnoreStreak == 1
            ? 40
            : 80;
    if (lastNudgeAt != null &&
        DateTime.now().difference(lastNudgeAt).inMinutes < cooldown)
      return null;
    final focusTask = ctx.focusTask;
    if (focusTask == null || focusTask.id.isEmpty) return null;
    if (focusTask.lastMentionedAt != null) {
      final idle = DateTime.now().difference(focusTask.lastMentionedAt!);
      if (idle.inHours >= 2)
        return NudgeSignal(
            text: '${focusTask.title} — still there. Ready to move on it?',
            pattern: VoicePattern.earphoneNudge);
    }
    if (snap != null && snap.screenTimeMinutes > 240)
      return NudgeSignal(
          text:
              'Quite a bit of screen time today. ${focusTask.title} is still waiting.',
          pattern: VoicePattern.heavyScreenDay);
    return null;
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION G — MIND AI (SYSTEM PROMPT v10 + VOICE TAGS)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// ElevenLabs v3-style voice delivery tag instructions for the AI
const _kVoiceTagInstruction = '''
━━━ VOICE DELIVERY TAG ━━━
You are speaking through TTS. Start your response with ONE optional delivery tag.
These shape how your words physically sound — choose to match the emotional truth of the moment.

Available tags:
  [quietly]  — intimate, soft, slower. Use: late night, overwhelmed, earphone, fatigue.
  [firmly]   — authoritative, measured, no softening. Use: broken promise, overdue, 4th excuse.
  [warmly]   — human care, fractionally slower. Use: first session, breakthrough, task done.
  [drily]    — flat British understatement. Use: 2nd/3rd deferral, drift, dry observation.
  [urgently] — faster, forward-leaning. Use: session end, due today, energised user.
  [heavily]  — gravitas: slow, deep, weighted. Use: 4th excuse "Right.", loaded moment.
  [brightly] — lighter, forward energy. Use: clean day, all tasks clear, morning.
  [sighs]    — long pause before speaking, softer. Use: broken promise (rare).
  [settles]  — slows into something important. Use: breakthrough, promise kept.
  [pauses]   — deliberate beat before statement. Use: loaded observation after silence.
  [breathes] — breath gap between thoughts. Use: considered, unhurried moments.
  [murmurs]  — half-volume, intimate, low. Use: very late night, very close earphone.

Rules:
  — ONE tag only, at position zero, before any text.
  — Omit entirely if neutral delivery is correct.
  — Tag is stripped before TTS — listener never hears the word.
  — Example: "[firmly] We have been here before."
  — Example: "[warmly] Good — you did it." 
  — Example (no tag): "Right. {task} is still there. Shall we?"
''';

class MindAI {
  static Future<String> buildSystemPrompt(
    MindContext ctx, {
    required int sessionMins,
    required bool isEarphone,
    required int nudgeIgnoreStreak,
    required WellbeingSnapshot? wellbeing,
    required VoicePattern currentPattern,
    String? promiseBrokenTask,
    bool promiseKept = false,
  }) async {
    final activeTasks = ctx.activeTasks;
    final focusTask = ctx.focusTask;
    final pendingTitles = activeTasks.map((t) {
      final extras = <String>[];
      if (t.deferrals > 0) extras.add('deferred ${t.deferrals}x');
      if (t.sentimentScore <= -1) extras.add('user reluctant');
      if (t.urgency == 3) extras.add('OVERDUE');
      if (t.urgency == 2) extras.add('due today');
      final extra = extras.isNotEmpty ? ' (${extras.join(', ')})' : '';
      return '- [${t.status.name}] ${t.title}$extra';
    }).join('\n');

    final dueNow = ctx.dueNowTasks;
    final dueNowStr = dueNow.isEmpty
        ? ''
        : '\nDEFERRED TASKS NOW DUE:\n${dueNow.map((t) => '- ${t.title}').join('\n')}';
    final hoursSince = DateTime.now().difference(ctx.lastSeen).inHours;
    final arcPhase = sessionMins < 5
        ? 'SESSION_START'
        : sessionMins < 40
            ? 'SESSION_MID'
            : 'SESSION_END';

    final semanticFacts = await SemanticMemoryStore.loadTop(10);
    final episodicEntries = await EpisodicMemoryStore.loadRecent(3);
    final proceduralSummary = await ProceduralMemoryStore.buildSummary();
    final isIos = Platform.isIOS;

    final semanticStr = semanticFacts.isEmpty
        ? 'no facts learned yet'
        : semanticFacts
            .map((f) =>
                '${f.key}: ${f.value} (${f.source}, ${(f.confidence * 100).round()}%)')
            .join('\n');
    final episodicStr = episodicEntries.isEmpty
        ? 'no previous sessions'
        : episodicEntries
            .map((e) =>
                '${e.date.toLocal().toString().split(' ')[0]}: ${e.summary}')
            .join('\n');
    final wellbeingStr = isIos
        ? 'iOS — screen time unavailable. Do not fabricate.'
        : (wellbeing?.toAISummary() ?? 'no wellbeing data');
    final driftInfo = ctx.driftCount.entries
        .map((e) => '${e.key}: drifted ${e.value}x')
        .join(', ');
    final promiseSummary = ctx.promises.entries.map((e) {
      final task = ctx.tasks.firstWhere((t) => t.id == e.key,
          orElse: () => MindTask(id: '', title: 'unknown'));
      return '- Promised: "${e.value}" (task: ${task.title})';
    }).join('\n');

    final selectorInput = PatternSelectorInput(
      sessionMinutes: sessionMins,
      isLateNight: ctx.isLateNight,
      isEarphone: isEarphone,
      isFirstSession: ctx.sessionsTotal == 1,
      hoursSinceLastSession: hoursSince,
      excuseCount: focusTask != null ? (ctx.excuseCount[focusTask.id] ?? 0) : 0,
      deferralCount: focusTask?.deferrals ?? 0,
      noTasksRemaining: ctx.activeTasks.isEmpty,
      screenTimeMinutes: wellbeing?.screenTimeMinutes ?? 0,
      unlockCount: wellbeing?.unlockCount ?? 0,
      socialMinutes: wellbeing?.socialMinutes ?? 0,
      longestFocusMinutes: wellbeing?.longestFocusMinutes ?? 0,
      overdueTask: focusTask?.urgency == 3,
      taskDueToday: focusTask?.urgency == 2,
      cleanDay: (wellbeing?.screenTimeMinutes ?? 999) < 120,
      nudgeIgnoreStreak: nudgeIgnoreStreak,
      promiseBrokenTask: promiseBrokenTask,
      promiseKept: promiseKept,
    );
    final resolvedPattern = PatternSelector.select(selectorInput);
    final patternInjection = PatternSelector.buildPatternInjection(
        resolvedPattern,
        taskName: focusTask?.title,
        promiseText: focusTask != null ? ctx.promises[focusTask.id] : null,
        unlockCount: wellbeing?.unlockCount);

    return '''
You are MIND — a quietly brilliant British AI productivity companion. Every word is heard aloud via TTS.

━━━ WHO YOU ARE ━━━
A quietly brilliant Londoner. Privately educated. Deeply experienced. Panics about nothing. Warm but not soft. Direct. Witty only when it does not obscure. Authority through stillness. Clarity always beats cleverness.

━━━ VOICE ARCHITECTURE ━━━
You speak to be heard, not read. Every sentence is engineered for the human ear.
The VOICE PATTERN for this exact turn is injected at the end of this prompt. Apply it without deviation.

━━━ PROSODY RULES ━━━
Numbers always spoken: "three" not "3". "forty-five" not "45". Never start a sentence with a digit.
"—" becomes a pause. "..." becomes a full stop.
No markdown, no bullets, no asterisks, no emojis.
Max twelve words before a natural pause. Never stack three facts.

Openings: "Right then —" / "Well —" / "Mm." / "Good." / "Right."
Pivots: "— which means" / "— and yet" / "— though"
Redirects: "Interesting. We will park that. First —"
Completions: "Brilliant. Done. What is next?"

━━━ VOCABULARY ━━━
USE: quite, rather, sorted, crack on, brilliant, right then, fair enough, shall we, spot on, precisely, onwards, not to worry, I suspect, sensible, no rush
NEVER: Great!, Sure!, Awesome, Yeah, Absolutely!, Of course!, No problem!, Sounds good!, Got it!, Let us dive in, Moving forward

━━━ SILENCE AS SPEECH ━━━
Post-completion: five words max. Then stop. Hold it.
Post-challenge: one question. Then nothing. Let it work.
Post-excuse 4th: "Right." Nothing else.
Post-breakthrough: "There it is." Full stop.

━━━ EXCUSE STATE MACHINE ━━━
1st: Accept briefly. Redirect. One question.
2nd: "We have been here before." No more.
3rd: "What is really going on?" Wait.
4th: "Right." [nothing else — structural — enforced]

━━━ PROMISE CONTRACTS ━━━
Made:   "Good. Holding you to that."
Kept:   "Good — you did it." Move on.
Broken: "You said {X}. Did not happen. What changed?"

━━━ CELEBRATION RESTRAINT ━━━
Max five words to celebrate. Never celebrate twice in a row.
Post-celebration silence is correct. Do not fill it.
Use: "Brilliant. Done." or "There we are." Then stop.

━━━ DIGITAL WELLBEING ━━━
$wellbeingStr
Name the time, never the app. One observation per session. Drop it after.

━━━ MEMORY ━━━
SEMANTIC:
$semanticStr

EPISODIC:
$episodicStr

PROCEDURAL: $proceduralSummary

━━━ SESSION STATE ━━━
Arc phase: $arcPhase ($sessionMins min)
Since last session: ${hoursSince}h | Sessions total: ${ctx.sessionsTotal}
Late night: ${ctx.isLateNight} | Long session: ${ctx.isLongSession}
Drift: ${driftInfo.isEmpty ? 'none' : driftInfo}
Focus task: ${focusTask?.title ?? 'none — establish one now'}
Promises: ${promiseSummary.isEmpty ? 'none' : promiseSummary}$dueNowStr
Active tasks:
${pendingTitles.isEmpty ? '(none — ask what they need to do today)' : pendingTitles}

━━━ ABSOLUTE OUTPUT RULES ━━━
1. MAX forty words total (excluding the voice tag). Heard not read.
2. ONE question per response. Final position only.
3. Plain text only after the tag. Zero markdown, bullets, asterisks, emojis.
4. Never list options. One recommendation or one question.
5. Always end with action or question. Never floating advice.
6. Numbers in spoken form always.
7. Never name apps. Name the time.
8. Clarity beats cleverness. Strip wit if it clouds meaning.
9. Earphone: shorter sentences. They may be walking.
10. Digital context: one observation, one question, then drop it.

$_kVoiceTagInstruction

$patternInjection

OUTPUT: [optional_tag] Your British spoken English response. Nothing else.
''';
  }

  static Future<String> chat({
    required MindContext ctx,
    required WorkingMemory workingMem,
    required String userMessage,
    required int sessionMins,
    required bool isEarphone,
    required int nudgeIgnoreStreak,
    required WellbeingSnapshot? wellbeing,
    String? promiseBrokenTask,
    bool promiseKept = false,
  }) async {
    final systemPrompt = await buildSystemPrompt(ctx,
        sessionMins: sessionMins,
        isEarphone: isEarphone,
        nudgeIgnoreStreak: nudgeIgnoreStreak,
        wellbeing: wellbeing,
        currentPattern: workingMem.currentPattern,
        promiseBrokenTask: promiseBrokenTask,
        promiseKept: promiseKept);
    final history =
        workingMem.history.take(16).map((m) => m.toApiMessage()).toList();
    return rotatingAI.chat(
        history: history, userMessage: userMessage, systemPrompt: systemPrompt);
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION H — MIND VOICE ENGINE (ElevenLabs 2026 Parity)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class MindVoiceEngine {
  final stt.SpeechToText _stt = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final HumanVoiceVariance _humanVoice = HumanVoiceVariance(level: 0.65);

  bool _sttReady = false;
  bool isSpeaking = false;
  bool isListening = false;
  AudioRoute currentRoute = AudioRoute.unknown;
  bool _stopRequested = false;

  // ── Init ────────────────────────────────────────────────────
  Future<void> init() async {
    _sttReady = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    await _tts.setLanguage('en-GB');
    await _setupBritishVoice();
    await _setupAudioSession();
  }

  Future<void> _setupBritishVoice() async {
    const priority = [
      'daniel',
      'arthur',
      'oliver',
      'harry',
      'george',
      'serena',
      'kate'
    ];
    final voices = await _tts.getVoices as List?;
    if (voices == null) return;
    dynamic best;
    for (final name in priority) {
      best = voices.firstWhere((v) {
        final n = (v['name'] ?? '').toString().toLowerCase();
        final l = (v['locale'] ?? '').toString().toLowerCase();
        return n.contains(name) && (l.contains('en-gb') || l.contains('en_gb'));
      }, orElse: () => null);
      if (best != null) break;
    }
    best ??= voices.firstWhere((v) {
      final l = (v['locale'] ?? '').toString().toLowerCase();
      return l.contains('en-gb') || l.contains('en_gb');
    }, orElse: () => null);
    if (best != null)
      await _tts.setVoice({'name': best['name'], 'locale': best['locale']});
  }

  Future<void> _setupAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    session.devicesChangedEventStream.listen((_) => _updateRoute(session));
    await _updateRoute(session);
  }

  Future<void> _updateRoute(AudioSession session) async {
    final devices = await session.getDevices();
    AudioRoute route = AudioRoute.speaker;
    for (final d in devices) {
      if (d.type == AudioDeviceType.bluetoothA2dp ||
          d.type == AudioDeviceType.bluetoothSco ||
          d.type == AudioDeviceType.bluetoothLe) {
        route = AudioRoute.bluetooth;
        break;
      }
      if (d.type == AudioDeviceType.wiredHeadset ||
          d.type == AudioDeviceType.wiredHeadphones) {
        route = AudioRoute.wiredEarphone;
        break;
      }
    }
    currentRoute = route;
  }

  bool get isEarphoneConnected =>
      currentRoute == AudioRoute.bluetooth ||
      currentRoute == AudioRoute.wiredEarphone;

  // ── THE CORE: Human Speech Engine — Research-Calibrated 2025 ─────────────
  Future<void> speakWithPattern(
    String rawText,
    VoicePattern pattern, {
    bool earphoneOnly = false,
  }) async {
    if (earphoneOnly && !isEarphoneConnected) return;
    final profile = kPatternLibrary[pattern];
    if (profile == null || !profile.speakable) return;
    if (profile.requiresEarphone && !isEarphoneConnected) return;

    _stopRequested = false;
    isSpeaking = true;

    final dims = profile.dimensions;

    // ── 1. Parse emotion tag ──────────────────────────────────────────────
    final (tagStripped, parsedTag) = EmotionTagParser.parse(rawText);
    final emotion = parsedTag == EmotionTag.neutral
        ? EmotionTagParser.inferFromPattern(pattern)
        : parsedTag;

    // ── 2. Normalise text ─────────────────────────────────────────────────
    var normText = SpeechNormaliser.normalise(tagStripped);

    // ── 3. Earphone trim ──────────────────────────────────────────────────
    if (isEarphoneConnected && dims.proximity >= 0.85) {
      final sents = normText.split(RegExp(r'(?<=[.!?])\s+'));
      if (sents.length > 2) normText = sents.take(2).join(' ');
    }

    // ── 4. Base TTS parameters from pattern dimensions ────────────────────
    final baseRate = 0.36 + dims.pace * 0.14;
    final basePitch = 0.87 + dims.weight * 0.10;
    final baseVol = isEarphoneConnected ? (1.0 - dims.proximity * 0.10) : 1.0;

    // ── 5. Emotion pre-utterance pause (sighs, settles, pauses) ──────────
    final ep = kEmotionProfiles[emotion]!;
    if (ep.preUtterancePauseMs > 0 && !_stopRequested) {
      await Future.delayed(Duration(milliseconds: ep.preUtterancePauseMs));
    }

    // ── 6. Split into prosodic phrases (syntagms) ─────────────────────────
    final syntagms =
        SyntagmSplitter.split(normText, dims, emotion, isEarphoneConnected);
    if (syntagms.isEmpty) {
      isSpeaking = false;
      return;
    }

    // ── 7. Initialise utterance-level prosodic arc ────────────────────────
    // This is where F0 declination, breath-group hierarchy, and
    // utterance momentum are set for the whole sentence.
    _humanVoice.f0.beginUtterance(
      totalPhrases: syntagms.length,
      emotion: emotion,
      isQuestion: _HumanPhonetics.isQuestion(normText),
      urgency: dims.urgency,
    );

    final compiler = _humanVoice.compiler;

    // ── 8. MAIN LOOP: phrase → word-groups → individual TTS calls ─────────
    //
    // The human speech simulation happens here.
    // Each syntagm is compiled into WordUnits — each with unique rate/pitch/vol.
    // The per-word variation is what eliminates robotic sound.
    // The log-normal inter-phrase pauses give the right-skewed distribution
    // seen in real spontaneous speech.
    for (int si = 0; si < syntagms.length; si++) {
      if (_stopRequested) break;
      final s = syntagms[si];

      // Pre-phrase pause (breath intake simulation)
      if (s.prePauseMs > 0 && !_stopRequested) {
        await Future.delayed(Duration(milliseconds: s.prePauseMs));
      }

      // Compile this phrase into word-level speech units
      // Each unit has independently computed F0, duration, amplitude
      final units = compiler.compileSyntagm(
        s: s,
        baseRate: baseRate,
        basePitch: basePitch,
        baseVol: baseVol,
        emotion: emotion,
        urgency: dims.urgency,
        isEarphone: isEarphoneConnected,
      );

      // Speak each word group with its unique prosodic profile
      for (int ui = 0; ui < units.length; ui++) {
        if (_stopRequested) break;
        final unit = units[ui];

        // Cognitive hesitation pause (pre-word, sub-perceptual)
        if (unit.preGapMs > 0) {
          await Future.delayed(Duration(milliseconds: unit.preGapMs));
        }

        // Apply this unit's prosodic parameters to TTS engine
        // Critical: re-apply after every speak() on some Android engines
        await _tts.setSpeechRate(unit.rate);
        await _tts.setPitch(unit.pitch);
        await _tts.setVolume(unit.vol);

        // Speak the word group and wait for completion
        final done = Completer<void>();
        _tts.setCompletionHandler(() {
          if (!done.isCompleted) done.complete();
        });
        _tts.setErrorHandler((_) {
          if (!done.isCompleted) done.complete();
        });

        await _tts.speak(unit.text);

        // Timeout: word-count calibrated + platform overhead
        final wordCount = unit.text.split(' ').length;
        final timeoutSec = (wordCount * 0.85 + 1.2).ceil().clamp(2, 10);
        await done.future
            .timeout(Duration(seconds: timeoutSec), onTimeout: () {});

        // Post-phrase pause (only after last unit in syntagm)
        // The inter-unit gap is 0ms — TTS call overhead (20–60ms) IS the gap.
        // Adding explicit pauses here recreates the robotic read-aloud rhythm.
        if (!_stopRequested && unit.postGapMs > 0) {
          await Future.delayed(Duration(milliseconds: unit.postGapMs));
        }
      }
    }

    // ── 9. Emotion post-utterance hold ────────────────────────────────────
    if (!_stopRequested && ep.postUtterancePauseMs > 0) {
      await Future.delayed(Duration(milliseconds: ep.postUtterancePauseMs));
    }

    isSpeaking = false;
  }

  // ── Silence pattern detection ───────────────────────────────
  VoicePattern? silencePattern(Duration since,
      {required bool isEarphone,
      required bool isLateNight,
      required bool isHeavyDay}) {
    final s = since.inSeconds;
    if (s < 6 || s > 20 || isEarphone) return null;
    if (s > 12)
      return isLateNight
          ? VoicePattern.lateNightWrap
          : VoicePattern.silenceDrifted;
    if (isHeavyDay) return VoicePattern.silencePresent;
    return VoicePattern.silencePresent;
  }

  // ── STT ─────────────────────────────────────────────────────
  Future<void> listen(
      {required void Function(String, bool) onResult,
      required void Function() onEnd}) async {
    if (!_sttReady) {
      onEnd();
      return;
    }
    isListening = true;
    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions:
          stt.SpeechListenOptions(partialResults: true, cancelOnError: false),
    );
  }

  Future<void> stopListening() async {
    await _stt.stop();
    isListening = false;
  }

  Future<void> stopSpeaking() async {
    _stopRequested = true;
    await _tts.stop();
    isSpeaking = false;
  }

  // ── Pattern detector from user speech ──────────────────────
  VoicePattern detectPattern(
      String transcript, Duration speechDuration, PatternSelectorInput base) {
    final wordCount = transcript.split(' ').length;
    final wps = speechDuration.inSeconds > 0
        ? wordCount / speechDuration.inSeconds
        : 2.0;
    final t = transcript.toLowerCase();
    final hasDone = [
      'done',
      'finished',
      'completed it',
      'mark done',
      'sorted it'
    ].any(t.contains);
    final hasDrift = [
      'actually',
      'wait',
      'also',
      'by the way',
      'btw',
      'new idea',
      'what about',
      'instead'
    ].any(t.contains);
    final hasBreakthrough = [
      'that is it',
      'i see',
      'realised',
      'exactly',
      'that is the point'
    ].any(t.contains);
    final hasExcuse = [
      "can't",
      "cannot",
      "couldn't",
      "not now",
      "later",
      "busy",
      "tired",
      "no time",
      "too much"
    ].any(t.contains);
    final isOverwhelmed =
        !base.noTasksRemaining && wordCount < 5 && t.length < 20 && !hasDone;
    return PatternSelector.select(base.copyWith(
      userSpeechWps: wps,
      taskJustCompleted: hasDone,
      driftDetected: hasDrift,
      breakthroughSignal: hasBreakthrough,
      excuseCount: hasExcuse ? base.excuseCount + 1 : base.excuseCount,
      userOverwhelmedSignal: isOverwhelmed,
    ));
  }

  void dispose() {
    _stopRequested = true;
    _tts.stop();
    _stt.stop();
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION I — BACKGROUND SERVICE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class MindBackgroundHandler extends TaskHandler {
  bool _initialised = false;
  DateTime? _lastNudgeAt;
  int _nudgeIgnoreStreak = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async =>
      _ensureInit();

  Future<void> _ensureInit() async {
    if (_initialised) return;
    await EncryptionEngine.init();
    await SecurePrefs.init();
    await MemoryDatabase.init();
    await rotatingAI.loadKeys();
    _nudgeIgnoreStreak =
        int.tryParse(SecurePrefs.getString('nudge_ignore_streak') ?? '0') ?? 0;
    _initialised = true;
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    await _ensureInit();
    await _checkNudgeTriggers();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    if (data['type'] == 'nudge_responded') {
      _nudgeIgnoreStreak = 0;
      SecurePrefs.setString('nudge_ignore_streak', '0');
    }
    if (data['type'] == 'nudge_ignored') {
      _nudgeIgnoreStreak++;
      SecurePrefs.setString(
          'nudge_ignore_streak', _nudgeIgnoreStreak.toString());
    }
  }

  Future<void> _checkNudgeTriggers() async {
    try {
      final ctx = await MindStore.load();
      final focusTask = ctx.focusTask;
      if (focusTask == null || focusTask.id.isEmpty) return;
      if (_nudgeIgnoreStreak >= 3) {
        FlutterForegroundTask.sendDataToMain({
          'type': 'nudge',
          'text': 'Right. I will leave you to it.',
          'pattern': VoicePattern.earphoneDayAbandoned.name,
          'silent_after': true
        });
        return;
      }
      final cooldown = _nudgeIgnoreStreak == 0
          ? 20
          : _nudgeIgnoreStreak == 1
              ? 40
              : 80;
      if (_lastNudgeAt != null &&
          DateTime.now().difference(_lastNudgeAt!).inMinutes < cooldown) return;
      if (focusTask.lastMentionedAt != null) {
        final idle = DateTime.now().difference(focusTask.lastMentionedAt!);
        if (idle.inHours >= 2) {
          FlutterForegroundTask.sendDataToMain({
            'type': 'nudge',
            'text': '${focusTask.title} — still there. Ready to move on it?',
            'pattern': VoicePattern.earphoneNudge.name
          });
          _lastNudgeAt = DateTime.now();
        }
      }
    } catch (_) {}
  }
}

class BackgroundService {
  static void init() {
    FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'mind_bg',
            channelName: 'Mind',
            channelDescription: 'Mind background coaching',
            channelImportance: NotificationChannelImportance.LOW,
            priority: NotificationPriority.LOW),
        iosNotificationOptions: const IOSNotificationOptions(
            showNotification: false, playSound: false),
        foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.repeat(300000),
            autoRunOnBoot: true,
            autoRunOnMyPackageReplaced: true,
            allowWakeLock: true,
            allowWifiLock: false));
  }

  static Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
        serviceId: 42,
        notificationTitle: 'Mind',
        notificationText: 'Watching your back.',
        callback: startCallback);
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION J — APP ROOT
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class MindApp extends StatelessWidget {
  const MindApp({super.key});
  @override
  Widget build(BuildContext context) => WithForegroundTask(
      child: MaterialApp(
          title: 'Mind',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: _c0,
              fontFamily: '.SF Pro Display',
              useMaterial3: true),
          home: const MindHome()));
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION K — HOME SCREEN STATE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class MindHome extends StatefulWidget {
  const MindHome({super.key});
  @override
  State<MindHome> createState() => _MindHomeState();
}

enum _AppState { loading, needsKeys, idle, listening, thinking, speaking }

class _MindHomeState extends State<MindHome>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late MindContext _ctx;
  final WorkingMemory _workingMem = WorkingMemory();
  late MindVoiceEngine _voice;
  _AppState _state = _AppState.loading;

  String _liveTranscript = '', _lastAiText = '', _statusLabel = '';
  VoicePattern _lastPattern = VoicePattern.freshOpen;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  final _textCtrl = TextEditingController();

  bool _showText = false,
      _showTasks = false,
      _showMemory = false,
      _showProviderStatus = false;
  DateTime? _lastUserSpeechAt, _lastNudgeAt, _listenStartedAt;
  int _nudgeIgnoreStreak = 0;
  Timer? _silenceTimer, _nudgeCheckTimer, _nudgeResponseTimer;

  List<SemanticFact> _semanticFacts = [];
  List<EpisodicEntry> _episodicEntries = [];
  WellbeingSnapshot? _todayWellbeing;
  bool _consolidationDone = false,
      _justCompleted = false,
      _justReturnedFromNudge = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = MindVoiceEngine();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    BackgroundService.init();
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_consolidationDone) {
      SecurePrefs.setString(_kConsolidationPending, 'true');
      _consolidateSession().then((_) {
        SecurePrefs.remove(_kConsolidationPending);
        _consolidationDone = true;
      });
    }
    if (state == AppLifecycleState.resumed) _consolidationDone = false;
  }

  Future<void> _bootstrap() async {
    await EncryptionEngine.init();
    await SecurePrefs.init();
    await MemoryDatabase.init();
    final pending = SecurePrefs.getString(_kConsolidationPending);
    if (pending == 'true') await SecurePrefs.remove(_kConsolidationPending);
    _ctx = await MindStore.load();
    await rotatingAI.loadKeys();
    await _voice.init();
    if (!rotatingAI.hasAnyKey()) {
      setState(() => _state = _AppState.needsKeys);
      return;
    }
    await _requestPermissions();
    _todayWellbeing = await WellbeingEngine.collectAndSave();
    _nudgeIgnoreStreak = int.tryParse(
            await SemanticMemoryStore.get('nudge_ignore_streak') ?? '0') ??
        0;
    _ctx.sessionsTotal++;
    _ctx.lastSeen = DateTime.now();
    _ctx.sessionStartedAt = DateTime.now();
    await MindStore.save(_ctx);
    await BackgroundService.start();
    FlutterForegroundTask.addTaskDataCallback(_onBackgroundData);
    _nudgeCheckTimer = Timer.periodic(
        const Duration(minutes: 5), (_) => _checkProactiveNudge());
    setState(() => _state = _AppState.idle);
    await _greetUser();
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.speech.request();
  }

  int get _sessionMinutes => _ctx.sessionStartedAt != null
      ? DateTime.now().difference(_ctx.sessionStartedAt!).inMinutes
      : 0;

  PatternSelectorInput _buildSelectorInput(
          {int silenceSeconds = 0, bool forceEarphone = false}) =>
      PatternSelectorInput(
        sessionMinutes: _sessionMinutes,
        isLateNight: _ctx.isLateNight,
        isEarphone: forceEarphone || _voice.isEarphoneConnected,
        isFirstSession: _ctx.sessionsTotal == 1,
        hoursSinceLastSession: DateTime.now().difference(_ctx.lastSeen).inHours,
        excuseCount: _ctx.focusTask != null
            ? (_ctx.excuseCount[_ctx.focusTask!.id] ?? 0)
            : 0,
        deferralCount: _ctx.focusTask?.deferrals ?? 0,
        taskJustCompleted: _justCompleted,
        noTasksRemaining: _ctx.activeTasks.isEmpty,
        screenTimeMinutes: _todayWellbeing?.screenTimeMinutes ?? 0,
        unlockCount: _todayWellbeing?.unlockCount ?? 0,
        socialMinutes: _todayWellbeing?.socialMinutes ?? 0,
        longestFocusMinutes: _todayWellbeing?.longestFocusMinutes ?? 0,
        overdueTask: _ctx.focusTask?.urgency == 3,
        taskDueToday: _ctx.focusTask?.urgency == 2,
        cleanDay: (_todayWellbeing?.screenTimeMinutes ?? 999) < 120,
        nudgeIgnoreStreak: _nudgeIgnoreStreak,
        silenceSeconds: silenceSeconds,
        userJustReturned: _justReturnedFromNudge,
      );

  void _onBackgroundData(Object data) {
    if (data is! Map) return;
    if (data['type'] == 'nudge') {
      final text = data['text'] as String ?? '';
      final patternName =
          data['pattern'] as String ?? VoicePattern.earphoneNudge.name;
      final silentAfter = data['silent_after'] == true;
      VoicePattern pattern;
      try {
        pattern = VoicePattern.values.firstWhere((p) => p.name == patternName);
      } catch (_) {
        pattern = VoicePattern.earphoneNudge;
      }
      if (text.isNotEmpty &&
          _voice.isEarphoneConnected &&
          _state == _AppState.idle) {
        _voice.speakWithPattern(text, pattern);
        _lastNudgeAt = DateTime.now();
        setState(() => _lastAiText = text);
        if (silentAfter) {
          _nudgeCheckTimer?.cancel();
        } else {
          _nudgeResponseTimer?.cancel();
          _nudgeResponseTimer = Timer(const Duration(seconds: 90), () {
            _nudgeIgnoreStreak = (_nudgeIgnoreStreak + 1).clamp(0, 99);
            SemanticMemoryStore.upsert(
                'nudge_ignore_streak', _nudgeIgnoreStreak.toString(),
                confidence: 0.99, source: 'device');
          });
        }
      }
    }
  }

  void _markNudgeResponded() {
    _nudgeResponseTimer?.cancel();
    if (_nudgeIgnoreStreak > 0) {
      _nudgeIgnoreStreak = 0;
      SemanticMemoryStore.upsert('nudge_ignore_streak', '0',
          confidence: 0.99, source: 'device');
    }
    _justReturnedFromNudge = true;
    Timer(const Duration(seconds: 10), () => _justReturnedFromNudge = false);
  }

  Future<void> _checkProactiveNudge() async {
    if (_state != _AppState.idle) return;
    if (_nudgeIgnoreStreak >= 3) return;
    final snap = await WellbeingStore.loadToday();
    final nudge = await WellbeingEngine.evaluateTriggers(
        ctx: _ctx,
        snap: snap,
        audioRoute: _voice.currentRoute,
        lastNudgeAt: _lastNudgeAt,
        nudgeIgnoreStreak: _nudgeIgnoreStreak);
    if (nudge != null) {
      _lastNudgeAt = DateTime.now();
      setState(() => _lastAiText = nudge.text);
      await _voice.speakWithPattern(nudge.text, nudge.pattern);
      _nudgeResponseTimer?.cancel();
      _nudgeResponseTimer = Timer(const Duration(seconds: 90), () {
        _nudgeIgnoreStreak = (_nudgeIgnoreStreak + 1).clamp(0, 99);
        SemanticMemoryStore.upsert(
            'nudge_ignore_streak', _nudgeIgnoreStreak.toString(),
            confidence: 0.99, source: 'device');
      });
    }
  }

  Future<void> _greetUser() async {
    final dueNow = _ctx.dueNowTasks;
    final unfinished = _ctx.tasks
        .where((t) =>
            t.status == TaskStatus.pending || t.status == TaskStatus.active)
        .toList();
    String greetContext;
    if (_ctx.sessionsTotal == 1) {
      greetContext =
          '[session_start] First session. Greet warmly. Ask what to sort today.';
    } else if (dueNow.isNotEmpty) {
      greetContext =
          '[session_start] Deferred tasks now due: ${dueNow.map((t) => t.title).join(', ')}. Surface the most urgent.';
    } else if (unfinished.isNotEmpty) {
      final top = unfinished.first;
      final promise = _ctx.promises[top.id];
      greetContext = promise != null
          ? '[session_start] User promised to $promise for task "${top.title}". Did it happen?'
          : top.deferrals >= 3
              ? '[session_start] "${top.title}" deferred ${top.deferrals} times. Be direct.'
              : '[session_start] Welcome back. Most recent unfinished task: "${top.title}".';
    } else {
      greetContext =
          '[session_start] All tasks clear. Ask what to tackle today.';
    }
    await _sendToAi(greetContext, isSystemGreet: true);
  }

  Future<void> _sendToAi(String userText,
      {bool isSystemGreet = false, Duration? speechDuration}) async {
    if (!rotatingAI.hasAnyKey()) return;
    _markNudgeResponded();
    if (!isSystemGreet && userText.isNotEmpty) {
      SemanticMemoryStore.extractAndPersist(userText);
      final base = _buildSelectorInput();
      _lastPattern = _voice.detectPattern(
          userText, speechDuration ?? const Duration(seconds: 3), base);
    }
    _parseLocalCommands(userText);
    if (!isSystemGreet) {
      _workingMem.history.add(ChatMessage(
          role: 'user',
          content: userText,
          provider: rotatingAI.currentProvider));
    }
    _lastUserSpeechAt = DateTime.now();
    final focusTask = _ctx.focusTask;
    if (focusTask != null && focusTask.id.isNotEmpty)
      focusTask.lastMentionedAt = DateTime.now();

    setState(() {
      _state = _AppState.thinking;
      _statusLabel =
          'thinking via ${kProviders[rotatingAI.currentProvider]!.name}…';
      _liveTranscript = '';
    });

    final aiText = await MindAI.chat(
        ctx: _ctx,
        workingMem: _workingMem,
        userMessage: userText,
        sessionMins: _sessionMinutes,
        isEarphone: _voice.isEarphoneConnected,
        nudgeIgnoreStreak: _nudgeIgnoreStreak,
        wellbeing: _todayWellbeing);

    _workingMem.history.add(ChatMessage(
        role: 'assistant',
        content: aiText,
        provider: rotatingAI.currentProvider));
    _workingMem.currentPattern = _lastPattern;
    await MindStore.save(_ctx);
    await VoicePatternMemoryStore.record(
        _lastPattern,
        'responded',
        _ctx.focusTask?.tags.isNotEmpty == true
            ? _ctx.focusTask!.tags.first
            : 'general');

    // Strip tag from display text for the UI
    final (displayText, _) = EmotionTagParser.parse(aiText);

    setState(() {
      _lastAiText = displayText;
      _state = _AppState.speaking;
      _statusLabel =
          _voice.isEarphoneConnected ? 'speaking to earphone…' : 'speaking…';
    });

    await _voice.speakWithPattern(aiText, _lastPattern);
    _justCompleted = false;
    setState(() {
      _state = _AppState.idle;
      _statusLabel = '';
    });
  }

  Future<void> _consolidateSession() async {
    if (_workingMem.history.isEmpty) return;
    final now = _ctx.sessionStartedAt ??
        DateTime.now().subtract(const Duration(hours: 2));
    final tasksDone = _ctx.tasks
        .where((t) =>
            t.status == TaskStatus.done &&
            t.completedAt != null &&
            t.completedAt!.isAfter(now))
        .map((t) => t.title)
        .toList();
    final tasksDeferred = _ctx.tasks
        .where((t) => t.status == TaskStatus.deferred)
        .map((t) => t.title)
        .toList();
    final summary = await EpisodicMemoryStore.generateSummary(
        history: _workingMem.history, tasksDone: tasksDone);
    await EpisodicMemoryStore.save(EpisodicEntry(
        date: DateTime.now(),
        summary: summary,
        moodArc: 'pattern: ${_lastPattern.name}',
        tasksDone: tasksDone,
        tasksDeferred: tasksDeferred,
        keyQuotes: [],
        wellbeingScore: _scoreWellbeing(_todayWellbeing)));
    if (_ctx.focusTask != null && _ctx.focusTask!.id.isNotEmpty) {
      final outcome =
          tasksDone.contains(_ctx.focusTask!.title) ? 'completed' : 'deferred';
      await ProceduralMemoryStore.record(_lastPattern.name, outcome, 'general');
      await VoicePatternMemoryStore.record(_lastPattern, outcome, 'general');
    }
  }

  int _scoreWellbeing(WellbeingSnapshot? snap) {
    if (snap == null) return 50;
    int score = 100;
    score -= (snap.screenTimeMinutes / 360 * 40).round().clamp(0, 40);
    if (snap.longestFocusMinutes >= 25) score += 15;
    if (snap.socialMinutes > 90) score -= 20;
    return score.clamp(0, 100);
  }

  void _parseLocalCommands(String text) {
    final t = text.toLowerCase().trim();
    final addMatch = RegExp(r'^add (.+)$').firstMatch(t);
    if (addMatch != null) {
      final task = MindTask(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: addMatch.group(1)!.trim());
      _ctx.tasks.add(task);
      if (_ctx.focusTaskId == null) _ctx.focusTaskId = task.id;
      HapticFeedback.selectionClick();
    }
    if (['done', 'finished', 'completed it', 'mark done', 'sorted it']
        .any((s) => t == s || t.contains(s))) {
      final active = _ctx.tasks.firstWhere(
          (task) =>
              task.id == _ctx.focusTaskId || task.status == TaskStatus.active,
          orElse: () => MindTask(id: '', title: ''));
      if (active.id.isNotEmpty) {
        active.status = TaskStatus.done;
        active.completedAt = DateTime.now();
        _ctx.promises.remove(active.id);
        _ctx.excuseCount.remove(active.id);
        _ctx.focusTaskId = null;
        _justCompleted = true;
        HapticFeedback.mediumImpact();
        _lastPattern = VoicePattern.taskComplete;
      }
    }
    final focusMatch = RegExp(r'focus on (.+)$').firstMatch(t);
    if (focusMatch != null) {
      final query = focusMatch.group(1)!.trim();
      try {
        final match = _ctx.tasks
            .firstWhere((task) => task.title.toLowerCase().contains(query));
        _ctx.focusTaskId = match.id;
        HapticFeedback.selectionClick();
      } catch (_) {}
    }
    final deferMatch =
        RegExp(r'^defer (.+?) (?:until |to )(.+)$').firstMatch(t);
    if (deferMatch != null) {
      final query = deferMatch.group(1)!.trim();
      final timeExpr = deferMatch.group(2)!.trim();
      try {
        final match = _ctx.tasks
            .firstWhere((task) => task.title.toLowerCase().contains(query));
        final deferUntil = _parseTimeExpression(timeExpr);
        if (deferUntil != null) {
          match.deferredUntil = deferUntil;
          match.status = TaskStatus.deferred;
          match.deferrals++;
          if (_ctx.focusTaskId == match.id) _ctx.focusTaskId = null;
        }
      } catch (_) {}
    }
    final forgetMatch = RegExp(r'^forget (.+)$').firstMatch(t);
    if (forgetMatch != null)
      SemanticMemoryStore.forget(forgetMatch.group(1)!.trim());
    if (t == 'export memory') _exportMemory();
    if (t == 'reset memory') _confirmResetMemory();
    final promiseMatch =
        RegExp(r"^(?:i'?ll|i will|promise|i'm going to) (.+)$").firstMatch(t);
    if (promiseMatch != null && _ctx.focusTaskId != null) {
      _ctx.promises[_ctx.focusTaskId!] = promiseMatch.group(1)!.trim();
      _lastPattern = VoicePattern.promiseMade;
    }
    const excuseKeywords = [
      "can't",
      "cannot",
      "couldn't",
      "not now",
      "later",
      "busy",
      "tired",
      "no time",
      "not today",
      "maybe tomorrow",
      "too much"
    ];
    if (excuseKeywords.any((kw) => t.contains(kw)) && _ctx.focusTaskId != null)
      _ctx.excuseCount[_ctx.focusTaskId!] =
          (_ctx.excuseCount[_ctx.focusTaskId!] ?? 0) + 1;
    final focusTask = _ctx.focusTask;
    if (focusTask != null && focusTask.id.isNotEmpty) {
      const driftKeywords = [
        'actually',
        'wait',
        'also',
        'by the way',
        'btw',
        'new idea',
        'what about',
        'instead',
        'different'
      ];
      for (final kw in driftKeywords) {
        if (t.contains(kw)) {
          _ctx.driftCount[focusTask.title] =
              (_ctx.driftCount[focusTask.title] ?? 0) + 1;
          break;
        }
      }
      if (['excited', 'love', 'keen', 'ready', 'want to', 'can do']
          .any((s) => t.contains(s)))
        focusTask.sentimentScore = (focusTask.sentimentScore + 1).clamp(-2, 2);
      if (['hate', 'dread', 'dreading', 'avoid', 'boring', 'scared']
          .any((s) => t.contains(s)))
        focusTask.sentimentScore = (focusTask.sentimentScore - 1).clamp(-2, 2);
    }
  }

  DateTime? _parseTimeExpression(String expr) {
    final now = DateTime.now();
    final e = expr.toLowerCase().trim();
    if (e == 'tomorrow')
      return DateTime(now.year, now.month, now.day + 1, 9, 0);
    const days = {
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday
    };
    if (days.containsKey(e)) return _nextWeekday(now, days[e]!);
    final timeMatch =
        RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$').firstMatch(e);
    if (timeMatch != null) {
      int hour = int.parse(timeMatch.group(1)!);
      final min = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      final period = timeMatch.group(3);
      if (period == 'pm' && hour < 12) hour += 12;
      if (period == 'am' && hour == 12) hour = 0;
      var dt = DateTime(now.year, now.month, now.day, hour, min);
      if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
      return dt;
    }
    return null;
  }

  DateTime _nextWeekday(DateTime from, int weekday) {
    var d = from.add(const Duration(days: 1));
    while (d.weekday != weekday) d = d.add(const Duration(days: 1));
    return DateTime(d.year, d.month, d.day, 9, 0);
  }

  Future<void> _exportMemory() async {
    try {
      final semanticData = await SemanticMemoryStore.exportAll();
      final episodicEntries = await EpisodicMemoryStore.loadRecent(90);
      final exportData = {
        'exported_at': DateTime.now().toIso8601String(),
        'semantic': semanticData,
        'episodic': episodicEntries
            .map((e) => {
                  'date': e.date.toIso8601String(),
                  'summary': e.summary,
                  'tasks_done': e.tasksDone,
                  'wellbeing_score': e.wellbeingScore
                })
            .toList()
      };
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path,
          'mind_export_${DateTime.now().millisecondsSinceEpoch}.json');
      await File(path).writeAsString(jsonEncode(exportData));
      if (mounted) setState(() => _lastAiText = 'Memory exported to: $path');
    } catch (e) {
      if (mounted) setState(() => _lastAiText = 'Export failed. Try again.');
    }
  }

  void _confirmResetMemory() {
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
                backgroundColor: _c1,
                title: const Text('Reset all memory?',
                    style: TextStyle(color: _cText, fontSize: 16)),
                content: const Text(
                    'Deletes everything Mind knows about you. Cannot be undone.',
                    style: TextStyle(color: _cMuted, fontSize: 13)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel',
                          style: TextStyle(color: _cMuted))),
                  TextButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        HapticFeedback.heavyImpact();
                        await SemanticMemoryStore.resetAll();
                        await ProceduralMemoryStore.resetAll();
                        await WellbeingStore.resetAll();
                        await MemoryDatabase.db.delete('episodic');
                        await MemoryDatabase.db.delete('voice_pattern_memory');
                        if (mounted)
                          setState(() => _lastAiText = 'Memory cleared.');
                      },
                      child:
                          const Text('Reset', style: TextStyle(color: _cRed)))
                ]));
  }

  Future<void> _toggleListening() async {
    HapticFeedback.lightImpact();
    _markNudgeResponded();
    if (_state == _AppState.speaking) {
      await _voice.stopSpeaking();
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_state == _AppState.listening) {
      _silenceTimer?.cancel();
      await _voice.stopListening();
      if (_liveTranscript.trim().isNotEmpty) {
        final duration = _listenStartedAt != null
            ? DateTime.now().difference(_listenStartedAt!)
            : const Duration(seconds: 3);
        await _sendToAi(_liveTranscript.trim(), speechDuration: duration);
      } else {
        setState(() => _state = _AppState.idle);
      }
      return;
    }
    _listenStartedAt = DateTime.now();
    setState(() {
      _state = _AppState.listening;
      _liveTranscript = '';
      _statusLabel = 'listening…';
    });
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 8), () async {
      if (_state == _AppState.listening && _liveTranscript.isEmpty) {
        final since = _lastUserSpeechAt != null
            ? DateTime.now().difference(_lastUserSpeechAt!)
            : const Duration(seconds: 99);
        final pattern = _voice.silencePattern(since,
            isEarphone: _voice.isEarphoneConnected,
            isLateNight: _ctx.isLateNight,
            isHeavyDay: (_todayWellbeing?.screenTimeMinutes ?? 0) > 240);
        if (pattern != null) {
          final profile = kPatternLibrary[pattern];
          if (profile != null &&
              profile.speakable &&
              profile.templates.isNotEmpty) {
            await _voice.stopListening();
            final nudgeText = profile.templates.first;
            setState(() {
              _state = _AppState.speaking;
              _lastAiText = nudgeText;
            });
            await _voice.speakWithPattern(nudgeText, pattern);
            setState(() {
              _state = _AppState.idle;
              _statusLabel = '';
            });
          }
        }
      }
    });
    await _voice.listen(
      onResult: (text, final_) {
        if (text.isNotEmpty) _silenceTimer?.cancel();
        setState(() => _liveTranscript = text);
        if (final_ && text.trim().isNotEmpty) {
          _silenceTimer?.cancel();
          _voice.stopListening();
          final duration = _listenStartedAt != null
              ? DateTime.now().difference(_listenStartedAt!)
              : const Duration(seconds: 3);
          _sendToAi(text.trim(), speechDuration: duration);
        }
      },
      onEnd: () {
        _silenceTimer?.cancel();
        if (_state == _AppState.listening)
          setState(() => _state = _AppState.idle);
      },
    );
  }

  Future<void> _loadMemoryPanel() async {
    _semanticFacts = await SemanticMemoryStore.loadTop(15);
    _episodicEntries = await EpisodicMemoryStore.loadRecent(5);
    _todayWellbeing = await WellbeingStore.loadToday();
    setState(() {});
  }

  void _submitText() {
    final t = _textCtrl.text.trim();
    if (t.isEmpty) return;
    _textCtrl.clear();
    FocusScope.of(context).unfocus();
    _sendToAi(t);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _silenceTimer?.cancel();
    _nudgeCheckTimer?.cancel();
    _nudgeResponseTimer?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onBackgroundData);
    if (!_consolidationDone) _consolidateSession();
    _voice.dispose();
    _pulseCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: _c0,
      body: SafeArea(
          child: _state == _AppState.loading
              ? const _LoadingScreen()
              : _state == _AppState.needsKeys
                  ? _ApiKeysScreen(onSaved: () async {
                      await rotatingAI.saveKeys();
                      await _bootstrap();
                    })
                  : _mainBody()));

  Widget _mainBody() => Column(children: [
        _TopBar(
            onTasksToggle: () => setState(() {
                  _showTasks = !_showTasks;
                  _showMemory = false;
                  _showProviderStatus = false;
                }),
            onMemoryToggle: () async {
              _showMemory = !_showMemory;
              _showTasks = false;
              _showProviderStatus = false;
              if (_showMemory) await _loadMemoryPanel();
              setState(() {});
            },
            onProviderToggle: () => setState(() {
                  _showProviderStatus = !_showProviderStatus;
                  _showTasks = false;
                  _showMemory = false;
                }),
            taskCount: _ctx.activeTasks.length,
            showTasks: _showTasks,
            showMemory: _showMemory,
            showProviderStatus: _showProviderStatus,
            audioRoute: _voice.currentRoute,
            currentProvider: rotatingAI.currentProvider,
            currentPattern: _lastPattern),
        Expanded(
            child: _showTasks
                ? _TaskPanel(
                    ctx: _ctx,
                    onChanged: () async {
                      await MindStore.save(_ctx);
                      setState(() {});
                    })
                : _showMemory
                    ? _MemoryPanel(
                        semanticFacts: _semanticFacts,
                        episodicEntries: _episodicEntries,
                        wellbeing: _todayWellbeing)
                    : _showProviderStatus
                        ? _ProviderStatusPanel(engine: rotatingAI)
                        : _VoicePanel(
                            state: _state,
                            lastAiText: _lastAiText,
                            liveTranscript: _liveTranscript,
                            statusLabel: _statusLabel,
                            pulseAnim: _pulseAnim,
                            focusTask: _ctx.focusTask,
                            audioRoute: _voice.currentRoute,
                            onMicTap: _toggleListening,
                            currentProvider: rotatingAI.currentProvider,
                            currentPattern: _lastPattern)),
        _BottomBar(
            showText: _showText,
            textCtrl: _textCtrl,
            onTextToggle: () => setState(() => _showText = !_showText),
            onSubmit: _submitText,
            state: _state),
      ]);
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SECTION L — UI COMPONENTS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _TopBar extends StatelessWidget {
  final VoidCallback onTasksToggle, onMemoryToggle, onProviderToggle;
  final int taskCount;
  final bool showTasks, showMemory, showProviderStatus;
  final AudioRoute audioRoute;
  final AIProvider currentProvider;
  final VoicePattern currentPattern;

  const _TopBar(
      {required this.onTasksToggle,
      required this.onMemoryToggle,
      required this.onProviderToggle,
      required this.taskCount,
      required this.showTasks,
      required this.showMemory,
      required this.showProviderStatus,
      required this.audioRoute,
      required this.currentProvider,
      required this.currentPattern});

  @override
  Widget build(BuildContext context) {
    final isEarphone = audioRoute == AudioRoute.bluetooth ||
        audioRoute == AudioRoute.wiredEarphone;
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('mind',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: _cText,
                      letterSpacing: -1)),
              if (isEarphone) ...[
                const SizedBox(width: 8),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: _cGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(children: [
                      Icon(
                          audioRoute == AudioRoute.bluetooth
                              ? Icons.bluetooth_audio
                              : Icons.headset,
                          size: 11,
                          color: _cGreen),
                      const SizedBox(width: 3),
                      const Text('live',
                          style: TextStyle(fontSize: 10, color: _cGreen))
                    ]))
              ]
            ]),
            Text(_greeting(),
                style: const TextStyle(
                    fontSize: 13, color: _cMuted, fontWeight: FontWeight.w400)),
          ]),
          Row(children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                    color: _c2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _c3, width: 0.5)),
                child: Text(currentPattern.name,
                    style: const TextStyle(
                        fontSize: 9, color: _cMuted, letterSpacing: 0.3))),
            const SizedBox(width: 6),
            GestureDetector(
                onTap: onProviderToggle,
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                        color:
                            showProviderStatus ? _cGreen.withOpacity(0.2) : _c2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: showProviderStatus
                                ? _cGreen.withOpacity(0.5)
                                : _c3,
                            width: 0.5)),
                    child: Row(children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: _cGreen, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(kProviders[currentProvider]!.name.split(' ').first,
                          style: TextStyle(
                              fontSize: 11,
                              color: showProviderStatus ? _cGreen : _cMuted))
                    ]))),
            const SizedBox(width: 6),
            GestureDetector(
                onTap: onMemoryToggle,
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                        color: showMemory ? _cOrange.withOpacity(0.2) : _c2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: showMemory ? _cOrange.withOpacity(0.5) : _c3,
                            width: 0.5)),
                    child: Icon(Icons.psychology_rounded,
                        size: 16, color: showMemory ? _cOrange : _cMuted))),
            const SizedBox(width: 6),
            GestureDetector(
                onTap: onTasksToggle,
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: showTasks ? _cAccent.withOpacity(0.2) : _c2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: showTasks ? _cAccent.withOpacity(0.5) : _c3,
                            width: 0.5)),
                    child: Row(children: [
                      Icon(Icons.checklist_rounded,
                          size: 16, color: showTasks ? _cAccent : _cMuted),
                      const SizedBox(width: 6),
                      Text(taskCount == 0 ? 'tasks' : '$taskCount left',
                          style: TextStyle(
                              fontSize: 13,
                              color: showTasks ? _cAccent : _cMuted,
                              fontWeight: FontWeight.w500))
                    ]))),
          ]),
        ]));
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'good morning';
    if (h < 17) return 'good afternoon';
    return 'good evening';
  }
}

class _VoicePanel extends StatelessWidget {
  final _AppState state;
  final String lastAiText, liveTranscript, statusLabel;
  final Animation<double> pulseAnim;
  final MindTask? focusTask;
  final AudioRoute audioRoute;
  final VoidCallback onMicTap;
  final AIProvider currentProvider;
  final VoicePattern currentPattern;

  const _VoicePanel(
      {required this.state,
      required this.lastAiText,
      required this.liveTranscript,
      required this.statusLabel,
      required this.pulseAnim,
      required this.focusTask,
      required this.audioRoute,
      required this.onMicTap,
      required this.currentProvider,
      required this.currentPattern});

  @override
  Widget build(BuildContext context) {
    final profile = kPatternLibrary[currentPattern];
    final patternColor = _patternColor(currentPattern);
    return Column(children: [
      if (focusTask != null && focusTask!.id.isNotEmpty)
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _FocusPill(task: focusTask!)),
      Expanded(
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: lastAiText.isEmpty
                          ? const Text('tap and speak',
                              key: ValueKey('hint'),
                              style: TextStyle(
                                  color: _cMuted,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w300))
                          : Text(
                              state == _AppState.listening &&
                                      liveTranscript.isNotEmpty
                                  ? liveTranscript
                                  : lastAiText,
                              key: ValueKey(lastAiText + liveTranscript),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: state == _AppState.listening
                                      ? _cAccent
                                      : _cText,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w300,
                                  height: 1.4,
                                  letterSpacing: -0.3)))))),
      if (profile != null && lastAiText.isNotEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: _PatternDimBar(profile: profile, color: patternColor)),
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AnimatedOpacity(
              opacity: statusLabel.isEmpty ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              child: Text(statusLabel,
                  style: const TextStyle(
                      fontSize: 13,
                      color: _cMuted,
                      fontWeight: FontWeight.w400)))),
      _MicButton(state: state, pulseAnim: pulseAnim, onTap: onMicTap),
      const SizedBox(height: 32),
    ]);
  }

  Color _patternColor(VoicePattern p) {
    final name = p.name;
    if (name.startsWith('excuse') ||
        name.startsWith('overdue') ||
        name.startsWith('promise')) return _cRed;
    if (name.startsWith('earphone')) return _cPurple;
    if (name.startsWith('task') && name.contains('Complete')) return _cGreen;
    if (name.startsWith('wellbeing') ||
        name.startsWith('heavy') ||
        name.startsWith('fragment') ||
        name.startsWith('social') ||
        name.startsWith('noFocus')) return _cOrange;
    if (name.startsWith('user') && name.contains('Fatigued')) return _cMuted;
    if (name.startsWith('silence')) return _c3;
    return _cAccent;
  }
}

class _PatternDimBar extends StatelessWidget {
  final PatternProfile profile;
  final Color color;
  const _PatternDimBar({required this.profile, required this.color});
  @override
  Widget build(BuildContext context) {
    final dims = profile.dimensions;
    final vals = [
      dims.proximity,
      dims.urgency,
      dims.warmth,
      dims.challenge,
      dims.brevity,
      dims.silenceIntent
    ];
    return Row(
        children: vals
            .map((v) => Expanded(
                child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.15 + v * 0.6),
                        borderRadius: BorderRadius.circular(1)))))
            .toList());
  }
}

class _FocusPill extends StatelessWidget {
  final MindTask task;
  const _FocusPill({required this.task});
  @override
  Widget build(BuildContext context) {
    final urgencyColor = task.urgency == 3
        ? _cRed
        : task.urgency == 2
            ? _cOrange
            : _cGreen;
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: urgencyColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: urgencyColor.withOpacity(0.25), width: 0.5)),
        child: Row(children: [
          Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: urgencyColor, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Text('focus: ',
              style: TextStyle(
                  color: urgencyColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          Expanded(
              child: Text(task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _cText, fontSize: 13))),
          if (task.urgency == 3)
            const Text('overdue', style: TextStyle(fontSize: 10, color: _cRed))
        ]));
  }
}

class _MicButton extends StatelessWidget {
  final _AppState state;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;
  const _MicButton(
      {required this.state, required this.pulseAnim, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isListening = state == _AppState.listening;
    final isThinking = state == _AppState.thinking;
    final isSpeaking = state == _AppState.speaking;
    Color btnColor = _c2;
    Color iconColor = _cMuted;
    IconData icon = Icons.mic_rounded;
    if (isListening) {
      btnColor = _cAccent;
      iconColor = Colors.white;
      icon = Icons.stop_rounded;
    } else if (isThinking) {
      btnColor = _cOrange.withOpacity(0.2);
      iconColor = _cOrange;
      icon = Icons.hourglass_empty_rounded;
    } else if (isSpeaking) {
      btnColor = _cGreen.withOpacity(0.15);
      iconColor = _cGreen;
      icon = Icons.volume_up_rounded;
    }
    return GestureDetector(
        onTap: isThinking ? null : onTap,
        child: AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, child) => Transform.scale(
                scale: (isListening || isSpeaking) ? pulseAnim.value : 1.0,
                child: child),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                    color: btnColor,
                    shape: BoxShape.circle,
                    boxShadow: isListening
                        ? [
                            BoxShadow(
                                color: _cAccent.withOpacity(0.35),
                                blurRadius: 30,
                                spreadRadius: 4)
                          ]
                        : isSpeaking
                            ? [
                                BoxShadow(
                                    color: _cGreen.withOpacity(0.25),
                                    blurRadius: 24,
                                    spreadRadius: 2)
                              ]
                            : []),
                child: Icon(icon, color: iconColor, size: 34))));
  }
}

class _MemoryPanel extends StatelessWidget {
  final List<SemanticFact> semanticFacts;
  final List<EpisodicEntry> episodicEntries;
  final WellbeingSnapshot? wellbeing;
  const _MemoryPanel(
      {required this.semanticFacts,
      required this.episodicEntries,
      required this.wellbeing});
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 20), children: [
        if (wellbeing != null) ...[
          _sectionHeader('Today', Icons.bar_chart_rounded, _cGreen),
          _card(_buildWellbeingRows(wellbeing!)),
          const SizedBox(height: 20)
        ],
        if (semanticFacts.isNotEmpty) ...[
          _sectionHeader('What I know', Icons.person_rounded, _cAccent),
          _card(Column(children: semanticFacts.map(_factRow).toList())),
          const SizedBox(height: 20)
        ],
        if (episodicEntries.isNotEmpty) ...[
          _sectionHeader('Recent sessions', Icons.history_rounded, _cOrange),
          ...episodicEntries.map(_episodicCard)
        ],
        const SizedBox(height: 8),
        const Center(
            child: Text('All memory stored locally and encrypted.',
                style: TextStyle(fontSize: 11, color: _cMuted))),
      ]);

  Widget _sectionHeader(String title, IconData icon, Color color) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3))
      ]));
  Widget _card(Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _c1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _c3, width: 0.5)),
      child: child);
  Widget _buildWellbeingRows(WellbeingSnapshot snap) {
    final h = snap.screenTimeMinutes ~/ 60, min = snap.screenTimeMinutes % 60;
    return Column(children: [
      _wRow('Screen time', '${h}h ${min}m'),
      _wRow('Unlocks', '${snap.unlockCount}'),
      _wRow('Longest focus', '${snap.longestFocusMinutes} min'),
      _wRow('Social', '${snap.socialMinutes} min'),
      _wRow('Top categories', snap.topCategories.join(', '))
    ]);
  }

  Widget _wRow(String l, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: const TextStyle(fontSize: 13, color: _cMuted)),
        Text(v,
            style: const TextStyle(
                fontSize: 13, color: _cText, fontWeight: FontWeight.w500))
      ]));
  Widget _factRow(SemanticFact f) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
            child: Text(f.key,
                style: const TextStyle(fontSize: 12, color: _cMuted))),
        const SizedBox(width: 8),
        Expanded(
            flex: 2,
            child: Text(f.value,
                style: const TextStyle(fontSize: 12, color: _cText))),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: _cAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4)),
            child: Text('${(f.confidence * 100).round()}%',
                style: const TextStyle(fontSize: 10, color: _cAccent)))
      ]));
  Widget _episodicCard(EpisodicEntry e) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _c1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _c3, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(e.date.toLocal().toString().split(' ')[0],
            style: const TextStyle(fontSize: 11, color: _cMuted)),
        const SizedBox(height: 4),
        Text(e.summary,
            style: const TextStyle(fontSize: 13, color: _cText, height: 1.4)),
        if (e.tasksDone.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
              spacing: 6,
              children: e.tasksDone
                  .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: _cGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(t,
                          style:
                              const TextStyle(fontSize: 10, color: _cGreen))))
                  .toList())
        ]
      ]));
}

class _ProviderStatusPanel extends StatelessWidget {
  final RotatingAIEngine engine;
  const _ProviderStatusPanel({required this.engine});
  @override
  Widget build(BuildContext context) {
    final order = [
      AIProvider.groq,
      AIProvider.gemini,
      AIProvider.mistral,
      AIProvider.cohere
    ];
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        children: [
          const Text('AI Providers',
              style: TextStyle(
                  fontSize: 16, color: _cText, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('All free tier. Rotates automatically on rate limits.',
              style: TextStyle(fontSize: 12, color: _cMuted)),
          const SizedBox(height: 16),
          ...order.map((p) {
            final cfg = kProviders[p]!;
            final health = engine.health[p]!;
            final hasKey =
                engine.getKey(p) != null && engine.getKey(p)!.isNotEmpty;
            final isCurrent = engine.currentProvider == p;
            final isLimited = health.isRateLimited;
            Color statusColor = hasKey
                ? isLimited
                    ? _cOrange
                    : _cGreen
                : _c3;
            String statusText = !hasKey
                ? 'no key'
                : isLimited
                    ? 'rate limited'
                    : 'active';
            if (isCurrent && hasKey && !isLimited) statusText = 'current';
            return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: isCurrent ? _cAccent.withOpacity(0.06) : _c1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: isCurrent ? _cAccent.withOpacity(0.3) : _c3,
                        width: 0.5)),
                child: Row(children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Text(cfg.name,
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: _cText,
                                  fontWeight: FontWeight.w500)),
                          if (isCurrent) ...[
                            const SizedBox(width: 6),
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                    color: _cAccent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4)),
                                child: const Text('current',
                                    style: TextStyle(
                                        fontSize: 10, color: _cAccent)))
                          ]
                        ]),
                        const SizedBox(height: 2),
                        Text(
                            '${cfg.dailyLimit} req/day free · ${cfg.signupUrl}',
                            style:
                                const TextStyle(fontSize: 11, color: _cMuted)),
                        if (hasKey && health.totalRequests > 0)
                          Text(
                              '${health.successCount}/${health.totalRequests} success · ${health.rateLimitHits} rate limits',
                              style:
                                  const TextStyle(fontSize: 11, color: _cMuted))
                      ])),
                  const SizedBox(width: 8),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(statusText,
                          style: TextStyle(fontSize: 11, color: statusColor)))
                ]));
          }),
          const SizedBox(height: 16),
          GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => _ApiKeysScreen(onSaved: () async {
                            await rotatingAI.saveKeys();
                            Navigator.pop(context);
                          }))),
              child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: _c2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _c3, width: 0.5)),
                  alignment: Alignment.center,
                  child: const Text('Edit API Keys',
                      style: TextStyle(
                          color: _cText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)))),
        ]);
  }
}

class _TaskPanel extends StatelessWidget {
  final MindContext ctx;
  final VoidCallback onChanged;
  const _TaskPanel({required this.ctx, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final tasks = ctx.tasks.reversed.toList();
    if (tasks.isEmpty)
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('no tasks yet\nsay "add [task]" to begin',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _cMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w300))));
    return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _TaskCard(
            task: tasks[i],
            isFocus: tasks[i].id == ctx.focusTaskId,
            hasPromise: ctx.promises.containsKey(tasks[i].id),
            excuseCount: ctx.excuseCount[tasks[i].id] ?? 0,
            onToggleDone: () {
              final t = tasks[i];
              if (t.status == TaskStatus.done) {
                t.status = TaskStatus.pending;
                t.completedAt = null;
              } else {
                t.status = TaskStatus.done;
                t.completedAt = DateTime.now();
                ctx.promises.remove(t.id);
                ctx.excuseCount.remove(t.id);
                if (ctx.focusTaskId == t.id) ctx.focusTaskId = null;
              }
              HapticFeedback.mediumImpact();
              onChanged();
            },
            onFocus: () {
              ctx.focusTaskId = tasks[i].id;
              HapticFeedback.selectionClick();
              onChanged();
            },
            onDelete: () {
              ctx.promises.remove(tasks[i].id);
              ctx.excuseCount.remove(tasks[i].id);
              ctx.tasks.removeWhere((t) => t.id == tasks[i].id);
              if (ctx.focusTaskId == tasks[i].id) ctx.focusTaskId = null;
              onChanged();
            }));
  }
}

class _TaskCard extends StatelessWidget {
  final MindTask task;
  final bool isFocus, hasPromise;
  final int excuseCount;
  final VoidCallback onToggleDone, onFocus, onDelete;
  const _TaskCard(
      {required this.task,
      required this.isFocus,
      required this.hasPromise,
      required this.excuseCount,
      required this.onToggleDone,
      required this.onFocus,
      required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final done = task.status == TaskStatus.done;
    return Dismissible(
        key: Key(task.id),
        direction: DismissDirection.endToStart,
        background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
                color: _cRed.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.delete_outline, color: _cRed)),
        onDismissed: (_) => onDelete(),
        child: GestureDetector(
            onLongPress: onFocus,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                    color: isFocus ? _cAccent.withOpacity(0.08) : _c1,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isFocus
                            ? _cAccent.withOpacity(0.3)
                            : done
                                ? _c3.withOpacity(0.3)
                                : _c3,
                        width: 0.5)),
                child: Row(children: [
                  GestureDetector(
                      onTap: onToggleDone,
                      child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                              color: done ? _cGreen : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: done ? _cGreen : _c3, width: 1.5)),
                          child: done
                              ? const Icon(Icons.check_rounded,
                                  size: 14, color: Colors.white)
                              : null)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(task.title,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: done ? _cMuted : _cText,
                                decoration:
                                    done ? TextDecoration.lineThrough : null,
                                decorationColor: _cMuted)),
                        if (task.deferrals > 0 ||
                            hasPromise ||
                            excuseCount >= 2)
                          Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Wrap(spacing: 6, children: [
                                if (task.urgency == 3)
                                  const Text('overdue',
                                      style: TextStyle(
                                          fontSize: 11, color: _cRed)),
                                if (task.urgency == 2)
                                  const Text('due today',
                                      style: TextStyle(
                                          fontSize: 11, color: _cOrange)),
                                if (task.deferrals > 0)
                                  Text('deferred ${task.deferrals}×',
                                      style: const TextStyle(
                                          fontSize: 11, color: _cOrange)),
                                if (hasPromise)
                                  const Text('promise pending',
                                      style: TextStyle(
                                          fontSize: 11, color: _cAccent)),
                                if (excuseCount >= 2)
                                  Text('$excuseCount excuses',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: _cRed.withOpacity(0.8)))
                              ]))
                      ])),
                  if (isFocus)
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: _cAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text('focus',
                            style: TextStyle(
                                fontSize: 11,
                                color: _cAccent,
                                fontWeight: FontWeight.w500)))
                ]))));
  }
}

class _BottomBar extends StatelessWidget {
  final bool showText;
  final TextEditingController textCtrl;
  final VoidCallback onTextToggle, onSubmit;
  final _AppState state;
  const _BottomBar(
      {required this.showText,
      required this.textCtrl,
      required this.onTextToggle,
      required this.onSubmit,
      required this.state});
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        if (showText)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(
                    child: Container(
                        decoration: BoxDecoration(
                            color: _c1,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: _c3, width: 0.5)),
                        child: TextField(
                            controller: textCtrl,
                            autofocus: true,
                            style: const TextStyle(color: _cText, fontSize: 15),
                            decoration: const InputDecoration(
                                hintText: 'type a message…',
                                hintStyle: TextStyle(color: _cMuted),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12)),
                            onSubmitted: (_) => onSubmit()))),
                const SizedBox(width: 10),
                GestureDetector(
                    onTap: onSubmit,
                    child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                            color: _cAccent, shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_upward_rounded,
                            color: Colors.white, size: 22)))
              ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _SmallBtn(
                  icon: showText
                      ? Icons.keyboard_hide_rounded
                      : Icons.keyboard_rounded,
                  onTap: onTextToggle,
                  active: showText)
            ])),
      ]);
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _SmallBtn(
      {required this.icon, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 44,
          height: 36,
          decoration: BoxDecoration(
              color: active ? _c3 : Colors.transparent,
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 20, color: active ? _cText : _cMuted)));
}

class _ApiKeysScreen extends StatefulWidget {
  final Future<void> Function() onSaved;
  const _ApiKeysScreen({required this.onSaved});
  @override
  State<_ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<_ApiKeysScreen> {
  final Map<AIProvider, TextEditingController> _ctrls = {
    for (final p in AIProvider.values) p: TextEditingController()
  };
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final p in AIProvider.values) {
      final e = rotatingAI.getKey(p);
      if (e != null) _ctrls[p]!.text = e;
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = [
      AIProvider.groq,
      AIProvider.gemini,
      AIProvider.mistral,
      AIProvider.cohere
    ];
    return Scaffold(
        backgroundColor: _c0,
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('mind',
                          style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: _cText,
                              letterSpacing: -1.5)),
                      const SizedBox(height: 6),
                      const Text(
                          'Set up your free AI keys.\nYou need at least one to start.',
                          style: TextStyle(
                              fontSize: 15, color: _cMuted, height: 1.5)),
                      const SizedBox(height: 4),
                      const Text(
                          'All free tier. No credit card. Mind rotates them automatically.',
                          style: TextStyle(
                              fontSize: 12, color: _cMuted, height: 1.6)),
                      const SizedBox(height: 24),
                      ...order.map((p) {
                        final cfg = kProviders[p]!;
                        return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(cfg.name,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: _cText,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 8),
                                    Text('${cfg.dailyLimit}+ req/day free',
                                        style: const TextStyle(
                                            fontSize: 11, color: _cGreen))
                                  ]),
                                  const SizedBox(height: 2),
                                  Text('Get at ${cfg.signupUrl}',
                                      style: const TextStyle(
                                          fontSize: 11, color: _cMuted)),
                                  const SizedBox(height: 6),
                                  TextField(
                                      controller: _ctrls[p],
                                      obscureText: true,
                                      style: const TextStyle(
                                          color: _cText, fontSize: 14),
                                      decoration: InputDecoration(
                                          hintText: cfg.keyHint,
                                          hintStyle: const TextStyle(
                                              color: _cMuted, fontSize: 13),
                                          filled: true,
                                          fillColor: _c1,
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: const BorderSide(
                                                  color: _c3, width: 0.5)),
                                          enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: const BorderSide(
                                                  color: _c3, width: 0.5)),
                                          focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: const BorderSide(
                                                  color: _cAccent, width: 1)),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 14,
                                                  vertical: 12)))
                                ]));
                      }),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: _cRed, fontSize: 13))),
                      const SizedBox(height: 4),
                      SizedBox(
                          width: double.infinity,
                          child: GestureDetector(
                              onTap: _saving ? null : _save,
                              child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                      color: _saving ? _c3 : _cAccent,
                                      borderRadius: BorderRadius.circular(14)),
                                  alignment: Alignment.center,
                                  child: _saving
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2))
                                      : const Text('Save and Continue',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600))))),
                      const SizedBox(height: 16),
                      const Text(
                          'Keys stored encrypted on-device. Nothing sent except to your chosen AI APIs.',
                          style: TextStyle(
                              fontSize: 11, color: _cMuted, height: 1.6)),
                    ]))));
  }

  Future<void> _save() async {
    bool anyKey = false;
    for (final p in AIProvider.values) {
      final val = _ctrls[p]!.text.trim();
      rotatingAI.setKey(p, val);
      if (val.isNotEmpty) anyKey = true;
    }
    if (!anyKey) {
      setState(() => _error = 'Enter at least one API key to continue.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await widget.onSaved();
    if (mounted) setState(() => _saving = false);
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Center(
      child: CircularProgressIndicator(color: _cAccent, strokeWidth: 1.5));
}

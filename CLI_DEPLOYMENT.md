# 🚀 CLI-Only GitHub Deployment Guide

Deploy MIND to GitHub using command-line interface only.

## Quick Deploy (Automated)

### Windows
```bash
deploy-cli.bat YOUR_GITHUB_USERNAME mind-ai-voice-assistant
```

### Example
```bash
deploy-cli.bat johndoe mind-ai-voice-assistant
```

## Manual Deploy (Step-by-Step)

### Prerequisites Check
```bash
# Check Git
git --version

# Check Flutter
flutter --version
```

### Step 1: Get Dependencies
```bash
flutter pub get
```

### Step 2: Initialize Git (if needed)
```bash
git init
```

### Step 3: Stage All Files
```bash
git add .
```

### Step 4: Create Initial Commit
```bash
git commit -m "feat: initial commit - MIND v5.0.0 voice-first AI productivity companion" ^
-m "- 🎙️ ElevenLabs-grade voice synthesis with 40+ contextual patterns" ^
-m "- 🎧 Earphone-native nudge system with intelligent timing" ^
-m "- 🧠 Three-layer memory system (episodic, semantic, procedural)" ^
-m "- 🔒 AES-256 encryption with Secure Enclave/Keystore" ^
-m "- 📊 Digital wellbeing integration" ^
-m "- 🗣️ Advanced speech synthesis (F0 declination, jitter/shimmer)" ^
-m "- 🎯 Promise tracking and accountability" ^
-m "- 📱 Background foreground service" ^
-m "- 🎨 Dark mode UI" ^
-m "- 🌍 Privacy-first local-only architecture"
```

### Step 5: Set Main Branch
```bash
git branch -M main
```

### Step 6: Add Remote
```bash
# Replace YOUR_USERNAME with your GitHub username
git remote add origin https://github.com/YOUR_USERNAME/mind-ai-voice-assistant.git
```

### Step 7: Push to GitHub
```bash
git push -u origin main
```

## After Deployment

### Add Repository Topics via CLI (using GitHub CLI)

If you have GitHub CLI installed:

```bash
# Install GitHub CLI first (if not installed)
# Windows: winget install GitHub.cli
# Mac: brew install gh
# Linux: See https://github.com/cli/cli#installation

# Login
gh auth login

# Add topics
gh repo edit --add-topic flutter,dart,ai-assistant,voice-assistant,productivity,task-management,speech-synthesis,text-to-speech,speech-recognition,mobile-app,ai,artificial-intelligence,voice-ai,conversational-ai,flutter-app,cross-platform,natural-language-processing,tts,stt,voice-control,earphone-integration,background-service,local-first,privacy-first,encryption,digital-wellbeing,focus-management,voice-first,ai-companion,smart-assistant,productivity-tools

# Enable features
gh repo edit --enable-issues --enable-discussions --enable-projects

# View repository
gh repo view --web
```

### Add Topics Manually

1. Go to: `https://github.com/YOUR_USERNAME/mind-ai-voice-assistant`
2. Click ⚙️ gear icon next to "About"
3. Add these topics:
```
flutter
dart
ai-assistant
voice-assistant
productivity
task-management
speech-synthesis
text-to-speech
speech-recognition
mobile-app
ai
artificial-intelligence
voice-ai
conversational-ai
flutter-app
cross-platform
natural-language-processing
tts
stt
voice-control
earphone-integration
background-service
local-first
privacy-first
encryption
digital-wellbeing
focus-management
voice-first
ai-companion
smart-assistant
productivity-tools
```

## Troubleshooting

### Push Failed - Authentication Required

**Option 1: Personal Access Token**
```bash
# Generate token at: https://github.com/settings/tokens
# Use token as password when prompted
git push -u origin main
```

**Option 2: SSH**
```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "your_email@example.com"

# Add to GitHub: https://github.com/settings/keys

# Change remote to SSH
git remote set-url origin git@github.com:YOUR_USERNAME/mind-ai-voice-assistant.git

# Push
git push -u origin main
```

### Repository Doesn't Exist

Create it first:

**Using GitHub CLI:**
```bash
gh repo create mind-ai-voice-assistant --public --description "🧠 Voice-first AI productivity companion with natural speech, earphone nudges, and intelligent task management"
```

**Or manually:**
1. Go to https://github.com/new
2. Name: `mind-ai-voice-assistant`
3. Public
4. Don't initialize with README
5. Create repository

### Remote Already Exists

```bash
# Remove existing remote
git remote remove origin

# Add new remote
git remote add origin https://github.com/YOUR_USERNAME/mind-ai-voice-assistant.git

# Push
git push -u origin main
```

### Working Tree Not Clean

```bash
# Check status
git status

# Stage changes
git add .

# Commit
git commit -m "feat: update deployment files"

# Push
git push
```

## Complete CLI Workflow

Here's the complete workflow in one script:

```bash
# 1. Setup
flutter pub get
git init
git add .

# 2. Commit
git commit -m "feat: initial commit - MIND v5.0.0"

# 3. Configure
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/mind-ai-voice-assistant.git

# 4. Deploy
git push -u origin main

# 5. Configure repository (with GitHub CLI)
gh auth login
gh repo edit --add-topic flutter,dart,ai-assistant,voice-assistant,productivity
gh repo edit --enable-issues --enable-discussions

# 6. View
gh repo view --web
```

## Verification

After deployment, verify:

```bash
# Check remote
git remote -v

# Check branch
git branch

# Check last commit
git log -1

# View on GitHub
gh repo view --web
```

## Next Steps

1. **Add social preview image**
   - Go to Settings → General → Social preview
   - Upload 1280x640px image

2. **Update description**
   - Settings → General → Description
   - Add: "🧠 Voice-first AI productivity companion with natural speech, earphone nudges, and intelligent task management"

3. **Enable features**
   - Settings → Features
   - Enable: Issues, Discussions, Projects

4. **Share**
   - Reddit: r/FlutterDev
   - Twitter: #Flutter #AI #Productivity
   - Dev.to: Write blog post

## GitHub CLI Cheat Sheet

```bash
# View repository
gh repo view

# Open in browser
gh repo view --web

# Create release
gh release create v5.0.0 --title "MIND v5.0.0" --notes "Initial release"

# List issues
gh issue list

# Create issue
gh issue create --title "Bug report" --body "Description"

# View pull requests
gh pr list

# Clone repository
gh repo clone YOUR_USERNAME/mind-ai-voice-assistant
```

## Success Checklist

- [ ] Repository created on GitHub
- [ ] Code pushed successfully
- [ ] Topics/tags added (30+)
- [ ] Description updated
- [ ] Issues enabled
- [ ] Discussions enabled
- [ ] Social preview image uploaded
- [ ] README displays correctly
- [ ] CI/CD workflow running
- [ ] License file present

## Support

If you encounter issues:

1. Check GitHub status: https://www.githubstatus.com/
2. Verify credentials: `gh auth status`
3. Check repository exists: `gh repo view YOUR_USERNAME/mind-ai-voice-assistant`
4. Review logs: `git log`
5. Check remote: `git remote -v`

---

**You're ready to deploy! Choose automated or manual method above.** 🚀

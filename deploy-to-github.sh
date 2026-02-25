#!/bin/bash

# MIND - GitHub Deployment Script
# This script helps you deploy MIND to GitHub with optimal configuration

set -e

echo "🧠 MIND - GitHub Deployment Script"
echo "=================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}❌ Git is not installed. Please install git first.${NC}"
    exit 1
fi

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter is not installed. Please install Flutter first.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Get GitHub username
read -p "Enter your GitHub username: " GITHUB_USERNAME

if [ -z "$GITHUB_USERNAME" ]; then
    echo -e "${RED}❌ GitHub username cannot be empty${NC}"
    exit 1
fi

# Get repository name
read -p "Enter repository name (default: mind-ai-voice-assistant): " REPO_NAME
REPO_NAME=${REPO_NAME:-mind-ai-voice-assistant}

echo ""
echo "📝 Configuration:"
echo "   GitHub Username: $GITHUB_USERNAME"
echo "   Repository Name: $REPO_NAME"
echo "   Repository URL: https://github.com/$GITHUB_USERNAME/$REPO_NAME"
echo ""

read -p "Is this correct? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "🔧 Step 1: Running Flutter checks..."

# Run Flutter pub get
echo "   📦 Getting dependencies..."
flutter pub get

# Run Flutter analyze
echo "   🔍 Analyzing code..."
flutter analyze

# Run Flutter format
echo "   ✨ Formatting code..."
flutter format .

echo -e "${GREEN}✅ Flutter checks passed${NC}"
echo ""

# Initialize git if not already initialized
if [ ! -d .git ]; then
    echo "🔧 Step 2: Initializing Git repository..."
    git init
    echo -e "${GREEN}✅ Git initialized${NC}"
else
    echo "🔧 Step 2: Git already initialized"
fi

echo ""

# Update README with correct username
echo "🔧 Step 3: Updating README with your GitHub username..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/yourusername/$GITHUB_USERNAME/g" README.md
    sed -i '' "s/yourusername/$GITHUB_USERNAME/g" DEPLOYMENT.md
    sed -i '' "s/yourusername/$GITHUB_USERNAME/g" CONTRIBUTING.md
else
    # Linux
    sed -i "s/yourusername/$GITHUB_USERNAME/g" README.md
    sed -i "s/yourusername/$GITHUB_USERNAME/g" DEPLOYMENT.md
    sed -i "s/yourusername/$GITHUB_USERNAME/g" CONTRIBUTING.md
fi
echo -e "${GREEN}✅ README updated${NC}"
echo ""

# Add all files
echo "🔧 Step 4: Staging files..."
git add .
echo -e "${GREEN}✅ Files staged${NC}"
echo ""

# Create initial commit
echo "🔧 Step 5: Creating initial commit..."
git commit -m "feat: initial commit - MIND v5.0.0 voice-first AI productivity companion

- 🎙️ ElevenLabs-grade voice synthesis
- 🎧 Earphone-native nudge system
- 🧠 40+ contextual voice patterns
- 🔒 AES-256 encryption
- 📊 Digital wellbeing integration
- 🗣️ Advanced speech synthesis (F0 declination, jitter/shimmer)
- 💾 Three-layer memory system
- 🎯 Promise tracking and accountability
- 📱 Background foreground service
- 🎨 Dark mode UI"

echo -e "${GREEN}✅ Initial commit created${NC}"
echo ""

# Set main branch
echo "🔧 Step 6: Setting main branch..."
git branch -M main
echo -e "${GREEN}✅ Main branch set${NC}"
echo ""

# Add remote
echo "🔧 Step 7: Adding remote repository..."
REMOTE_URL="https://github.com/$GITHUB_USERNAME/$REPO_NAME.git"
git remote add origin $REMOTE_URL || git remote set-url origin $REMOTE_URL
echo -e "${GREEN}✅ Remote added: $REMOTE_URL${NC}"
echo ""

# Push to GitHub
echo "🔧 Step 8: Pushing to GitHub..."
echo -e "${YELLOW}⚠️  You may be prompted for GitHub credentials${NC}"
echo ""

git push -u origin main

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 SUCCESS! Your repository has been deployed to GitHub!${NC}"
    echo ""
    echo "📋 Next Steps:"
    echo ""
    echo "1. 🏷️  Add repository topics/tags:"
    echo "   Go to: https://github.com/$GITHUB_USERNAME/$REPO_NAME"
    echo "   Click 'Settings' → Add topics:"
    echo "   flutter, dart, ai-assistant, voice-assistant, productivity,"
    echo "   task-management, speech-synthesis, text-to-speech, ai,"
    echo "   mobile-app, flutter-app, voice-ai, privacy-first"
    echo ""
    echo "2. 📝 Update repository description:"
    echo "   🧠 Voice-first AI productivity companion with natural speech,"
    echo "   earphone nudges, and intelligent task management. Built with Flutter."
    echo ""
    echo "3. 🎨 Add social preview image:"
    echo "   Settings → General → Social preview (1280x640px)"
    echo ""
    echo "4. ✅ Enable features:"
    echo "   Settings → Features → Enable Issues, Discussions"
    echo ""
    echo "5. 📢 Share your project:"
    echo "   - Reddit: r/FlutterDev, r/productivity"
    echo "   - Twitter: #Flutter #AI #Productivity"
    echo "   - Dev.to / Medium: Write a blog post"
    echo ""
    echo "6. 📖 Read DEPLOYMENT.md for detailed promotion strategies"
    echo ""
    echo "🔗 Your repository: https://github.com/$GITHUB_USERNAME/$REPO_NAME"
    echo ""
    echo -e "${GREEN}Good luck with your launch! 🚀${NC}"
else
    echo ""
    echo -e "${RED}❌ Push failed. Please check your GitHub credentials and try again.${NC}"
    echo ""
    echo "💡 Tips:"
    echo "   - Make sure you've created the repository on GitHub first"
    echo "   - Check your GitHub username and repository name"
    echo "   - Ensure you have push access to the repository"
    echo "   - You may need to set up SSH keys or personal access token"
    echo ""
    echo "📖 See: https://docs.github.com/en/authentication"
    exit 1
fi

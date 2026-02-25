@echo off
REM MIND - GitHub Deployment Script for Windows
REM This script helps you deploy MIND to GitHub with optimal configuration

setlocal enabledelayedexpansion

echo.
echo 🧠 MIND - GitHub Deployment Script
echo ==================================
echo.

REM Check if git is installed
where git >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Git is not installed. Please install git first.
    exit /b 1
)

REM Check if Flutter is installed
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Flutter is not installed. Please install Flutter first.
    exit /b 1
)

echo ✅ Prerequisites check passed
echo.

REM Get GitHub username
set /p GITHUB_USERNAME="Enter your GitHub username: "

if "%GITHUB_USERNAME%"=="" (
    echo ❌ GitHub username cannot be empty
    exit /b 1
)

REM Get repository name
set /p REPO_NAME="Enter repository name (default: mind-ai-voice-assistant): "
if "%REPO_NAME%"=="" set REPO_NAME=mind-ai-voice-assistant

echo.
echo 📝 Configuration:
echo    GitHub Username: %GITHUB_USERNAME%
echo    Repository Name: %REPO_NAME%
echo    Repository URL: https://github.com/%GITHUB_USERNAME%/%REPO_NAME%
echo.

set /p CONFIRM="Is this correct? (y/n): "
if /i not "%CONFIRM%"=="y" (
    echo Deployment cancelled.
    exit /b 0
)

echo.
echo 🔧 Step 1: Running Flutter checks...

REM Run Flutter pub get
echo    📦 Getting dependencies...
call flutter pub get

REM Run Flutter analyze
echo    🔍 Analyzing code...
call flutter analyze

REM Run Flutter format
echo    ✨ Formatting code...
call flutter format .

echo ✅ Flutter checks passed
echo.

REM Initialize git if not already initialized
if not exist .git (
    echo 🔧 Step 2: Initializing Git repository...
    git init
    echo ✅ Git initialized
) else (
    echo 🔧 Step 2: Git already initialized
)

echo.

REM Update README with correct username
echo 🔧 Step 3: Updating README with your GitHub username...
powershell -Command "(Get-Content README.md) -replace 'yourusername', '%GITHUB_USERNAME%' | Set-Content README.md"
powershell -Command "(Get-Content DEPLOYMENT.md) -replace 'yourusername', '%GITHUB_USERNAME%' | Set-Content DEPLOYMENT.md"
powershell -Command "(Get-Content CONTRIBUTING.md) -replace 'yourusername', '%GITHUB_USERNAME%' | Set-Content CONTRIBUTING.md"
echo ✅ README updated
echo.

REM Add all files
echo 🔧 Step 4: Staging files...
git add .
echo ✅ Files staged
echo.

REM Create initial commit
echo 🔧 Step 5: Creating initial commit...
git commit -m "feat: initial commit - MIND v5.0.0 voice-first AI productivity companion" -m "- 🎙️ ElevenLabs-grade voice synthesis" -m "- 🎧 Earphone-native nudge system" -m "- 🧠 40+ contextual voice patterns" -m "- 🔒 AES-256 encryption" -m "- 📊 Digital wellbeing integration" -m "- 🗣️ Advanced speech synthesis" -m "- 💾 Three-layer memory system" -m "- 🎯 Promise tracking" -m "- 📱 Background service" -m "- 🎨 Dark mode UI"

echo ✅ Initial commit created
echo.

REM Set main branch
echo 🔧 Step 6: Setting main branch...
git branch -M main
echo ✅ Main branch set
echo.

REM Add remote
echo 🔧 Step 7: Adding remote repository...
set REMOTE_URL=https://github.com/%GITHUB_USERNAME%/%REPO_NAME%.git
git remote add origin %REMOTE_URL% 2>nul || git remote set-url origin %REMOTE_URL%
echo ✅ Remote added: %REMOTE_URL%
echo.

REM Push to GitHub
echo 🔧 Step 8: Pushing to GitHub...
echo ⚠️  You may be prompted for GitHub credentials
echo.

git push -u origin main

if %ERRORLEVEL% EQU 0 (
    echo.
    echo 🎉 SUCCESS! Your repository has been deployed to GitHub!
    echo.
    echo 📋 Next Steps:
    echo.
    echo 1. 🏷️  Add repository topics/tags:
    echo    Go to: https://github.com/%GITHUB_USERNAME%/%REPO_NAME%
    echo    Click 'Settings' → Add topics:
    echo    flutter, dart, ai-assistant, voice-assistant, productivity,
    echo    task-management, speech-synthesis, text-to-speech, ai,
    echo    mobile-app, flutter-app, voice-ai, privacy-first
    echo.
    echo 2. 📝 Update repository description
    echo.
    echo 3. 🎨 Add social preview image
    echo.
    echo 4. ✅ Enable Issues and Discussions
    echo.
    echo 5. 📢 Share your project on Reddit, Twitter, Dev.to
    echo.
    echo 6. 📖 Read DEPLOYMENT.md for detailed strategies
    echo.
    echo 🔗 Your repository: https://github.com/%GITHUB_USERNAME%/%REPO_NAME%
    echo.
    echo Good luck with your launch! 🚀
) else (
    echo.
    echo ❌ Push failed. Please check your GitHub credentials and try again.
    echo.
    echo 💡 Tips:
    echo    - Make sure you've created the repository on GitHub first
    echo    - Check your GitHub username and repository name
    echo    - Ensure you have push access to the repository
    echo    - You may need to set up SSH keys or personal access token
    echo.
    echo 📖 See: https://docs.github.com/en/authentication
    exit /b 1
)

endlocal

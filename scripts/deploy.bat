@echo off
REM MIND GitHub Deployment Script for Windows
REM This script automates the deployment process to GitHub

echo.
echo ================================
echo MIND GitHub Deployment Script
echo ================================
echo.

REM Check if git is installed
where git >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Git is not installed. Please install git first.
    exit /b 1
)
echo [OK] Git is installed

REM Check if we're in a git repository
if not exist .git (
    echo [INFO] Initializing git repository...
    git init
    echo [OK] Git repository initialized
) else (
    echo [OK] Already in a git repository
)

REM Check for uncommitted changes
git status --short >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [WARNING] You have uncommitted changes
    set /p commit_choice="Do you want to commit all changes? (y/n): "
    if /i "%commit_choice%"=="y" (
        git add .
        set /p commit_msg="Enter commit message: "
        git commit -m "%commit_msg%"
        echo [OK] Changes committed
    )
)

REM Check if GitHub CLI is installed
where gh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [OK] GitHub CLI is installed
    
    REM Check if authenticated
    gh auth status >nul 2>nul
    if %ERRORLEVEL% EQU 0 (
        echo [OK] Authenticated with GitHub
        
        set /p create_repo="Do you want to create a new GitHub repository? (y/n): "
        if /i "%create_repo%"=="y" (
            set /p repo_name="Enter repository name (default: mind-voice-ai): "
            if "%repo_name%"=="" set repo_name=mind-voice-ai
            
            set /p repo_desc="Enter repository description: "
            if "%repo_desc%"=="" set repo_desc=Voice-first AI productivity companion with human-like speech synthesis and emotional intelligence. Built with Flutter.
            
            echo [INFO] Creating GitHub repository...
            gh repo create %repo_name% --public --description "%repo_desc%" --source=. --remote=origin --push
            
            echo [OK] Repository created and code pushed!
            
            echo [INFO] Adding topics to repository...
            gh repo edit --add-topic flutter,dart,ai,voice-assistant,productivity,tts,speech-synthesis,natural-language-processing,mobile-app,ios,android,voice-ai,conversational-ai,task-management,digital-wellbeing,flutter-app,ai-assistant,voice-recognition,speech-to-text,machine-learning,openai,gpt,emotional-ai,human-computer-interaction,mobile-ai,flutter-voice,productivity-app,ai-productivity,voice-first,intelligent-assistant
            echo [OK] Topics added
            
            echo [INFO] Enabling repository features...
            gh repo edit --enable-issues --enable-discussions --enable-projects
            echo [OK] Features enabled
        )
    ) else (
        echo [WARNING] Not authenticated with GitHub. Run 'gh auth login' first.
    )
) else (
    echo [WARNING] GitHub CLI not installed. Manual setup required.
    echo [INFO] Install from: https://cli.github.com/
)

REM Check if remote exists
git remote | findstr origin >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [OK] Remote 'origin' exists
    
    set /p push_choice="Do you want to push to GitHub? (y/n): "
    if /i "%push_choice%"=="y" (
        echo [INFO] Pushing to GitHub...
        git push -u origin main
        if %ERRORLEVEL% NEQ 0 (
            git push -u origin master
        )
        echo [OK] Code pushed to GitHub!
    )
) else (
    echo [WARNING] No remote 'origin' configured
    set /p repo_url="Enter GitHub repository URL: "
    if not "%repo_url%"=="" (
        git remote add origin %repo_url%
        echo [OK] Remote added
        
        echo [INFO] Pushing to GitHub...
        git push -u origin main
        if %ERRORLEVEL% NEQ 0 (
            git push -u origin master
        )
        echo [OK] Code pushed to GitHub!
    )
)

REM Create release tag
set /p tag_choice="Do you want to create a release tag? (y/n): "
if /i "%tag_choice%"=="y" (
    set /p version="Enter version (default: v5.0.0): "
    if "%version%"=="" set version=v5.0.0
    
    set /p release_msg="Enter release message: "
    if "%release_msg%"=="" set release_msg=Initial public release
    
    echo [INFO] Creating release tag...
    git tag -a %version% -m "%release_msg%"
    git push origin %version%
    echo [OK] Release tag created: %version%
    
    where gh >nul 2>nul
    if %ERRORLEVEL% EQU 0 (
        set /p gh_release="Do you want to create a GitHub release? (y/n): "
        if /i "%gh_release%"=="y" (
            echo [INFO] Creating GitHub release...
            gh release create %version% --title "MIND %version% - Initial Public Release" --notes "See DEPLOYMENT.md for full release notes"
            echo [OK] GitHub release created!
        )
    )
)

echo.
echo ================================
echo [OK] Deployment complete!
echo.
echo [INFO] Next steps:
echo   1. Add screenshots to screenshots/ directory
echo   2. Update README.md with screenshots
echo   3. Configure repository settings on GitHub
echo   4. Promote on social media (see DEPLOYMENT.md)
echo.
echo [INFO] Repository URL:
where gh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    gh repo view --web
) else (
    echo   Check your GitHub account
)
echo.

pause

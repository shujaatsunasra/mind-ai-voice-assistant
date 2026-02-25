#!/bin/bash

# MIND GitHub Deployment Script
# This script automates the deployment process to GitHub

set -e  # Exit on error

echo "🚀 MIND GitHub Deployment Script"
echo "================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "ℹ $1"
}

# Check if git is installed
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install git first."
    exit 1
fi
print_success "Git is installed"

# Check if we're in a git repository
if [ ! -d .git ]; then
    print_info "Initializing git repository..."
    git init
    print_success "Git repository initialized"
else
    print_success "Already in a git repository"
fi

# Check for uncommitted changes
if [[ -n $(git status -s) ]]; then
    print_warning "You have uncommitted changes"
    read -p "Do you want to commit all changes? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add .
        read -p "Enter commit message: " commit_msg
        git commit -m "$commit_msg"
        print_success "Changes committed"
    fi
fi

# Check if GitHub CLI is installed
if command -v gh &> /dev/null; then
    print_success "GitHub CLI is installed"
    
    # Check if authenticated
    if gh auth status &> /dev/null; then
        print_success "Authenticated with GitHub"
        
        read -p "Do you want to create a new GitHub repository? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Enter repository name (default: mind-voice-ai): " repo_name
            repo_name=${repo_name:-mind-voice-ai}
            
            read -p "Enter repository description: " repo_desc
            repo_desc=${repo_desc:-"Voice-first AI productivity companion with human-like speech synthesis and emotional intelligence. Built with Flutter."}
            
            print_info "Creating GitHub repository..."
            gh repo create "$repo_name" \
                --public \
                --description "$repo_desc" \
                --source=. \
                --remote=origin \
                --push
            
            print_success "Repository created and code pushed!"
            
            # Add topics
            print_info "Adding topics to repository..."
            gh repo edit --add-topic flutter,dart,ai,voice-assistant,productivity,tts,speech-synthesis,natural-language-processing,mobile-app,ios,android,voice-ai,conversational-ai,task-management,digital-wellbeing,flutter-app,ai-assistant,voice-recognition,speech-to-text,machine-learning,openai,gpt,emotional-ai,human-computer-interaction,mobile-ai,flutter-voice,productivity-app,ai-productivity,voice-first,intelligent-assistant
            print_success "Topics added"
            
            # Enable features
            print_info "Enabling repository features..."
            gh repo edit --enable-issues --enable-discussions --enable-projects
            print_success "Features enabled"
        fi
    else
        print_warning "Not authenticated with GitHub. Run 'gh auth login' first."
    fi
else
    print_warning "GitHub CLI not installed. Manual setup required."
    print_info "Install from: https://cli.github.com/"
fi

# Check if remote exists
if git remote | grep -q origin; then
    print_success "Remote 'origin' exists"
    
    read -p "Do you want to push to GitHub? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Pushing to GitHub..."
        git push -u origin main || git push -u origin master
        print_success "Code pushed to GitHub!"
    fi
else
    print_warning "No remote 'origin' configured"
    read -p "Enter GitHub repository URL: " repo_url
    if [ -n "$repo_url" ]; then
        git remote add origin "$repo_url"
        print_success "Remote added"
        
        print_info "Pushing to GitHub..."
        git push -u origin main || git push -u origin master
        print_success "Code pushed to GitHub!"
    fi
fi

# Create release tag
read -p "Do you want to create a release tag? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter version (default: v5.0.0): " version
    version=${version:-v5.0.0}
    
    read -p "Enter release message: " release_msg
    release_msg=${release_msg:-"Initial public release"}
    
    print_info "Creating release tag..."
    git tag -a "$version" -m "$release_msg"
    git push origin "$version"
    print_success "Release tag created: $version"
    
    if command -v gh &> /dev/null; then
        read -p "Do you want to create a GitHub release? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Creating GitHub release..."
            gh release create "$version" \
                --title "MIND $version - Initial Public Release" \
                --notes "See DEPLOYMENT.md for full release notes"
            print_success "GitHub release created!"
        fi
    fi
fi

echo ""
echo "================================="
print_success "Deployment complete!"
echo ""
print_info "Next steps:"
echo "  1. Add screenshots to screenshots/ directory"
echo "  2. Update README.md with screenshots"
echo "  3. Configure repository settings on GitHub"
echo "  4. Promote on social media (see DEPLOYMENT.md)"
echo ""
print_info "Repository URL:"
if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    gh repo view --web
else
    echo "  Check your GitHub account"
fi
echo ""

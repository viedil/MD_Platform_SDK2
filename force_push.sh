#!/bin/bash

echo "🚀 Starting Git Commit and Push Sequence..."

# 1. Check status
echo "📋 Checking status..."
git status

# 2. Add all files
echo "📂 Staging all files..."
git add .

# 3. Check if there are changes to commit
if git diff --cached --quiet; then
    echo "⚠️  No changes to commit. Working tree is clean."
else
    echo "✍️  Committing changes..."
    git commit -m "refactor: Final sync of all sections (00-11) with refined content"
fi

# 4. Push to GitHub
echo "☁️  Pushing to origin/main..."
# Using verbose mode to see exactly what happens
git push origin main --verbose

echo "✅ Sequence Complete."

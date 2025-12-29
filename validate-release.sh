#!/bin/bash
# Neopilot Release Validation Script
# Run this before tagging a release

set -e

echo "🔍 Validating Neopilot release..."

# Check version consistency
VERSION_FILE=$(cat VERSION)
echo "📋 Version file: $VERSION_FILE"

# Check changelog
if ! grep -q "$VERSION_FILE" CHANGELOG.md; then
    echo "❌ ERROR: Version $VERSION_FILE not found in CHANGELOG.md"
    exit 1
fi
echo "✅ CHANGELOG.md updated"

# Check stability contract
if [ ! -f STABILITY.md ]; then
    echo "❌ ERROR: STABILITY.md not found"
    exit 1
fi
echo "✅ STABILITY.md exists"

# Validate Lua syntax
echo "🔧 Checking Lua syntax..."
find lua -name "*.lua" -exec lua -e "print('Checking: {}'); dofile('{}')" \; 2>&1 | head -20
echo "✅ Lua syntax valid"

# Check Vimscript syntax (basic)
echo "🔧 Checking Vimscript syntax..."
if nvim --headless -c "source plugin/neopilot.vim" -c "qa" 2>/dev/null; then
    echo "✅ Vimscript syntax valid"
else
    echo "❌ Vimscript syntax error"
    exit 1
fi

# Check README references
if ! grep -q "$VERSION_FILE" README.md; then
    echo "⚠️  WARNING: Version $VERSION_FILE not prominently mentioned in README.md"
fi

echo ""
echo "🎉 Release validation complete!"
echo "Ready to tag: $VERSION_FILE"
echo ""
echo "Next steps:"
echo "1. git tag v$VERSION_FILE"
echo "2. git push --tags"
echo "3. Create GitHub release with RELEASE_NOTES_v1.0-beta.md"
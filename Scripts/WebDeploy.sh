#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$PROJECT_ROOT/Resources/Web/"
DEST="jtr.sh:/home/jtrsfltu/public_html/RockYou/docs/"

echo "📦 Deploying RockYou web content..."
echo "   Source: $SOURCE"
echo "   Destination: $DEST"
echo ""

# Actually deploy if --deploy is passed
if [[ "$1" == "--deploy" ]]; then
    rsync -avz --progress "$SOURCE" "$DEST"
    echo ""
    echo "✅ Deploy complete!"
    echo "   View at: https://rockyou.jtr.sh/docs/"
else
    echo "🔍 DRY RUN - showing what would be transferred:"
    rsync -avz --dry-run "$SOURCE" "$DEST"
    echo ""
    echo "✨ Run with --deploy to actually deploy"
fi

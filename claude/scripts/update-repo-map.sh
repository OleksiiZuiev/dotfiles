#!/bin/bash
# Generates ~/.claude/repo-map.md by scanning local GitHub repos
# Usage: bash ~/dotfiles/claude/scripts/update-repo-map.sh

GITHUB_ROOT="/c/work/github"
OUTPUT_FILE="$HOME/.claude/repo-map.md"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# Extract first usable description line from a README
extract_summary() {
    local readme="$1"

    while IFS= read -r line; do
        line="${line//$'\r'/}"
        # Skip empty lines, headings, badges, HTML tags, horizontal rules
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^#+ ]] && continue
        [[ "$line" =~ ^\!\[ ]] && continue
        [[ "$line" =~ ^\<  ]] && continue
        [[ "$line" =~ ^---+$ ]] && continue
        [[ "$line" =~ ^\[!\[ ]] && continue
        [[ "$line" =~ ^\`\`\` ]] && continue
        [[ "$line" =~ ^[0-9]+\. ]] && continue

        # Found a usable line — trim to first sentence
        echo "$line" | sed 's/^ *//; s/ *$//; s/\. .*/\./'
        return
    done < "$readme"

    echo "No description"
}

# Write header
cat > "$OUTPUT_FILE" << 'HEADER'
# Local Repo Map
<!-- Regenerate: bash ~/dotfiles/claude/scripts/update-repo-map.sh -->
HEADER
echo "<!-- Last updated: $(date +%Y-%m-%d) -->" >> "$OUTPUT_FILE"
cat >> "$OUTPUT_FILE" << 'TABLE'

| Repo | Org | Summary |
|------|-----|---------|
TABLE

# Scan repos
for org_dir in "$GITHUB_ROOT"/*/; do
    [ -d "$org_dir" ] || continue
    local_org=$(basename "$org_dir")

    for repo_dir in "$org_dir"*/; do
        [ -d "$repo_dir/.git" ] || continue
        local_repo=$(basename "$repo_dir")

        # Find README (case-insensitive)
        readme=""
        for candidate in "$repo_dir"README.md "$repo_dir"readme.md "$repo_dir"Readme.md; do
            if [ -f "$candidate" ]; then
                readme="$candidate"
                break
            fi
        done

        if [ -n "$readme" ]; then
            summary=$(extract_summary "$readme")
        else
            summary="No description"
        fi

        # Escape pipes in summary
        summary="${summary//|/\\|}"

        echo "| $local_repo | $local_org | $summary |" >> "$OUTPUT_FILE"
    done
done

echo "Repo map updated: $OUTPUT_FILE"

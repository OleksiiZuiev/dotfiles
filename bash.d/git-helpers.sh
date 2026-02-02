# Git helper functions

# Git switch recent branches - shows numbered list of recently checked-out branches
gsw() {
    local branches
    branches=$(git reflog show --pretty=format:'%gs' 2>/dev/null |
               grep -o 'checkout: moving from .* to .*' |
               sed 's/checkout: moving from .* to //' |
               awk '!seen[$0]++' |
               head -10)

    if [ -z "$branches" ]; then
        echo "No recent branches found"
        return 1
    fi

    echo "Recent branches:"
    local i=1
    while IFS= read -r branch; do
        echo "$i) $branch"
        ((i++))
    done <<< "$branches"

    local count=$((i-1))
    read -p "Select branch [1-$count]: " selection

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$count" ]; then
        echo "Invalid selection"
        return 1
    fi

    local target=$(echo "$branches" | sed -n "${selection}p")
    git switch "$target"
}

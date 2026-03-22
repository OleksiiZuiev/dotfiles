---
description: Bookmark the current session with a name for cross-repo resuming
allowed-tools: Bash(bash:*)
argument-hint: "<name>"
---

{{#if $ARGUMENTS}}
Run this command and show the output to the user:

```bash
bash C:/work/github/OleksiiZuiev/dotfiles/claude/scripts/namex.sh "{{$ARGUMENTS}}"
```
{{else}}
No name provided. Usage: `/namex <name>`

Example: `/namex permissions-strategy`
{{/if}}

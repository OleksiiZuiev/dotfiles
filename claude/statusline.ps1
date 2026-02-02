# Read JSON input from stdin
$inputText = [Console]::In.ReadToEnd()
$data = $inputText | ConvertFrom-Json

# Extract model and directory
$model = $data.model.display_name
$currentDir = Split-Path -Leaf $data.workspace.current_dir

# Get git branch if in a git repo
$gitBranch = ""
$branch = git rev-parse --abbrev-ref HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $branch) {
    $gitBranch = " | $branch"
}

# Output status line (Write-Output to avoid extra formatting)
Write-Output "$model | $currentDir$gitBranch"

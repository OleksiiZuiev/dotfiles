<#
Claude Code notification hook — emits a sticky Windows toast for Stop /
Notification events. Uses BurntToast with Scenario Reminder + a Dismiss
button so the toast stays on screen until the user interacts with it.

Falls back to a console beep if BurntToast isn't available, and always
exits 0 so a missing module never breaks Claude Code.
#>

[CmdletBinding()]
param(
    [ValidateSet('Stop', 'Notification')]
    [string]$EventName = 'Stop'
)

$ErrorActionPreference = 'Continue'

try {
    $raw = [Console]::In.ReadToEnd()
    $payload = $null
    if ($raw) { try { $payload = $raw | ConvertFrom-Json } catch { } }

    # A fan-out wakes the main agent each time a sub-agent or teammate finishes, and
    # every wake-up ends in its own Stop event. Toasting all of them buries the one
    # that means "your work is done", so a Stop with work still in flight stays
    # silent and the last one, once background_tasks has drained, toasts. Input is
    # never missed: permission_prompt / idle_prompt arrive as Notification, which
    # carries no background_tasks and so is never suppressed here.
    $running = @($payload.background_tasks | Where-Object { $_.status -eq 'running' }).Count

    # Toggled by a marker file rather than an env var, because hooks inherit the
    # Claude Code process environment and so an env gate can only be set at startup.
    if (Test-Path -LiteralPath "$env:USERPROFILE\.claude\hooks\toast-debug.on") {
        $decision = if ($running -gt 0) { "suppress(running=$running)" } else { 'toast' }
        Add-Content -LiteralPath "$env:USERPROFILE\.claude\hooks\toast-debug.log" `
            -Value "$((Get-Date).ToString('s'))`tEvent=$EventName`tdecision=$decision`traw=$raw" `
            -Encoding utf8
    }

    if ($running -gt 0) { exit 0 }

    $project = if ($payload -and $payload.cwd) { Split-Path $payload.cwd -Leaf } else { 'Claude Code' }

    $body = if ($payload -and $payload.message) {
        $payload.message
    } elseif ($EventName -eq 'Stop') {
        'Task complete'
    } else {
        'Awaiting input'
    }

    if ($body.Length -gt 120) { $body = $body.Substring(0, 117) + '...' }

    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        [Console]::Beep(800, 300)
        exit 0
    }

    Import-Module BurntToast -ErrorAction Stop

    $title  = New-BTText -Text "Claude Code - $project"
    $line   = New-BTText -Text $body
    $btn    = New-BTButton -Content 'Dismiss' -Dismiss
    $action = New-BTAction -Buttons $btn
    $bind   = New-BTBinding -Children $title, $line
    $visual = New-BTVisual -BindingGeneric $bind

    $audioSrc = if ($EventName -eq 'Notification') {
        'ms-winsoundevent:Notification.Reminder'
    } else {
        'ms-winsoundevent:Notification.IM'
    }
    $audio = New-BTAudio -Source $audioSrc

    $content = New-BTContent -Visual $visual -Actions $action -Audio $audio `
        -Scenario Reminder -Duration Long
    Submit-BTNotification -Content $content
} catch {
    try { [Console]::Beep(800, 300) } catch { }
}

exit 0

# DaGuild switch table (dot-sourced by the daguild PowerShell hooks; twin of config.sh, which is the
# primary implementation and the reference for every rule below).
# Sources, later wins: <plugin root>/config/defaults.conf, ~/.claude/daguild.conf,
# <project>/.claude/daguild.conf. Missing or unreadable files are skipped silently.
# Grammar per line: blank or `#` comment ignored; otherwise `name = value`, optional spaces
# around `=`, names matching ^[a-z][a-z0-9_.]*$, values on|off|true|false|yes|no in any case.
# Any other line (inline comments included) is ignored silently. The defaults file declares the
# known switches; a switch the defaults file does not declare is ignored in the user and project
# files and reads as on. Lines are only matched against that grammar, never expanded or executed.
# git.handling is not a conf switch: a line for it is ignored in every file, the defaults file
# included. The plugin option CLAUDE_PLUGIN_OPTION_GIT_HANDLING (install prompt or /config) is
# its only source: true|1|on|yes in any case is on, any other value is off, unset reads as off.
# The defaults file is read from CLAUDE_PLUGIN_ROOT only; when it is unset no defaults file is
# read (the hooks exit before dot-sourcing this file in that case). The release build compiles
# the defaults in: it replaces that read with one declare line per defaults file entry.
# The home directory is HOME, as in the sh twin; when HOME is unset (the usual case on Windows
# outside Git Bash) it is the user profile directory, so ~/.claude/daguild.conf is still read.
# Every comparison is ordinal and every case fold is ASCII-only, as in the C locale.
# Windows PowerShell 5.1 compatible syntax.
Set-StrictMode -Version 2.0

$DAGUILD_SWITCHES = New-Object System.Collections.Specialized.OrderedDictionary -ArgumentList ([System.StringComparer]::Ordinal)
$DAGUILD_DEFAULTS = New-Object System.Collections.Specialized.OrderedDictionary -ArgumentList ([System.StringComparer]::Ordinal)
$DAGUILD_UTF8 = New-Object System.Text.UTF8Encoding -ArgumentList $false, $false
# [[:space:]] in the C locale.
$DAGUILD_SPACE_CHARACTERS = [char[]]@(32, 9, 10, 11, 12, 13)

# Fills DAGUILD_SWITCHES: name -> on|off, one entry per switch, in declaration order.
# DAGUILD_DEFAULTS keeps the same table as declared by the defaults file alone.
function Import-DaGuildConfig {
    $DAGUILD_SWITCHES.Clear()
    Read-DaGuildDefaultsFile
    $DAGUILD_DEFAULTS.Clear()
    foreach ($name in @($DAGUILD_SWITCHES.Keys)) { $DAGUILD_DEFAULTS[$name] = $DAGUILD_SWITCHES[$name] }
    $userHome = Get-DaGuildHome
    if ($userHome -ne '') { Read-DaGuildConfigFile ($userHome + '/.claude/daguild.conf') 'override' }
    $projectDirectory = Get-DaGuildProjectDir
    if ($projectDirectory -ne '') { Read-DaGuildConfigFile ($projectDirectory + '/.claude/daguild.conf') 'override' }
    Set-DaGuildOption
}

# True when switch NAME is on. A switch with no entry takes its built-in default.
function Get-DaGuildSwitch([string]$Name) {
    return (Get-DaGuildTableValue $DAGUILD_SWITCHES $Name) -ceq 'on'
}

# The name=on / name=off entries whose value differs from the shipped default, sorted by name,
# space separated; empty when every switch holds its default.
function Get-DaGuildChangedSwitches {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($name in $DAGUILD_SWITCHES.Keys) {
        if ($DAGUILD_SWITCHES[$name] -cne (Get-DaGuildTableValue $DAGUILD_DEFAULTS $name)) { $names.Add($name) }
    }
    $sortedNames = $names.ToArray()
    [System.Array]::Sort($sortedNames, [System.StringComparer]::Ordinal)
    return ((@($sortedNames) | ForEach-Object { $_ + '=' + $DAGUILD_SWITCHES[$_] }) -join ' ')
}

# Splits TEXT the way a `while read -r line || [ -n "$line" ]` loop does: on LF only, a final
# line without LF kept, no empty line after a trailing LF. Carriage returns stay in the lines.
function Split-DaGuildLines([string]$Text) {
    $lines = New-Object System.Collections.Generic.List[string]
    if ($Text -ne '') { $lines.AddRange([string[]]$Text.Split([char]10)) }
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ceq '') { $lines.RemoveAt($lines.Count - 1) }
    return , $lines.ToArray()
}

# TEXT without the C-locale whitespace around it.
function Get-DaGuildTrimmed([string]$Text) {
    return $Text.Trim($DAGUILD_SPACE_CHARACTERS)
}

# Each reader names its variable literally: the Claude Directory validator refuses a variable
# name assembled at run time, so there is no generic reader that takes the name.
function Get-DaGuildPluginRoot {
    return [string][System.Environment]::GetEnvironmentVariable('CLAUDE_PLUGIN_ROOT')
}

# The project directory from CLAUDE_PROJECT_DIR; empty when unset.
function Get-DaGuildProjectDir {
    return [string][System.Environment]::GetEnvironmentVariable('CLAUDE_PROJECT_DIR')
}

# The defaults file under the plugin root; skipped when CLAUDE_PLUGIN_ROOT is unset.
function Read-DaGuildDefaultsFile {
    # Release build anchor: the only code line naming the defaults file, holding the whole read so
    # the generated declare lines replace all of it. Rewriting it or adding a second such line
    # breaks the release build.
    if ((Get-DaGuildPluginRoot) -ne '') { Read-DaGuildConfigFile ((Get-DaGuildPluginRoot) + '/config/defaults.conf') 'declare' }
}

function Get-DaGuildHome {
    $userHome = [string][System.Environment]::GetEnvironmentVariable('HOME')
    if ($userHome -eq '') { $userHome = [System.Environment]::GetFolderPath('UserProfile') }
    return [string]$userHome
}

# TABLE NAME: NAME's state in TABLE, else its built-in default.
function Get-DaGuildTableValue($Table, [string]$Name) {
    if ($Table.Contains($Name)) { return [string]$Table[$Name] }
    return Get-DaGuildBuiltinDefault $Name
}

# Built-in defaults for a switch no defaults file declares: git.handling is opt-in, the rest on.
function Get-DaGuildBuiltinDefault([string]$Name) {
    if ($Name -ceq 'git.handling') { return 'off' }
    return 'on'
}

# FILE MODE: applies every valid line; MODE declare accepts new switches, override only known ones.
function Read-DaGuildConfigFile([string]$Path, [string]$Mode) {
    if (-not [System.IO.File]::Exists($Path)) { return }
    try {
        $text = $DAGUILD_UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
    } catch {
        return
    }
    foreach ($line in (Split-DaGuildLines $text)) { Add-DaGuildConfigLine $line $Mode }
}

function Add-DaGuildConfigLine([string]$Line, [string]$Mode) {
    $text = Remove-DaGuildCarriageReturn $Line
    $equals = $text.IndexOf([char]'=')
    if ($equals -lt 0) { return }
    $name = Get-DaGuildTrimmed $text.Substring(0, $equals)
    $state = ConvertTo-DaGuildState (Get-DaGuildTrimmed $text.Substring($equals + 1))
    # git.handling comes from the plugin option only.
    if (-not (Test-DaGuildName $name) -or $null -eq $state -or $name -ceq 'git.handling') { return }
    if (-not $DAGUILD_SWITCHES.Contains($name) -and $Mode -cne 'declare') { return }
    $DAGUILD_SWITCHES[$name] = $state
}

# LINE without one trailing carriage return.
function Remove-DaGuildCarriageReturn([string]$Line) {
    if ($Line.EndsWith([string][char]13, [System.StringComparison]::Ordinal)) {
        return $Line.Substring(0, $Line.Length - 1)
    }
    return $Line
}

function Test-DaGuildName([string]$Name) {
    return $Name -cmatch '^[a-z][a-z0-9_.]*\z'
}

# on, off, or $null for a value outside the grammar.
function ConvertTo-DaGuildState([string]$Value) {
    if ($Value -cmatch '^([Oo][Nn]|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss])\z') { return 'on' }
    if ($Value -cmatch '^([Oo][Ff][Ff]|[Ff][Aa][Ll][Ss][Ee]|[Nn][Oo])\z') { return 'off' }
    return $null
}

# Maps the git handling plugin option, when set (even to an empty value), onto git.handling.
function Set-DaGuildOption {
    $option = [System.Environment]::GetEnvironmentVariable('CLAUDE_PLUGIN_OPTION_GIT_HANDLING')
    if ($null -eq $option) { return }
    if ($option -cmatch '^([Tt][Rr][Uu][Ee]|1|[Oo][Nn]|[Yy][Ee][Ss])\z') {
        $DAGUILD_SWITCHES['git.handling'] = 'on'
    } else {
        $DAGUILD_SWITCHES['git.handling'] = 'off'
    }
}

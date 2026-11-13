<#
.SYNOPSIS
  Which parts of tools/check.ps1 a change needs (the unit tier, docs/CI.md).

.DESCRIPTION
  Reads the files changed against the merge-base with -Base (committed,
  uncommitted and untracked) and returns what the unit tier runs for them:
  the Godot tests to run or skip, whether FastSim-RS parity runs, and which
  FastSim checks. The integration tier (check.ps1 -Full) ignores this and runs
  everything.

  Rules (first match per file; the selection is the union over all files):
    docs        *.md, docs/**                     -> nothing
    rust        tools/fastsim-rs/**               -> parity, every FastSim check but the integration ones
    sim shared  sim/** not listed below           -> every test but the goldens, parity, every FastSim check but sameseed
    sim local   sim/hazards/*.gd, sim/rooms/catalog_*.gd, sim/rooms/room_pacing.gd
                                                  -> the fast tests, parity, the room FastSim checks
                (boss files add bossfair; catalog and pacing files, which move the room draws,
                 add test_generated_variants)
    test file   tests/**/test_*.gd                -> that file
    support     tests/** other files              -> every test but the goldens
    game, meta, services, server, assets, scenes  -> the fast tests, plus the yardstick
                check when a painter or a view changed (visible.tsv)
    tools       tools/** other files              -> lint and the always set only
    anything else (project.godot, workflows ...)  -> the fast tests

  Always (when anything but docs changed): lint, format, import, load all.

.EXAMPLE
  $sel = & tools/ci/select_checks.ps1 -Base next-features-2
  powershell -ExecutionPolicy Bypass -File tools/ci/select_checks.ps1 -SelfTest
#>
param(
    [string]$Base = "next-features-2",
    [string[]]$Files = $null,
    [switch]$SelfTest
)

# Godot tests that only the integration tier runs (the slow whole-game ones).
$IntegrationTests = @(
    "tests/replay/test_golden_replays.gd",
    "tests/unit/test_generated_variants.gd",
    "tests/unit/test_portals.gd",
    "tests/unit/test_arrival_check.gd",
    "tests/sim/test_exits_reachable.gd",
    "tests/sim/test_crawl_passable.gd"
)
# FastSim checks that only the integration tier runs, and the ones a room change needs.
$IntegrationChecks = @("sameseed", "reach", "exits", "bossfair")
$RoomChecks = @("passable", "arrival", "revive", "points", "keys", "crawl", "gates", "isles", "rescued",
    "runs", "sight", "blind_seeds", "yardstick", "difficulty")
$AllChecks = $RoomChecks + $IntegrationChecks

function Select-Checks([string[]]$files) {
    $s = [ordered]@{
        docs_only = $true; godot = "none"; only = @(); skip = @(); parity = $false; checks = @(); why = @()
    }
    $fast = $false; $allButGolden = $false; $draws = $false
    $only = New-Object System.Collections.Generic.List[string]
    $checks = New-Object System.Collections.Generic.HashSet[string]
    foreach ($raw in $files) {
        $f = $raw.Replace("\", "/")
        if ($f.EndsWith(".uid")) { $f = $f.Substring(0, $f.Length - 4) }
        if ($f -match '\.md$' -or $f -match '^docs/') { continue }
        $s.docs_only = $false
        if ($f -match '^tools/fastsim-rs/') {
            $s.parity = $true
            foreach ($c in $RoomChecks) { [void]$checks.Add($c) }
            $s.why += "rust: $f"
        } elseif ($f -match '^sim/') {
            $local = $f -match '^sim/hazards/[^/]+\.gd$' -or $f -match '^sim/rooms/catalog_[^/]+\.gd$' -or $f -match '^sim/rooms/room_pacing\.gd$'
            $s.parity = $true
            if ($local) {
                $fast = $true
                foreach ($c in $RoomChecks) { [void]$checks.Add($c) }
                if ($f -match 'boss') { [void]$checks.Add("bossfair") }
                if ($f -match '^sim/rooms/(catalog_|room_pacing)') { $draws = $true }
                $s.why += "sim, one room or hazard: $f"
            } else {
                $allButGolden = $true
                foreach ($c in $AllChecks) { if ($c -ne "sameseed") { [void]$checks.Add($c) } }
                $s.why += "sim, shared: $f"
            }
        } elseif ($f -match '^tests/.*/test_[^/]+\.gd$' -or $f -match '^tests/test_[^/]+\.gd$') {
            $only.Add($f)
            $s.why += "test file: $f"
        } elseif ($f -match '^tests/') {
            $allButGolden = $true
            $s.why += "test support: $f"
        } elseif ($f -match '^(game|meta|services|server|assets)/' -or $f -match '\.tscn$') {
            $fast = $true
            if ($f -match '^game/run/') { [void]$checks.Add("yardstick") }
            $s.why += "game or services: $f"
        } elseif ($f -match '^tools/') {
            $s.why += "tool: $f"
        } else {
            $fast = $true
            $s.why += "other: $f"
        }
    }
    if ($allButGolden) {
        $s.godot = "all"; $s.skip = @("tests/replay/test_golden_replays.gd")
    } elseif ($fast) {
        $s.godot = "all"
        $s.skip = @($IntegrationTests | Where-Object { -not ($draws -and $_ -match 'test_generated_variants') })
    } elseif ($only.Count -gt 0) {
        $s.godot = "only"; $s.only = @($only | Select-Object -Unique)
    }
    # A test file that changed runs, even when it is an integration one.
    if ($only.Count -gt 0 -and $s.godot -eq "all") { $s.skip = @($s.skip | Where-Object { $only -notcontains $_ }) }
    if ($draws) { $s.why += "room draws moved: test_generated_variants runs too" }
    $s.checks = @($AllChecks | Where-Object { $checks.Contains($_) })
    return $s
}

function Get-ChangedFiles([string]$base) {
    $mb = (& git merge-base HEAD $base 2>$null)
    if (-not $mb) { return $null }
    $files = @(& git diff --name-only $mb 2>$null) + @(& git ls-files --others --exclude-standard 2>$null)
    return @($files | Where-Object { $_ } | Select-Object -Unique)
}

if ($SelfTest) {
    # Real commits of 2026-11-12/13 (git show --stat) and what they must select.
    $cases = @(
        @{ n = "8b05cc3 raft look"; f = @("game/run/bird_view.gd", "game/run/painters/lava_painter.gd", "tests/unit/test_lava_raft_look.gd");
           godot = "all"; parity = $false; has = @("yardstick"); hasnt = @("passable") },
        @{ n = "62aca6f lantern"; f = @("game/run/scenes/worlds/lantern.gd"); godot = "all"; parity = $false; has = @("yardstick"); hasnt = @() },
        @{ n = "c3ab062 pacing"; f = @("docs/ROOM_PACING.md", "sim/rooms/room_pacing.gd", "tools/fastsim-rs/sim/src/rooms/room_pacing.rs");
           godot = "all"; parity = $true; has = @("passable", "arrival"); hasnt = @("sameseed", "reach"); gen = $true },
        @{ n = "f7bc459 room fix"; f = @("sim/hazards/bouncer.gd", "sim/hazards/updraft.gd", "tests/unit/test_room_fixes.gd", "tools/fastsim-rs/sim/src/hazards/bouncer.rs");
           godot = "all"; parity = $true; has = @("passable", "revive"); hasnt = @("sameseed"); gen = $false },
        @{ n = "shared sim"; f = @("sim/game_sim.gd"); godot = "all"; parity = $true; has = @("reach", "exits", "bossfair"); hasnt = @("sameseed") },
        @{ n = "docs"; f = @("docs/CI.md", "README.md"); godot = "none"; parity = $false; has = @(); hasnt = @("yardstick") },
        @{ n = "a test"; f = @("tests/unit/test_leaderboard.gd"); godot = "only"; parity = $false; has = @(); hasnt = @("yardstick") },
        @{ n = "uid"; f = @("tests/unit/test_lava_rafts.gd.uid"); godot = "only"; parity = $false; has = @(); hasnt = @() }
    )
    $bad = 0
    foreach ($c in $cases) {
        $s = Select-Checks $c.f
        $errs = @()
        if ($s.godot -ne $c.godot) { $errs += "godot $($s.godot), want $($c.godot)" }
        if ($s.parity -ne $c.parity) { $errs += "parity $($s.parity), want $($c.parity)" }
        foreach ($x in $c.has) { if ($s.checks -notcontains $x) { $errs += "misses check $x" } }
        foreach ($x in $c.hasnt) { if ($s.checks -contains $x) { $errs += "runs check $x" } }
        if ($c.ContainsKey("gen")) {
            $runsGen = $s.godot -eq "all" -and -not ($s.skip -match 'test_generated_variants')
            if ($runsGen -ne $c.gen) { $errs += "generated_variants $runsGen, want $($c.gen)" }
        }
        if ($errs.Count) { $bad++; Write-Host "FAIL $($c.n): $($errs -join '; ')" } else { Write-Host "ok   $($c.n)" }
    }
    exit $bad
}

if ($null -eq $Files) { $Files = Get-ChangedFiles $Base }
if ($null -eq $Files) { return $null }
return Select-Checks $Files

#Requires -Version 7.0
<#
    Phase 0 baseline characterization tests for the SQL Power Doc modernization.

    These tests pin the CURRENT, pre-modernization state of the repository so that
    incidental regressions are caught while the planned work proceeds. Assertions
    that the modernization is expected to deliberately flip are tagged
    [CHARACTERIZATION] together with the plan work item that changes them; when that
    item lands, the assertion is updated in the same commit.

    Pester 5/6 note: variables assigned in BeforeDiscovery are not visible during the
    Run phase, so anything an It block needs is recomputed in BeforeAll. Discovery-phase
    state is used only to generate -ForEach data sets.

    Verified against pwsh 7.6.6 / .NET 10.0.12 on Linux.
#>

BeforeDiscovery {
    $discoveryRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

    $sourceFiles = Get-ChildItem -Path $discoveryRepoRoot -Recurse -Include '*.ps1', '*.psm1' -File |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|Tests)[\\/]' } |
        Sort-Object FullName

    $manifests = Get-ChildItem -Path (Join-Path $discoveryRepoRoot 'Modules') -Recurse -Filter '*.psd1' -File |
        Sort-Object Name

    $moduleFiles = Get-ChildItem -Path (Join-Path $discoveryRepoRoot 'Modules') -Recurse -Filter '*.psm1' -File |
        Sort-Object Name

    $encodingTargets = @($sourceFiles) + @($manifests) | Sort-Object FullName
}

BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

    function Get-RepoSourceFile {
        param([string[]]$Include = @('*.ps1', '*.psm1'))
        Get-ChildItem -Path $RepoRoot -Recurse -Include $Include -File |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|Tests)[\\/]' }
    }

    function Get-AstCommandCount {
        param([string]$Path, [string]$NamePattern)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -match $NamePattern
            }, $true).Count
    }

    # Manifests that cannot resolve their NestedModules by bare name off $env:PSModulePath.
    # Fixed by plan item W1-4 (switch to relative paths / RequiredModules).
    $ManifestsExpectedToFail = @('NetworkScan.psd1', 'SqlServerInventory.psd1', 'WindowsInventory.psd1')

    # Fails at SqlServerDatabaseEngineInformation.psm1:12100 because LoadWithPartialName
    # returns $null on .NET Core and `$null | ForEach-Object` still executes its body.
    # Fixed by plan item W3-1.
    $ModulesExpectedToFailImport = @('SqlServerDatabaseEngineInformation.psm1')
}

Describe 'Every PowerShell source file parses under PowerShell 7' {

    It '<_.Name> parses with no errors' -ForEach $sourceFiles {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)

        # Surface the actual messages rather than just a count, so a regression is diagnosable.
        $detail = ($errors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
        $errors.Count | Should -Be 0 -Because "the file must parse cleanly ($detail)"
    }

    It 'the en-dash operators in Tools/SQL Inventory.ps1 parse and evaluate' {
        # phase1_business_analysis.md claims these "will fail to parse". They do not:
        # PowerShell accepts en-dash and em-dash as operator/parameter prefixes.
        # Normalized to ASCII by plan item W1-2 for hygiene, not correctness.
        $enDash = [char]0x2013
        Invoke-Expression "1 ${enDash}le 37" | Should -BeTrue
    }
}

Describe 'Module manifests' {

    It '<_.Name> Test-ModuleManifest result is unchanged' -ForEach $manifests {
        $expectedToFail = $_.Name -in $ManifestsExpectedToFail

        $passed = try {
            $null = Test-ModuleManifest -Path $_.FullName -ErrorAction Stop -WarningAction SilentlyContinue
            $true
        } catch {
            $false
        }

        if ($expectedToFail) {
            # [CHARACTERIZATION] flipped to $true by W1-4.
            $passed | Should -BeFalse -Because 'NestedModules is resolved by bare name and cannot be found on Linux (W1-4)'
        } else {
            $passed | Should -BeTrue
        }
    }

    It '<_.Name> still uses the deprecated ModuleToProcess key' -ForEach $manifests {
        # [CHARACTERIZATION] inverted by W1-3 (ModuleToProcess -> RootModule).
        # Get-Content -Raw is encoding-aware: 4 of 7 manifests are UTF-16 and
        # byte-oriented tools silently miss them.
        Get-Content -Path $_.FullName -Raw | Should -Match 'ModuleToProcess' -Because 'W1-3 renames this to RootModule'
    }

    It 'RDS-Manager has no manifest' {
        # [CHARACTERIZATION] inverted by W1-5, which creates one.
        Test-Path (Join-Path $RepoRoot 'Modules/RDS-Manager/RDS-Manager.psd1') |
            Should -BeFalse -Because 'W1-5 creates this manifest'
    }
}

Describe 'Module import status on PowerShell 7' {

    It '<_.Name> import result is unchanged' -ForEach $moduleFiles {
        $expectedToFail = $_.Name -in $ModulesExpectedToFailImport

        # Import in a child process: a failed import can leave partial module state behind.
        $path = $_.FullName
        $result = pwsh -NoProfile -Command @"
try { Import-Module '$path' -Force -ErrorAction Stop; 'PASS' }
catch { 'FAIL: ' + `$_.Exception.Message }
"@ 2>&1 | Where-Object { $_ -match '^(PASS|FAIL)' } | Select-Object -First 1

        if ($expectedToFail) {
            # [CHARACTERIZATION] flipped to PASS by W3-1.
            $result | Should -BeLike 'FAIL*' -Because 'LoadWithPartialName returns $null on .NET Core (W3-1)'
        } else {
            $result | Should -Be 'PASS'
        }
    }
}

Describe 'WMI call-site burn-down' {

    BeforeAll {
        $WmiCallsByFile = @{}
        foreach ($file in (Get-RepoSourceFile)) {
            $n = Get-AstCommandCount -Path $file.FullName -NamePattern '^Get-WMI?Object$'
            if ($n -gt 0) { $WmiCallsByFile[$file.Name] = $n }
        }
    }

    # AST-derived counts, independently corroborated by PSScriptAnalyzer's
    # PSAvoidUsingWMICmdlet rule reporting 71 across the repository.
    # [CHARACTERIZATION] all driven to 0 by W2 (RDS-Manager pending open decision 2).
    It 'live Get-WmiObject call sites per file match the recorded baseline' {
        $WmiCallsByFile['WindowsMachineInformation.psm1'] | Should -Be 48
        $WmiCallsByFile['NetworkScan.psm1']               | Should -Be 14
        $WmiCallsByFile['RDS-Manager.psm1']               | Should -Be 8
        $WmiCallsByFile['SQL Inventory.ps1']              | Should -Be 1
    }

    It 'the repository-wide total is 71' {
        ($WmiCallsByFile.Values | Measure-Object -Sum).Sum | Should -Be 71
    }

    It 'no CIM cmdlet is called outside a platform abstraction module' {
        # Enforced going forward: CIM must only ever be reached through the
        # SqlPowerDoc.Platform seam, because CimCmdlets does not exist on Linux
        # and therefore cannot be mocked by Pester.
        $offenders = foreach ($file in (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Include '*.psm1' -File |
                Where-Object { $_.FullName -notmatch 'SqlPowerDoc\.Platform' })) {
            $n = Get-AstCommandCount -Path $file.FullName -NamePattern '^(Get|New|Set|Remove|Invoke)-Cim'
            if ($n -gt 0) { '{0} ({1})' -f $file.Name, $n }
        }

        $offenders | Should -BeNullOrEmpty -Because 'CIM must be reached through the SqlPowerDoc.Platform seam'
    }
}

Describe 'Excel COM surface' {

    It 'Excel COM instantiation sites match the recorded baseline' {
        # [CHARACTERIZATION] driven to 0 by W4.
        $counts = @{}
        foreach ($file in (Get-RepoSourceFile)) {
            $n = ([regex]::Matches((Get-Content -Path $file.FullName -Raw), 'New-Object\s+-Com(Object)?\s+Excel\.Application', 'IgnoreCase')).Count
            if ($n -gt 0) { $counts[$file.Name] = $n }
        }

        $counts['SqlServerInventory.psm1'] | Should -Be 3
        $counts['WindowsInventory.psm1']   | Should -Be 2
        $counts['SQL Inventory.ps1']       | Should -Be 1
        ($counts.Values | Measure-Object -Sum).Sum | Should -Be 6
    }
}

Describe 'Deprecated SMO assembly loading' {

    It 'LoadWithPartialName call sites match the recorded baseline' {
        # [CHARACTERIZATION] driven to 0 by W3-1.
        $counts = @{}
        foreach ($file in (Get-RepoSourceFile)) {
            $n = ([regex]::Matches((Get-Content -Path $file.FullName -Raw), 'LoadWithPartialName')).Count
            if ($n -gt 0) { $counts[$file.Name] = $n }
        }

        $counts['NetworkScan.psm1']                        | Should -Be 3
        $counts['SqlServerDatabaseEngineInformation.psm1']  | Should -Be 4
        $counts['SQL Inventory.ps1']                        | Should -Be 1
    }

    It 'LoadWithPartialName returns $null on this runtime' {
        # The root cause of the SqlServerDatabaseEngineInformation import failure.
        [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Should -BeNullOrEmpty
    }
}

Describe 'Platform reality checks that constrain the migration design' {

    It 'documents whether CimCmdlets is available on this platform' {
        $available = [bool](Get-Command Get-CimInstance -ErrorAction SilentlyContinue)
        if ($IsWindows) {
            $available | Should -BeTrue
        } else {
            # Not merely "present but throws PlatformNotSupportedException" as
            # phase1_research.md states: the module is not shipped at all, so the
            # command cannot even be resolved -- and therefore cannot be mocked.
            $available | Should -BeFalse
        }
    }

    It 'CimException resolves on every platform, so catch blocks are portable' {
        'Microsoft.Management.Infrastructure.CimException' -as [Type] | Should -Not -BeNullOrEmpty
    }

    It 'Pester cannot mock a command that does not exist, which is why the CIM seam is required' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Get-CimInstance exists on Windows and is mockable directly' }
        { Mock Get-CimInstance { } } | Should -Throw -ExpectedMessage '*Could not find Command Get-CimInstance*'
    }

    It 'Close-ExcelPackage has no -Save parameter' {
        # Several Phase 1 sample snippets end with `Close-ExcelPackage $pkg -Save`,
        # which binds as a prefix of -SaveAs and silently fails to write the file.
        Import-Module ImportExcel -ErrorAction Stop
        (Get-Command Close-ExcelPackage).Parameters.Keys | Should -Not -Contain 'Save'
        (Get-Command Close-ExcelPackage).Parameters.Keys | Should -Contain 'NoSave'
    }
}

Describe 'Source file encodings' {

    It '<_.Name> encoding matches the recorded baseline' -ForEach $encodingTargets {
        # [CHARACTERIZATION] all normalized to UTF-8 BOM by W1-1.
        $expected = @{
            'NetShell.psm1'                             = 'UTF-16 BE BOM'
            'NetShell.psd1'                             = 'UTF-16 LE BOM'
            'RDS-Manager.psm1'                          = 'UTF-16 LE BOM'
            'Convert-WindowsInventoryClixmlToExcel.ps1' = 'UTF-16 LE BOM'
            'SqlServerDatabaseEngineInformation.psd1'   = 'UTF-16 LE BOM'
            'SqlServerInventory.psd1'                   = 'UTF-16 LE BOM'
            'WindowsInventory.psd1'                     = 'UTF-16 LE BOM'
            'LogHelper.psd1'                            = 'UTF-8 BOM'
            'NetworkScan.psd1'                          = 'UTF-8 BOM'
            'WindowsMachineInformation.psd1'            = 'UTF-8 BOM'
            'SQL Inventory.ps1'                         = 'UTF-8 BOM'
        }

        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $actual =
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 'UTF-8 BOM' }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { 'UTF-16 BE BOM' }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { 'UTF-16 LE BOM' }
            else { 'UTF-8/ASCII no BOM' }

        $actual | Should -Be ($expected[$_.Name] ?? 'UTF-8/ASCII no BOM')
    }
}

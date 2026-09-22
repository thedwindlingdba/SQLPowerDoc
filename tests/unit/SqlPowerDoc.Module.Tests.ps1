#Requires -Version 7.4
<#
    Work item A1 — repository skeleton.

    Asserts the shape of the new module tree: the source manifest, the dev-mode loader,
    the InvokeBuild task file, and the pinned dependency manifest. Everything here is
    static analysis — nothing is imported and nothing is built — so the file runs on
    Linux with no SQL Server, no Windows, and no build output present.
#>

BeforeDiscovery {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
}

BeforeAll {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:SourceRoot = Join-Path $script:RepositoryRoot 'src' 'SqlPowerDoc'
    $script:ManifestPath = Join-Path $script:SourceRoot 'SqlPowerDoc.psd1'
    $script:LoaderPath = Join-Path $script:SourceRoot 'SqlPowerDoc.psm1'
    $script:BuildScriptPath = Join-Path $script:RepositoryRoot 'SqlPowerDoc.build.ps1'
    $script:RequiresPath = Join-Path $script:RepositoryRoot 'build.requires.psd1'

    function script:Test-PowerShellFileParses {
        param([Parameter(Mandatory)][string] $Path)

        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $tokens, [ref] $errors)
        , @($errors)
    }
}

Describe 'SqlPowerDoc repository layout' -Tag 'Unit' {

    It 'has a <_> directory' -ForEach @(
        'src/SqlPowerDoc'
        'src/SqlPowerDoc/Classes'
        'src/SqlPowerDoc/Private'
        'src/SqlPowerDoc/Public'
        'src/SqlPowerDoc/en-US'
        'tests/unit'
        'tests/integration'
        'tests/fixtures'
        'build'
    ) {
        Join-Path $script:RepositoryRoot $_ | Should -Exist
    }

    It 'leaves the legacy Modules tree in place until work item E5' {
        Join-Path $script:RepositoryRoot 'Modules' | Should -Exist
    }

    It 'ignores build output in .gitignore' {
        $gitignore = Get-Content -Path (Join-Path $script:RepositoryRoot '.gitignore') -Raw
        $gitignore | Should -Match '(?m)^output/'
        $gitignore | Should -Match '(?m)^\*\.nupkg'
    }
}

Describe 'SqlPowerDoc source manifest' -Tag 'Unit' {

    BeforeAll {
        $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
    }

    It 'is a valid module manifest' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'declares the dev-mode loader as its root module' {
        $script:Manifest.RootModule | Should -Be 'SqlPowerDoc.psm1'
    }

    It 'requires PowerShell 7.4' {
        $script:Manifest.PowerShellVersion | Should -Be '7.4'
    }

    It 'targets PowerShell Core only' {
        $script:Manifest.CompatiblePSEditions | Should -Be @('Core')
    }

    It 'is version 3.0.0' {
        $script:Manifest.ModuleVersion | Should -Be '3.0.0'
    }

    It 'carries a real GUID' {
        $script:Manifest.GUID | Should -Not -Be '00000000-0000-0000-0000-000000000000'
        { [guid]::Parse($script:Manifest.GUID) } | Should -Not -Throw
    }

    It 'declares <_> as a runtime dependency' -ForEach @('dbatools', 'PSFramework', 'ImportExcel') {
        $script:Manifest.RequiredModules.ModuleName | Should -Contain $_
    }

    It 'declares no dependency on the excluded SqlServer module' {
        $script:Manifest.RequiredModules.ModuleName | Should -Not -Contain 'SqlServer'
    }

    It 'declares exactly three runtime dependencies' {
        $script:Manifest.RequiredModules | Should -HaveCount 3
    }

    It 'exports every function in dev mode so the loader is not filtered (plan section 2.2)' {
        $script:Manifest.FunctionsToExport | Should -Be '*'
    }

    It 'exports no cmdlets, variables, or aliases' {
        $script:Manifest.CmdletsToExport | Should -BeNullOrEmpty
        $script:Manifest.VariablesToExport | Should -BeNullOrEmpty
        $script:Manifest.AliasesToExport | Should -BeNullOrEmpty
    }

    It 'declares no nested modules' {
        $script:Manifest.NestedModules | Should -BeNullOrEmpty
    }
}

Describe 'SqlPowerDoc dev-mode loader' -Tag 'Unit' {

    It 'exists' {
        $script:LoaderPath | Should -Exist
    }

    It 'parses without errors' {
        script:Test-PowerShellFileParses -Path $script:LoaderPath | Should -HaveCount 0
    }

    It 'dot-sources Classes, Private, and Public in that order' {
        $content = Get-Content -Path $script:LoaderPath -Raw
        $content | Should -Match "'Classes',\s*'Private',\s*'Public'"
    }

    It 'exports the Public directory as the module surface' {
        Get-Content -Path $script:LoaderPath -Raw | Should -Match 'Export-ModuleMember'
    }

    It 'contains no using statements (plan section 2.6)' {
        Get-Content -Path $script:LoaderPath -Raw | Should -Not -Match '(?m)^\s*using\s+(module|namespace)\b'
    }

    It 'imports without error' {
        { Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
        Remove-Module -Name 'SqlPowerDoc' -Force -ErrorAction SilentlyContinue
    }
}

Describe 'SqlPowerDoc ModuleBuilder configuration' -Tag 'Unit' {

    BeforeAll {
        $script:BuildConfigPath = Join-Path $script:SourceRoot 'build.psd1'
    }

    It 'exists' {
        $script:BuildConfigPath | Should -Exist
    }

    It 'assembles Classes, Private, and Public in that order' {
        $config = Import-PowerShellDataFile -Path $script:BuildConfigPath
        $config.SourceDirectories | Should -Be @('Classes', 'Private', 'Public')
    }

    It 'points at the source manifest' {
        (Import-PowerShellDataFile -Path $script:BuildConfigPath).Path | Should -Be 'SqlPowerDoc.psd1'
    }
}

Describe 'SqlPowerDoc InvokeBuild task file' -Tag 'Unit' {

    It 'exists at the repository root' {
        $script:BuildScriptPath | Should -Exist
    }

    It 'parses without errors' {
        script:Test-PowerShellFileParses -Path $script:BuildScriptPath | Should -HaveCount 0
    }

    It 'defines the <_> task' -ForEach @('Clean', 'Build', 'Lint', 'Test', 'Package') {
        Get-Content -Path $script:BuildScriptPath -Raw | Should -Match "(?m)^task\s+$_\b"
    }

    It 'exposes the expected task list to InvokeBuild' {
        $tasks = Invoke-Build -File $script:BuildScriptPath -Task '??'
        $tasks.Keys | Should -Contain 'Clean'
        $tasks.Keys | Should -Contain 'Build'
        $tasks.Keys | Should -Contain 'Lint'
        $tasks.Keys | Should -Contain 'Test'
        $tasks.Keys | Should -Contain 'Package'
        $tasks.Keys | Should -Contain '.'
    }
}

Describe 'SqlPowerDoc pinned dependencies' -Tag 'Unit' {

    BeforeAll {
        $script:Requires = Import-PowerShellDataFile -Path $script:RequiresPath
    }

    It 'exists and parses' {
        $script:RequiresPath | Should -Exist
        $script:Requires | Should -Not -BeNullOrEmpty
    }

    It 'pins <_>' -ForEach @(
        'InvokeBuild'
        'ModuleBuilder'
        'PSModuleDevelopment'
        'Pester'
        'PSScriptAnalyzer'
        'dbatools'
        'PSFramework'
        'ImportExcel'
    ) {
        $script:Requires.Keys | Should -Contain $_
        $script:Requires[$_].version | Should -Not -BeNullOrEmpty
    }

    It 'does not pin the excluded SqlServer module' {
        $script:Requires.Keys | Should -Not -Contain 'SqlServer'
    }

    It 'installs through PSResourceGet with -Prerelease and never through the retired installer' {
        $installer = Join-Path $script:RepositoryRoot 'build' 'Install-DevDependencies.ps1'
        $installer | Should -Exist

        $content = Get-Content -Path $installer -Raw
        $content | Should -Match 'Install-PSResource'
        $content | Should -Match '-Prerelease'
        $content | Should -Not -Match 'Install-Module'

        script:Test-PowerShellFileParses -Path $installer | Should -HaveCount 0
    }
}

Describe 'SqlPowerDoc Pester configuration' -Tag 'Unit' {

    BeforeAll {
        $script:PesterConfigPath = Join-Path $script:RepositoryRoot 'tests' 'PesterConfiguration.ps1'
    }

    It 'exists and parses' {
        $script:PesterConfigPath | Should -Exist
        script:Test-PowerShellFileParses -Path $script:PesterConfigPath | Should -HaveCount 0
    }

    It 'returns a Pester configuration that excludes Windows-only tests on this host' {
        $configuration = & $script:PesterConfigPath

        $configuration | Should -BeOfType ([PesterConfiguration])
        $configuration.Run.Throw.Value | Should -BeTrue

        $isWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::Windows)
        if (-not $isWindows) {
            $configuration.Filter.ExcludeTag.Value | Should -Contain 'RequiresWindows'
        }
        if (-not $env:SQLPOWERDOC_TEST_INSTANCE) {
            $configuration.Filter.ExcludeTag.Value | Should -Contain 'RequiresSql'
        }
    }
}

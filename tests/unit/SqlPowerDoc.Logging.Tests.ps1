#Requires -Version 7.4
<#
    Work item A6 - PSFramework logging provider initialisation.

    Asserts that importing SqlPowerDoc registers and enables a `logfile` provider instance
    named `SqlPowerDoc` (the direct replacement for the deleted `LogHelper.Set-LogFile`,
    plan section 3.12), that emitting a message through it never throws, and that the module's
    info/verbose routing respects PSFramework's standard level configuration.
#>

BeforeAll {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ManifestPath = Join-Path $script:RepositoryRoot 'src' 'SqlPowerDoc' 'SqlPowerDoc.psd1'

    Import-Module PSFramework -ErrorAction Stop
    Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'SqlPowerDoc' -Force -ErrorAction SilentlyContinue
}

Describe 'SqlPowerDoc logging provider' -Tag 'Unit' {

    It 'registers a logfile provider instance named SqlPowerDoc' {
        $provider = Get-PSFLoggingProvider -Name 'logfile'
        $provider.Instances.Keys | Should -Contain 'SqlPowerDoc'
    }

    It 'enables the SqlPowerDoc logfile instance' {
        $provider = Get-PSFLoggingProvider -Name 'logfile'
        $provider.Instances['SqlPowerDoc'].Enabled | Should -BeTrue
    }

    It 'initialises the SqlPowerDoc logfile instance' {
        $provider = Get-PSFLoggingProvider -Name 'logfile'
        $provider.Instances['SqlPowerDoc'].Initialized | Should -BeTrue
    }

    It 'does not throw when writing a message at any documented level' -ForEach @(
        'Host', 'Significant', 'Verbose', 'Warning', 'Debug'
    ) {
        { Write-PSFMessage -Level $_ -Message "A6 logging smoke test at level $_" -ModuleName 'SqlPowerDoc' } |
            Should -Not -Throw
    }

    It 'records written messages in the in-memory message log' {
        $marker = "A6-marker-$([guid]::NewGuid())"
        Write-PSFMessage -Level Verbose -Message $marker -ModuleName 'SqlPowerDoc'

        $recorded = Get-PSFMessage -ModuleName 'SqlPowerDoc' | Where-Object { $_.Message -eq $marker }
        $recorded | Should -Not -BeNullOrEmpty
    }

    It 'does not throw waiting for the message queue to drain' {
        { Wait-PSFMessage -Timeout '5s' } | Should -Not -Throw
    }

    Context 'log level configuration' {

        BeforeAll {
            $script:OriginalVerbosePreference = $VerbosePreference
        }

        AfterAll {
            $VerbosePreference = $script:OriginalVerbosePreference
        }

        It 'writes a Verbose-level message to the verbose stream when verbosity is enabled' {
            $VerbosePreference = 'Continue'
            $marker = "A6-verbose-shown-$([guid]::NewGuid())"

            $captured = Write-PSFMessage -Level Verbose -Message $marker -ModuleName 'SqlPowerDoc' 4>&1

            $captured | Out-String | Should -Match ([regex]::Escape($marker))
        }

        It 'suppresses a Verbose-level message from the verbose stream when verbosity is disabled' {
            $VerbosePreference = 'SilentlyContinue'
            $marker = "A6-verbose-hidden-$([guid]::NewGuid())"

            $captured = Write-PSFMessage -Level Verbose -Message $marker -ModuleName 'SqlPowerDoc' 4>&1

            $captured | Should -BeNullOrEmpty
        }
    }
}

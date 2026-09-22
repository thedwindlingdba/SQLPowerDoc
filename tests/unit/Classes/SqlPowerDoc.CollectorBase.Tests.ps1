#Requires -Version 7.4
<#
    Work item: B5 - SqlPowerDocCollectorBase (plan section 4, B5; code in section 3.5).

    SqlPowerDocCollectorBase is the template every data collector (machine info, SQL server
    info, network scan) derives from. It owns four things no individual collector should have
    to reimplement: a Platform seam, a Status/Scope pair a caller can inspect and filter on,
    timing, and error aggregation that never throws out of a partially-successful collection.

    Everything runs inside InModuleScope: Import-Module does not export class or enum types to
    the caller's scope - only `using module` does - so a type lookup from the test's own scope
    returns $null however correct the module is.

    SqlPowerDocFakePlatform (Classes/12-) stands in for SqlPowerDocPlatform here for the same
    reason A7/A8's tests use it: it is the only platform seam that resolves and behaves
    predictably on a Linux control host with no CimCmdlets module.
#>

BeforeAll {
    $script:BuiltManifest = Join-Path $PSScriptRoot '..' '..' '..' 'output' 'SqlPowerDoc' '3.0.0' 'SqlPowerDoc.psd1'
    Import-Module -Name PSFramework -ErrorAction SilentlyContinue
    Import-Module -Name $script:BuiltManifest -Force -ErrorAction Stop
}

Describe 'SqlPowerDocCollectorStatus' -Tag 'Unit' {

    It 'declares the four lifecycle states a collector passes through' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocCollectorStatus' -as [type]
            $type | Should -Not -BeNullOrEmpty -Because 'plan section 4, B5 requires a status enum for SqlPowerDocCollectorBase'
            $type.IsEnum | Should -BeTrue

            [enum]::GetNames($type) | Should -Be @('NotStarted', 'Running', 'Completed', 'Failed')
        }
    }
}

Describe 'SqlPowerDocCollectorBase construction' -Tag 'Unit' {

    It 'derives from SqlPowerDocBase so every collector logs and reads configuration the same way' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocCollectorBase' -as [type]
            $type | Should -Not -BeNullOrEmpty -Because 'plan section 4, B5 lists Classes/40-SqlPowerDocCollectorBase.ps1'
            $type.BaseType.Name | Should -Be 'SqlPowerDocBase'
        }
    }

    It 'can be instantiated with a platform and stores it' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $platform = [SqlPowerDocFakePlatform]::new()
            $collector = [SqlPowerDocCollectorBase]::new($platform)

            $collector.Platform | Should -Be $platform
        }
    }

    It 'accepts a PSCmdlet so collector log lines are attributed to the calling wrapper' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            function Invoke-B5ConstructionProbe {
                [CmdletBinding()]
                param()
                $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new(), $PSCmdlet)
                $collector.Start()
                $collector
            }

            $collector = Invoke-B5ConstructionProbe
            $collector.Platform | Should -Not -BeNullOrEmpty
        }

        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            $PesterBoundParameters.ContainsKey('PSCmdlet') -and
            $PesterBoundParameters.FunctionName -eq 'Invoke-B5ConstructionProbe'
        }
    }

    It 'initialises Errors to an empty, usable list' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())

            # An empty generic list unwraps to nothing across the pipeline, so the list itself
            # (not its enumerated contents) is asserted directly here.
            $null -eq $collector.Errors | Should -BeFalse -Because 'the list instance itself must exist, even though it starts empty'
            $collector.Errors.Count | Should -Be 0
        }
    }

    It 'starts life with Status NotStarted' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())

            $collector.Status | Should -Be ([SqlPowerDocCollectorStatus]::NotStarted)
        }
    }
}

Describe 'SqlPowerDocCollectorBase.Start' -Tag 'Unit' {

    It 'sets Status to Running and records a start time' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $before = [datetime]::UtcNow
            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.Start()
            $after = [datetime]::UtcNow

            $collector.Status | Should -Be ([SqlPowerDocCollectorStatus]::Running)

            # Duration is computed relative to the recorded start time in Complete(); the most
            # direct way to prove Start() actually recorded 'now' is to observe its effect there.
            Start-Sleep -Milliseconds 20
            $collector.Complete()

            $collector.Duration.TotalMilliseconds | Should -BeGreaterThan 0
            $collector.Duration.TotalSeconds | Should -BeLessThan 5 -Because 'the recorded start time must be close to Start-Sleep''s window, not epoch/default'
        }
    }

    It 'logs a Verbose message naming the collector' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new()).Start()
        }

        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            "$($PesterBoundParameters.Level)" -eq 'Verbose' -and
            $PesterBoundParameters.Message -match 'Starting collection'
        }
    }
}

Describe 'SqlPowerDocCollectorBase.Complete' -Tag 'Unit' {

    It 'computes a non-negative Duration from the recorded start time' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.Start()
            Start-Sleep -Milliseconds 10
            $collector.Complete()

            $collector.Duration | Should -BeOfType [timespan]
            $collector.Duration.Ticks | Should -BeGreaterThan 0
        }
    }

    It 'sets Status to Completed when no errors were recorded' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.Start()
            $collector.Complete()

            $collector.Status | Should -Be ([SqlPowerDocCollectorStatus]::Completed)
        }
    }

    It 'sets Status to Failed when at least one error was recorded' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.Start()
            $collector.AddError('GetBios', [System.InvalidOperationException]::new('WMI class missing'))
            $collector.Complete()

            $collector.Status | Should -Be ([SqlPowerDocCollectorStatus]::Failed)
        }
    }

    It 'logs a Verbose message reporting duration and error count' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.Start()
            $collector.Complete()
        }

        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            "$($PesterBoundParameters.Level)" -eq 'Verbose' -and
            $PesterBoundParameters.Message -match 'Collection completed'
        }
    }
}

Describe 'SqlPowerDocCollectorBase.AddError' -Tag 'Unit' {

    It 'appends one entry per call with Operation, Message, Timestamp, and the exception itself' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $exception = [System.InvalidOperationException]::new('WMI class missing')

            $collector.AddError('GetBios', $exception)

            $collector.Errors.Count | Should -Be 1
            $entry = $collector.Errors[0]
            $entry['Operation'] | Should -Be 'GetBios'
            $entry['Message'] | Should -Be 'WMI class missing'
            $entry['Exception'] | Should -Be $exception
            $entry['Timestamp'] | Should -BeOfType [datetime]
        }
    }

    It 'accumulates errors across multiple calls without overwriting earlier ones' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.AddError('GetBios', [System.InvalidOperationException]::new('first failure'))
            $collector.AddError('GetProcessor', [System.InvalidOperationException]::new('second failure'))

            $collector.Errors.Count | Should -Be 2
            $collector.Errors[0]['Operation'] | Should -Be 'GetBios'
            $collector.Errors[1]['Operation'] | Should -Be 'GetProcessor'
        }
    }

    It 'logs a Warning naming the operation and the exception message' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.AddError('GetBios', [System.InvalidOperationException]::new('WMI class missing'))
        }

        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            "$($PesterBoundParameters.Level)" -eq 'Warning' -and
            $PesterBoundParameters.Message -match 'GetBios' -and
            $PesterBoundParameters.Message -match 'WMI class missing'
        }
    }
}

Describe 'SqlPowerDocCollectorBase.ShouldCollect' -Tag 'Unit' {

    It 'returns true when Scope contains every bit of the required scope' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.Scope = [SqlPowerDocCollectionScope]::Hardware -bor [SqlPowerDocCollectionScope]::Network

            $collector.ShouldCollect([SqlPowerDocCollectionScope]::Hardware) | Should -BeTrue
            $collector.ShouldCollect([SqlPowerDocCollectionScope]::Network) | Should -BeTrue
        }
    }

    It 'returns false when Scope is missing a bit of the required scope' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.Scope = [SqlPowerDocCollectionScope]::Hardware

            $collector.ShouldCollect([SqlPowerDocCollectionScope]::Network) | Should -BeFalse
            $collector.ShouldCollect([SqlPowerDocCollectionScope]::Hardware -bor [SqlPowerDocCollectionScope]::Network) |
                Should -BeFalse -Because 'Scope does not carry the Network bit the caller asked for'
        }
    }

    It 'returns true for every section once Scope is All' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.Scope = [SqlPowerDocCollectionScope]::All

            foreach ($section in [enum]::GetValues([SqlPowerDocCollectionScope])) {
                $collector.ShouldCollect($section) | Should -BeTrue -Because "$section must be reachable once every bit is set"
            }
        }
    }

    It 'returns false for every non-None section when Scope is None' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.Scope = [SqlPowerDocCollectionScope]::None

            $sections = @(
                [enum]::GetValues([SqlPowerDocCollectionScope]) |
                    Where-Object { $_ -ne [SqlPowerDocCollectionScope]::None }
            )

            foreach ($section in $sections) {
                $collector.ShouldCollect($section) | Should -BeFalse -Because "$section requires a bit Scope::None does not have"
            }
        }
    }
}

Describe 'SqlPowerDocCollectorBase logging inheritance' -Tag 'Unit' {

    It 'reaches the real PSFramework message log through the inherited Log method' {
        $message = 'b5-collector-base-log-{0}' -f [guid]::NewGuid()

        InModuleScope SqlPowerDoc -Parameters @{ Text = $message } {
            ('SqlPowerDocCollectorBase' -as [type]) | Should -Not -BeNullOrEmpty

            $collector = [SqlPowerDocCollectorBase]::new([SqlPowerDocFakePlatform]::new())
            $collector.Log('Verbose', $Text)
        }

        $entry = Get-PSFMessage | Where-Object { $_.Message -eq $message } | Select-Object -Last 1

        $entry | Should -Not -BeNullOrEmpty
        $entry.ModuleName | Should -Be 'SqlPowerDoc'
        $entry.FunctionName | Should -Be 'SqlPowerDocCollectorBase'
        "$($entry.Level)" | Should -Be 'Verbose'
    }
}

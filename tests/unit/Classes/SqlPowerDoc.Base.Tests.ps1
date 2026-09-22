#Requires -Version 7.4
<#
    Work item: A4 - enums, exceptions, SqlPowerDocBase (plan section 4, A4; code in section 3.1).
    Gate (plan section 4, A4): "unit tests asserting Log passes -FunctionName and -PSCmdlet, that
    Config falls back when a key is absent, and that each exception type carries Target through all
    three constructors."

    Why -FunctionName and -PSCmdlet are worth testing: PSFramework infers module and function from
    the call stack, and that inference yields '<Unknown>' when the caller is a class method (plan
    section 3.1). Every log line the module emits from a class - which is most of them - depends on
    this one method getting the attribution right.

    Mock assertions read $PesterBoundParameters rather than the parameter variables whenever they
    care whether an argument was passed at all: $PSCmdlet is an automatic variable in any advanced
    function on the stack, so a bare "$null -eq $PSCmdlet" filter cannot tell "not passed" from
    "passed".
#>

BeforeAll {
    $script:BuiltManifest = Join-Path $PSScriptRoot '..' '..' '..' 'output' 'SqlPowerDoc' '3.0.0' 'SqlPowerDoc.psd1'
    Import-Module -Name PSFramework -ErrorAction SilentlyContinue
    Import-Module -Name $script:BuiltManifest -Force -ErrorAction Stop
}

Describe 'SqlPowerDocBase construction' -Tag 'Unit' {

    It 'constructs with no arguments so derived classes can chain to base()' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty -Because 'plan section 2.3 lists Classes/10-SqlPowerDocBase.ps1'

            $instance = [SqlPowerDocBase]::new()

            $instance | Should -Not -BeNullOrEmpty
            $instance.Cmdlet | Should -BeNullOrEmpty
        }
    }

    It 'stores the PSCmdlet handed in by a wrapper function' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty

            function Invoke-A4ConstructionProbe {
                [CmdletBinding()]
                param()
                [SqlPowerDocBase]::new($PSCmdlet)
            }

            $instance = Invoke-A4ConstructionProbe

            $instance.Cmdlet | Should -Not -BeNullOrEmpty
            $instance.Cmdlet | Should -BeOfType ([System.Management.Automation.PSCmdlet])
        }
    }

    It 'keeps Cmdlet, Log, and Config hidden - they are plumbing, not a public surface' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty

            $instance = [SqlPowerDocBase]::new()

            ($instance | Get-Member -Name 'Cmdlet') | Should -BeNullOrEmpty
            ($instance | Get-Member -Name 'Log') | Should -BeNullOrEmpty
            ($instance | Get-Member -Name 'Config') | Should -BeNullOrEmpty

            ($instance | Get-Member -Force -Name 'Log') | Should -Not -BeNullOrEmpty
            ($instance | Get-Member -Force -Name 'Config') | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'SqlPowerDocBase.Log' -Tag 'Unit' {

    It 'always names the module and the function so PSFramework never records Unknown' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty
            [SqlPowerDocBase]::new().Log('Verbose', 'collecting Win32_OperatingSystem')
        }

        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            $PesterBoundParameters.ModuleName -eq 'SqlPowerDoc' -and
            $PesterBoundParameters.FunctionName -eq 'SqlPowerDocBase' -and
            "$($PesterBoundParameters.Level)" -eq 'Verbose' -and
            $PesterBoundParameters.Message -eq 'collecting Win32_OperatingSystem'
        }
    }

    It 'passes -PSCmdlet and the wrapper name when a wrapper supplied its PSCmdlet' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty

            function Invoke-A4LogProbe {
                [CmdletBinding()]
                param()
                [SqlPowerDocBase]::new($PSCmdlet).Log('Verbose', 'wrapper-attributed message')
            }

            Invoke-A4LogProbe
        }

        # -PSCmdlet is what restores the caller's -Verbose/-Debug preferences and correct
        # attribution; asserting it on the wire is the only way to know it was not dropped.
        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            $PesterBoundParameters.ContainsKey('PSCmdlet') -and
            $null -ne $PesterBoundParameters.PSCmdlet -and
            $PesterBoundParameters.FunctionName -eq 'Invoke-A4LogProbe' -and
            $PesterBoundParameters.ModuleName -eq 'SqlPowerDoc'
        }
    }

    It 'omits -PSCmdlet entirely when the class was constructed without one' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty
            [SqlPowerDocBase]::new().Log('Debug', 'no wrapper here')
        }

        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            -not $PesterBoundParameters.ContainsKey('PSCmdlet')
        }
    }

    It 'falls back to the class name rather than logging an empty function name' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty

            # A PSCmdlet outlives the invocation that produced it, but its MyInvocation.MyCommand is
            # null once that invocation has returned. An object holding a stashed PSCmdlet would
            # otherwise log -FunctionName '' and lose attribution completely.
            function Get-A4StalePSCmdlet {
                [CmdletBinding()]
                param()
                $PSCmdlet
            }

            $stale = Get-A4StalePSCmdlet
            $stale.MyInvocation.MyCommand | Should -BeNullOrEmpty

            [SqlPowerDocBase]::new($stale).Log('Verbose', 'stale cmdlet')
        }

        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            $PesterBoundParameters.FunctionName -eq 'SqlPowerDocBase' -and
            $PesterBoundParameters.ContainsKey('PSCmdlet')
        }
    }

    It 'passes Target and Tag through the four-argument overload' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty
            [SqlPowerDocBase]::new().Log('Warning', 'section failed', 'SPDHOST01', @('cim', 'partial'))
        }

        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            $PesterBoundParameters.Target -eq 'SPDHOST01' -and
            $PesterBoundParameters.Tag -contains 'cim' -and
            $PesterBoundParameters.Tag -contains 'partial'
        }
    }

    It 'omits Target and Tag when they carry nothing, so the log line stays clean' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty
            [SqlPowerDocBase]::new().Log('Verbose', 'nothing to correlate', $null, @())
        }

        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            -not $PesterBoundParameters.ContainsKey('Target') -and
            -not $PesterBoundParameters.ContainsKey('Tag')
        }
    }

    It 'reaches the real PSFramework message log with the attribution intact' {
        $message = 'a4-base-log-{0}' -f [guid]::NewGuid()

        InModuleScope SqlPowerDoc -Parameters @{ Text = $message } {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty
            [SqlPowerDocBase]::new().Log('Verbose', $Text)
        }

        # Not a mock assertion: this proves the splat is actually accepted by Write-PSFMessage,
        # which no ParameterFilter on a mocked command can tell you.
        $entry = Get-PSFMessage | Where-Object { $_.Message -eq $message } | Select-Object -Last 1

        $entry | Should -Not -BeNullOrEmpty
        $entry.ModuleName | Should -Be 'SqlPowerDoc'
        $entry.FunctionName | Should -Be 'SqlPowerDocBase'
        "$($entry.Level)" | Should -Be 'Verbose'
    }
}

Describe 'SqlPowerDocBase.Config' -Tag 'Unit' {

    It 'namespaces the key under SqlPowerDoc. and forwards the fallback' {
        Mock -CommandName Get-PSFConfigValue -ModuleName SqlPowerDoc -MockWith { 99 }

        $value = InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty
            [SqlPowerDocBase]::new().Config('Sql.ConnectTimeoutSeconds', 15)
        }

        $value | Should -Be 99
        Should -Invoke -CommandName Get-PSFConfigValue -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            $PesterBoundParameters.FullName -eq 'SqlPowerDoc.Sql.ConnectTimeoutSeconds' -and
            $PesterBoundParameters.Fallback -eq 15
        }
    }

    It 'returns the fallback when the key has never been registered' {
        $value = InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty
            [SqlPowerDocBase]::new().Config('A4.KeyThatDoesNotExist', 'fallback-value')
        }

        $value | Should -Be 'fallback-value'
    }

    It 'returns the configured value when the key exists' {
        $value = InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty

            Set-PSFConfig -FullName 'SqlPowerDoc.A4.ConfiguredKey' -Value 600
            [SqlPowerDocBase]::new().Config('A4.ConfiguredKey', 15)
        }

        $value | Should -Be 600
    }

    It 'reads configuration at call time, not at construction time' {
        # Plan section 3.1: config is read inside methods, never as a field initialiser, or a value
        # set after the object was built is silently ignored.
        $results = InModuleScope SqlPowerDoc {
            ('SqlPowerDocBase' -as [type]) | Should -Not -BeNullOrEmpty

            $instance = [SqlPowerDocBase]::new()
            $instance.Config('A4.LateBoundKey', 'default')

            Set-PSFConfig -FullName 'SqlPowerDoc.A4.LateBoundKey' -Value 'changed'
            $instance.Config('A4.LateBoundKey', 'default')
        }

        $results[0] | Should -Be 'default'
        $results[1] | Should -Be 'changed'
    }
}

#Requires -Version 7.4
<#
    Work item: A5 - class load-order guard (plan section 4, A5; design in plan section 2.3).

    ModuleBuilder concatenates Classes/*.ps1 in filename order and does no dependency resolution
    (confirmed by the maintainer in PoshCode/ModuleBuilder#18), and PowerShell resolves a type
    reference at parse time wherever it appears. That means load order is encoded entirely in each
    file's numeric prefix, and a wrong prefix surfaces as a confusing TypeNotFound at import time
    far from its actual cause - especially once several agents are adding class files in parallel.

    Checking only TypeDefinitionAst.BaseTypes (inheritance) is the mistake to avoid: a base type,
    an interface, a property type, a method parameter/return type, a static member access, a type
    literal, and a `::new()` call all fail identically if the referenced type is declared in a
    lexicographically later file, and all of them parse to a TypeConstraintAst or a
    TypeExpressionAst. So this guard walks every one of those in every Classes/*.ps1, not just the
    class declarations themselves.

    Everything here is static analysis - nothing is imported and nothing is built - so the file
    runs on Linux with no SQL Server, no Windows, and no build output present.
#>

BeforeDiscovery {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $script:ClassDirectory = Join-Path $script:RepositoryRoot 'src' 'SqlPowerDoc' 'Classes'

    $classFiles = @(
        Get-ChildItem -Path $script:ClassDirectory -Filter '*.ps1' -File |
            Sort-Object -Property Name -Culture ([System.Globalization.CultureInfo]::InvariantCulture)
    )

    # Load position of every file, and where each SqlPowerDoc* type (class or enum) is declared.
    # Keyed by file name rather than derived from the type map, because a class file that declares
    # no type of its own (a pure helper file) would otherwise get a $null order and every reference
    # it makes would silently pass every assertion below.
    $orderOf = @{}
    $declaredIn = @{}
    $enumDeclarations = @{}
    $index = 0

    foreach ($file in $classFiles) {
        $index++
        $orderOf[$file.Name] = $index

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $parseErrors)

        foreach ($definition in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.TypeDefinitionAst] }, $true)) {
            $declaredIn[$definition.Name] = @{ File = $file.Name; Order = $index }
            if ($definition.IsEnum) {
                $enumDeclarations[$definition.Name] = @{ File = $file.Name; Order = $index }
            }
        }
    }

    # Every reference to one of our own types, from anywhere in any class file. Hashtables, NOT
    # [pscustomobject]: Pester's -ForEach binds hashtable keys as variables inside the It block and
    # expands <Key> in the test name. A [pscustomobject] exposes only $_, so the referenced
    # variables would all be $null and a real violation would report a false "Tests Passed".
    $references = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($file in $classFiles) {
        $referencingOrder = $orderOf[$file.Name]

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $parseErrors)

        $referenceAsts = $ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.TypeConstraintAst] -or
                $args[0] -is [System.Management.Automation.Language.TypeExpressionAst]
            }, $true)

        foreach ($reference in $referenceAsts) {
            # ArrayTypeName (e.g. [SqlPowerDocWorksheetSpec[]]) reports its Name with the trailing
            # '[]' still attached; strip it so the lookup matches the declared type name.
            $typeName = $reference.TypeName.Name -replace '\[\]$', ''

            if (-not $declaredIn.ContainsKey($typeName)) { continue }   # framework/.NET type; not ours

            $declared = $declaredIn[$typeName]

            $references.Add(@{
                    ReferencingFile  = $file.Name
                    ReferencingOrder = $referencingOrder
                    Type             = $typeName
                    DeclaredFile     = $declared.File
                    DeclaredOrder    = $declared.Order
                    Line             = $reference.Extent.StartLineNumber
                })
        }
    }

    $script:References = @($references)
    $script:ClassFiles = @(
        $classFiles | ForEach-Object { @{ File = $_; OwnTypeNames = @($declaredIn.Keys) } }
    )
    $script:EnumDeclarations = @(
        $enumDeclarations.GetEnumerator() | ForEach-Object {
            @{
                EnumName = $_.Key
                FileName = $_.Value.File
                Prefix   = [int] ($_.Value.File -replace '-.*$', '')
            }
        }
    )
}

Describe 'Class load order' -Tag 'Unit' {

    BeforeAll {
        # BeforeDiscovery's $script: variables back the -ForEach bindings below (evaluated at
        # discovery time), but are not guaranteed visible to a plain It's Run-time scope - so any
        # assertion that is not itself an -ForEach binding recomputes what it needs here instead.
        $script:ClassDirectory = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path 'src' 'SqlPowerDoc' 'Classes'
    }

    It 'declares <Type> before <ReferencingFile> references it (line <Line>)' -ForEach $script:References {
        # Equal order is fine: a class may reference itself, or a sibling declared in the same
        # file (e.g. an exception subclass referencing its own base within Classes/01-Exceptions.ps1).
        $DeclaredOrder | Should -BeLessOrEqual $ReferencingOrder -Because (
            "$ReferencingFile references [$Type], which is declared later in $DeclaredFile - " +
            'ModuleBuilder concatenates Classes/*.ps1 by filename with no dependency resolution, ' +
            'so this ordering would produce a TypeNotFound at import time.'
        )
    }

    It 'parses <File> without errors' -ForEach $script:ClassFiles {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref] $tokens, [ref] $parseErrors)

        # ParseFile analyses one file at a time, with no other Classes/*.ps1 file dot-sourced into
        # the session first, so a completely legitimate reference to a SqlPowerDoc type declared
        # in another (correctly earlier-loaded) file reports as ErrorId 'TypeNotFound' here even
        # though the real, dependency-ordered import in SqlPowerDoc.psm1 resolves it fine - the
        # load-order assertion above is what actually proves that. Only a TypeNotFound for a name
        # that is NOT one of our own known types (a real typo, or a genuinely missing .NET type)
        # should fail this test; every other parse error still should.
        $realErrors = @($parseErrors | Where-Object {
                -not ($_.ErrorId -eq 'TypeNotFound' -and $OwnTypeNames -contains $_.Extent.Text)
            })
        $realErrors | Should -BeNullOrEmpty
    }

    It 'declares enum <EnumName> in a tier-0x file, matching plan section 2.3' -ForEach $script:EnumDeclarations {
        # Enums carry no dependencies of their own, so plan section 2.3 tiers them into 0x
        # regardless of how many other classes come to reference them. A correctly-ordered but
        # mis-tiered enum (e.g. renumbered into 1x) would still pass every dependency check above,
        # which is exactly the gap this assertion closes.
        $Prefix | Should -BeLessThan 10 -Because "$EnumName is an enum declared in $FileName; plan section 2.3 reserves tier 0x for enums, exceptions, and other dependency-free declarations"
    }

    It 'finds at least one Classes/*.ps1 file to guard' {
        # A guard that silently checks zero files (e.g. because the directory moved) is worse than
        # no guard at all: every assertion above would vacuously pass.
        @(Get-ChildItem -Path $script:ClassDirectory -Filter '*.ps1' -File).Count | Should -BeGreaterThan 0
    }
}

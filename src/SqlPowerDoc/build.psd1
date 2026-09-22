#
# ModuleBuilder configuration. Consumed by `Build-Module -SourcePath src/SqlPowerDoc/build.psd1`.
#
# The output is one file, output/SqlPowerDoc/<version>/SqlPowerDoc.psm1, containing every
# Classes/*.ps1, Private/*.ps1, and Public/*.ps1 in that order, each wrapped in a
# `#Region <source file>` marker, plus a manifest whose FunctionsToExport is populated from
# the Public/ filenames.
#
# SourceDirectories must stay in step with the dev-mode loader in SqlPowerDoc.psm1, or dev
# mode and built mode diverge.
#
@{
    Path                     = 'SqlPowerDoc.psd1'
    OutputDirectory          = '../../output'
    VersionedOutputDirectory = $true
    SourceDirectories        = @('Classes', 'Private', 'Public')
    PublicFilter             = 'Public/*.ps1'
    CopyDirectories          = @('en-US')
    Encoding                 = 'UTF8'

    # Hoists and de-duplicates `using` statements. Required: `using` must be the first
    # statement in a file, so naive concatenation of per-file `using` lines is a parse error.
    Generators               = @(
        @{ Generator = 'Move-UsingStatement' }
    )
}

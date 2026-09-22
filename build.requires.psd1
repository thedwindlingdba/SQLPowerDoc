# build.requires.psd1 - the single source of truth for every install, dev and CI alike.
#
# Consumed by:  pwsh -NoProfile -File ./build/Install-DevDependencies.ps1
#
# That script installs each entry with Install-PSResource -Prerelease. It does not use
# -RequiredResourceFile, because PSResourceGet 1.2.0 puts -Prerelease and
# -RequiredResourceFile in different parameter sets and refuses the combination, and
# -Prerelease on every install is mandatory here.
#
# Pinning policy:
#   exact ('5.14.23')        - build tooling. A task runner or assembler changing under us
#                              changes the artifact, so these move only by an explicit commit.
#   range ('[2.9.0,3.0)')    - runtime and test dependencies. Allows patch and minor pickup
#                              inside a major, which is what the shipped manifest's floor
#                              already implies; blocks a major bump arriving silently.
#   explicit prerelease      - write the full tag, e.g. '2.9.1-beta1', to track one on purpose.
#
# -Prerelease is always passed and the pin decides what it resolves to: the switch widens the
# candidate set, it does not force a prerelease over a pinned stable version.
#
# The excluded SQL Server PowerShell module appears nowhere here by design. dbatools.library,
# which arrives with dbatools, supplies SMO and Microsoft.Data.SqlClient.
@{
    # --- build toolchain: exact ---
    InvokeBuild         = @{ version = '5.14.23'; repository = 'PSGallery' }
    ModuleBuilder       = @{ version = '3.2.18'; repository = 'PSGallery' }
    PSModuleDevelopment = @{ version = '2.2.13.217'; repository = 'PSGallery' }

    # --- test and lint: ranged, floors chosen for idiom compatibility ---
    # The suite uses Pester 5 idioms only, which both 5.x and 6.x run, so a contributor on
    # 5.7.1 and CI on 6.2.0 execute the same tests.
    Pester              = @{ version = '[5.5.0,7.0)'; repository = 'PSGallery' }
    PSScriptAnalyzer    = @{ version = '[1.21.0,2.0)'; repository = 'PSGallery' }

    # --- runtime: ranged within the current major ---
    dbatools            = @{ version = '[2.9.0,3.0)'; repository = 'PSGallery' }
    PSFramework         = @{ version = '[1.14.457,2.0)'; repository = 'PSGallery' }
    ImportExcel         = @{ version = '[7.8.10,8.0)'; repository = 'PSGallery' }
}

#
# Enums. Tier 0x: no dependencies, declared before anything that can reference them.
#
# ModuleBuilder concatenates Classes/*.ps1 in filename order and does no dependency resolution,
# and PowerShell resolves a type reference at parse time wherever it appears, so load order is
# encoded in the numeric prefix (plan section 2.3). Nothing in this file may reference a
# SqlPowerDoc type.
#

# The OS- and host-dependent operations the module gates on. SqlPowerDocPlatform.Supports() answers
# one of these per call site, and AssertSupported() turns a 'no' into a SqlPowerDocPlatformException
# naming the capability - which is how a Linux control host reports what it cannot collect instead
# of failing deep inside a collector with a CommandNotFoundException.
enum SqlPowerDocCapability {
    CimQuery
    RemoteRegistry
    LocalSecurityPolicy
    SqlServiceEnumeration
    WindowsAuthentication
    ExcelAutoSize
    TcpProbe
    DnsResolution
}

# SQL Server SKUs, ascending by capability so a comparison is meaningful: Express and Web are
# resource-capped and lack SQL Agent, which is why the legacy engine module skipped two collectors
# on 'Express*' and why its assessment flagged anything that was not Standard, Enterprise, or
# Developer. Azure SQL Database appears here for reporting only; the catalog-view differences it
# causes are driven by SqlPowerDocConnection.IsAzure, not by this enum.
enum SqlPowerDocSqlEdition {
    Unknown = 0
    Express = 10
    Web = 20
    Standard = 30
    BusinessIntelligence = 40
    Developer = 50
    Enterprise = 60
    Evaluation = 70
    AzureSqlDatabase = 80
}

# Which sections of a machine inventory to collect. One member per method group in plan section 3.6,
# so a caller can ask for hardware and network without paying for a software inventory. Flags rather
# than a plain enum because those selections combine.
[Flags()]
enum SqlPowerDocCollectionScope {
    None = 0
    Hardware = 1
    OperatingSystem = 2
    RuntimeState = 4
    Security = 8
    Software = 16
    Network = 32
    Web = 64
    All = 127
}

# The parent object type a schema query runs against. The legacy module duplicated four collectors
# per parent type (Get-ColumnInformation / Get-ColumnInformation2 and three siblings) instead of
# parameterising them; this enum is the parameter that collapses all four pairs.
enum SqlPowerDocSchemaScope {
    Table
    View
    UserDefinedFunction
}

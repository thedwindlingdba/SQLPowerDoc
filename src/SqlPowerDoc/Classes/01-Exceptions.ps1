#
# Exceptions. Tier 0x: no dependencies beyond System.Exception.
#
# Classes throw; wrappers catch and call Stop-PSFFunction (plan section 3.1). Target is what makes
# that split work: the wrapper sets -Target from $_.Exception.Target instead of parsing the message,
# so the failure is correlatable to a host or an instance no matter how deep it was raised.
#
# PowerShell does not inherit constructors, so each subclass redeclares all three.
#

class SqlPowerDocException : System.Exception {
    [string] $Target

    SqlPowerDocException([string] $Message) : base($Message) { }

    SqlPowerDocException([string] $Message, [string] $Target) : base($Message) {
        $this.Target = $Target
    }

    SqlPowerDocException([string] $Message, [string] $Target, [System.Exception] $InnerException)
        : base($Message, $InnerException) {
        $this.Target = $Target
    }
}

# Raised when a capability is not available on the current control host. Target carries the platform
# name, so the message and the structured data say the same thing.
class SqlPowerDocPlatformException : SqlPowerDocException {
    SqlPowerDocPlatformException([string] $Message) : base($Message) { }

    SqlPowerDocPlatformException([string] $Message, [string] $Target) : base($Message, $Target) { }

    SqlPowerDocPlatformException([string] $Message, [string] $Target, [System.Exception] $InnerException)
        : base($Message, $Target, $InnerException) { }
}

# Raised when connecting to, or querying, a SQL Server instance fails. Target carries the instance
# name.
class SqlPowerDocConnectionException : SqlPowerDocException {
    SqlPowerDocConnectionException([string] $Message) : base($Message) { }

    SqlPowerDocConnectionException([string] $Message, [string] $Target) : base($Message, $Target) { }

    SqlPowerDocConnectionException([string] $Message, [string] $Target, [System.Exception] $InnerException)
        : base($Message, $Target, $InnerException) { }
}

# Raised by the version gate for an instance below SQL Server 2016. Target carries the instance name.
class SqlPowerDocUnsupportedVersionException : SqlPowerDocException {
    SqlPowerDocUnsupportedVersionException([string] $Message) : base($Message) { }

    SqlPowerDocUnsupportedVersionException([string] $Message, [string] $Target) : base($Message, $Target) { }

    SqlPowerDocUnsupportedVersionException([string] $Message, [string] $Target, [System.Exception] $InnerException)
        : base($Message, $Target, $InnerException) { }
}

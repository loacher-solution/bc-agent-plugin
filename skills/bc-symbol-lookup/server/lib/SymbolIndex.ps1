#requires -Version 7.0
<#
SymbolIndex.ps1 — Build an in-memory flat index over SymbolReference.json trees from
every .app file in a package cache folder.

Index shape:
  [pscustomobject]@{
    Apps    = @([{ Id, Name, Publisher, Version, Path }])
    Objects = @([{ Id, Type, Name, Namespace, FullyQualifiedName, SourceApp, AppVersion,
                    Fields, Procedures, Node }])
  }

`Node` holds the raw JSON PSCustomObject for the object so tool handlers can pull
fields/procedures on demand without re-walking the tree.
#>

function New-SymbolIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PackageCachePath
    )

    $apps    = New-Object System.Collections.Generic.List[object]
    $objects = New-Object System.Collections.Generic.List[object]

    if (-not (Test-Path $PackageCachePath)) {
        return [pscustomobject]@{ Apps = @(); Objects = @() }
    }

    $appFiles = Get-ChildItem -Path $PackageCachePath -Filter '*.app' -File -ErrorAction SilentlyContinue
    foreach ($file in $appFiles) {
        try {
            $read = Read-AppSymbols -Path $file.FullName
        } catch {
            Write-Warning "Skipping $($file.Name): $($_.Exception.Message)"
            continue
        }
        if (-not $read) { continue }

        try {
            $parsed = $read.SymbolJson | ConvertFrom-Json -Depth 100
        } catch {
            Write-Warning "Skipping $($file.Name): SymbolReference.json parse failed — $($_.Exception.Message)"
            continue
        }

        $apps.Add([pscustomobject]@{
            Id        = $parsed.AppId
            Name      = $parsed.Name
            Publisher = $parsed.Publisher
            Version   = $parsed.Version
            Path      = $file.FullName
        })

        _WalkNamespaces -Node $parsed -NamespacePath '' -SourceAppName $parsed.Name -SourceAppVersion $parsed.Version -Sink $objects
    }

    return [pscustomobject]@{
        Apps    = $apps.ToArray()
        Objects = $objects.ToArray()
    }
}

function _WalkNamespaces {
    param(
        [Parameter(Mandatory)] $Node,
        [string] $NamespacePath,
        [string] $SourceAppName,
        [string] $SourceAppVersion,
        [Parameter(Mandatory)] $Sink
    )

    $objectKinds = @(
        @{ Property = 'Tables';          Type = 'Table' },
        @{ Property = 'TableExtensions'; Type = 'TableExtension' },
        @{ Property = 'Pages';           Type = 'Page' },
        @{ Property = 'PageExtensions';  Type = 'PageExtension' },
        @{ Property = 'Codeunits';       Type = 'Codeunit' },
        @{ Property = 'Reports';         Type = 'Report' },
        @{ Property = 'Queries';         Type = 'Query' },
        @{ Property = 'XmlPorts';        Type = 'XmlPort' },
        @{ Property = 'Enums';           Type = 'Enum' },
        @{ Property = 'EnumTypes';       Type = 'Enum' },            # BC real-world uses EnumTypes
        @{ Property = 'EnumExtensions';  Type = 'EnumExtension' },
        @{ Property = 'EnumExtensionTypes'; Type = 'EnumExtension' },
        @{ Property = 'Interfaces';      Type = 'Interface' },
        @{ Property = 'ControlAddIns';   Type = 'ControlAddIn' },
        @{ Property = 'PermissionSets';  Type = 'PermissionSet' },
        @{ Property = 'ReportExtensions'; Type = 'ReportExtension' }
    )

    foreach ($kind in $objectKinds) {
        $arr = $Node.PSObject.Properties[$kind.Property]
        if ($arr -and $arr.Value) {
            foreach ($obj in $arr.Value) {
                $name = if ($obj.Name) { $obj.Name } else { "<unnamed>" }
                $id   = if ($obj.PSObject.Properties['Id']) { $obj.Id } else { $null }
                $fqn  = if ($NamespacePath) { "$NamespacePath.$name" } else { $name }
                $Sink.Add([pscustomobject]@{
                    Id                 = $id
                    Type               = $kind.Type
                    Name               = $name
                    Namespace          = $NamespacePath
                    FullyQualifiedName = $fqn
                    SourceApp          = $SourceAppName
                    AppVersion         = $SourceAppVersion
                    Node               = $obj
                })
            }
        }
    }

    # Recurse into nested namespaces
    $nsProp = $Node.PSObject.Properties['Namespaces']
    if ($nsProp -and $nsProp.Value) {
        foreach ($ns in $nsProp.Value) {
            $childPath = if ($ns.Name) {
                if ($NamespacePath) { "$NamespacePath.$($ns.Name)" } else { $ns.Name }
            } else {
                $NamespacePath
            }
            _WalkNamespaces -Node $ns -NamespacePath $childPath -SourceAppName $SourceAppName -SourceAppVersion $SourceAppVersion -Sink $Sink
        }
    }
}

function Find-IndexedObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [Parameter(Mandatory)] [string] $Name,
        [string] $Type
    )
    # Used by SymbolIndex.Tests.ps1 to verify index shape; tool handlers in Tools.ps1
    # filter inline for performance. -ilike covers both exact and wildcard matches.
    $results = $Index.Objects | Where-Object { $_.Name -ilike $Name }
    if ($Type) {
        $results = $results | Where-Object { $_.Type -ieq $Type }
    }
    return @($results)
}

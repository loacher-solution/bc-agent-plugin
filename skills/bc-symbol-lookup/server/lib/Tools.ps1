#requires -Version 7.0
<#
Tools.ps1 — MCP tool handlers for bc-symbol-lookup.

Each handler takes `-Index` (a SymbolIndex) and `-Args` (a hashtable from the MCP
tool call) and returns a PSCustomObject that gets JSON-serialized as the tool result.

Never throw — wrap errors in { error = ... } return values so the agent gets structured
feedback instead of a protocol-level crash.
#>

function Invoke-BcListAppsTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )
    return [pscustomobject]@{
        apps = @($Index.Apps | ForEach-Object {
            [pscustomobject]@{
                id        = $_.Id
                name      = $_.Name
                publisher = $_.Publisher
                version   = $_.Version
                path      = $_.Path
            }
        })
    }
}

function Invoke-BcFindObjectTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )

    $name = [string]$Args['name']
    if (-not $name) {
        return [pscustomobject]@{ error = "Parameter 'name' is required" }
    }
    $type = [string]$Args['type']

    $results = $Index.Objects | Where-Object {
        $_.Name -ilike $name
    }
    if ($type) {
        $results = $results | Where-Object { $_.Type -ieq $type }
    }

    return [pscustomobject]@{
        objects = @($results | ForEach-Object {
            [pscustomobject]@{
                id                 = $_.Id
                type               = $_.Type
                name               = $_.Name
                namespace          = $_.Namespace
                fullyQualifiedName = $_.FullyQualifiedName
                sourceApp          = $_.SourceApp
                appVersion         = $_.AppVersion
            }
        })
    }
}

function Invoke-BcGetFieldsTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )

    $objectName = [string]$Args['objectName']
    $objectId   = $Args['objectId']
    $type       = [string]$Args['type']
    $filter     = [string]$Args['filter']

    if (-not $type) {
        return [pscustomobject]@{ error = "Parameter 'type' is required (e.g., 'Table' or 'TableExtension')" }
    }
    if ($type -ne 'Table' -and $type -ne 'TableExtension') {
        return [pscustomobject]@{ error = "bc_get_fields only supports type Table or TableExtension (got: $type)" }
    }

    $match = $Index.Objects | Where-Object {
        $_.Type -ieq $type -and (
            ($objectName -and $_.Name -ieq $objectName) -or
            ($objectId -and $_.Id -eq $objectId)
        )
    } | Select-Object -First 1

    if (-not $match) {
        return [pscustomobject]@{ error = "Object not found: $type '$objectName' (id=$objectId)" }
    }

    $fieldsProp = $match.Node.PSObject.Properties['Fields']
    if (-not $fieldsProp -or -not $fieldsProp.Value) {
        return [pscustomobject]@{ error = "Object has no fields: $type '$objectName'" }
    }

    $fields = $fieldsProp.Value | ForEach-Object {
        $td = $_.TypeDefinition
        [pscustomobject]@{
            id         = $_.Id
            name       = $_.Name
            typeName   = if ($td) { $td.Name } else { $null }
            typeLength = if ($td -and $td.PSObject.Properties['Length']) { $td.Length } else { $null }
            enabled    = if ($_.PSObject.Properties['Enabled']) { $_.Enabled } else { $true }
        }
    }

    if ($filter) {
        $fields = $fields | Where-Object { $_.name -ilike "*$filter*" }
    }

    return [pscustomobject]@{ fields = @($fields) }
}

function Invoke-BcGetProceduresTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )

    $objectName = [string]$Args['objectName']
    $objectId   = $Args['objectId']
    $type       = [string]$Args['type']
    $filter     = [string]$Args['filter']

    if (-not $type) {
        return [pscustomobject]@{ error = "Parameter 'type' is required (e.g., 'Codeunit' or 'Page')" }
    }

    $match = $Index.Objects | Where-Object {
        $_.Type -ieq $type -and (
            ($objectName -and $_.Name -ieq $objectName) -or
            ($objectId -and $_.Id -eq $objectId)
        )
    } | Select-Object -First 1

    if (-not $match) {
        return [pscustomobject]@{ error = "Object not found: $type '$objectName' (id=$objectId)" }
    }

    $methodsProp = $match.Node.PSObject.Properties['Methods']
    if (-not $methodsProp -or -not $methodsProp.Value) {
        return [pscustomobject]@{ procedures = @() }
    }

    $procs = $methodsProp.Value | ForEach-Object {
        $m = $_
        $scope =
            if ($m.PSObject.Properties['IsLocal'] -and $m.IsLocal) { 'Local' }
            elseif ($m.PSObject.Properties['IsInternal'] -and $m.IsInternal) { 'Internal' }
            else { 'Public' }

        $params = @()
        if ($m.PSObject.Properties['Parameters'] -and $m.Parameters) {
            $params = $m.Parameters | ForEach-Object {
                [pscustomobject]@{
                    name     = $_.Name
                    typeName = if ($_.TypeDefinition) { $_.TypeDefinition.Name } else { $null }
                    isVar    = if ($_.PSObject.Properties['IsVar']) { [bool]$_.IsVar } else { $false }
                }
            }
        }

        $returnType = $null
        if ($m.PSObject.Properties['ReturnTypeDefinition'] -and $m.ReturnTypeDefinition) {
            $returnType = $m.ReturnTypeDefinition.Name
        }

        [pscustomobject]@{
            name       = $m.Name
            scope      = $scope
            parameters = @($params)
            returnType = $returnType
        }
    }

    if ($filter) {
        $procs = $procs | Where-Object { $_.name -ilike "*$filter*" }
    }

    return [pscustomobject]@{ procedures = @($procs) }
}

function Invoke-BcSearchTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )

    $query = [string]$Args['query']
    if (-not $query) {
        return [pscustomobject]@{ error = "Parameter 'query' is required" }
    }
    $limit = if ($Args['limit']) { [int]$Args['limit'] } else { 25 }

    $ql = $query.ToLowerInvariant()
    $hits = $Index.Objects | ForEach-Object {
        $nameLower = $_.Name.ToLowerInvariant()
        $score =
            if ($nameLower -eq $ql) { 100 }
            elseif ($nameLower.StartsWith($ql)) { 75 }
            elseif ($nameLower.Contains($ql)) { 50 }
            else { 0 }
        if ($score -gt 0) {
            [pscustomobject]@{
                score      = $score
                id         = $_.Id
                type       = $_.Type
                name       = $_.Name
                namespace  = $_.Namespace
                sourceApp  = $_.SourceApp
                appVersion = $_.AppVersion
            }
        }
    } | Sort-Object -Property score -Descending | Select-Object -First $limit

    return [pscustomobject]@{ results = @($hits) }
}

function Invoke-BcGetObjectSourceTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )

    $objectName = [string]$Args['objectName']
    $type       = [string]$Args['type']

    $match = $Index.Objects | Where-Object {
        $_.Type -ieq $type -and $_.Name -ieq $objectName
    } | Select-Object -First 1

    if (-not $match) {
        return [pscustomobject]@{ error = "Object not found: $type '$objectName'" }
    }

    return [pscustomobject]@{
        source = $null
        reason = 'Source retrieval not implemented in v1 — see roadmap'
    }
}

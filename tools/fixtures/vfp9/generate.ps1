param(
    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function ConvertTo-HexLiteral {
    param([byte[]] $Bytes)

    return "0h" + ([BitConverter]::ToString($Bytes) -replace "-", "")
}

function Invoke-VfpSql {
    param(
        [System.Data.OleDb.OleDbConnection] $Connection,
        [string] $Label,
        [string] $Sql
    )

    $command = $Connection.CreateCommand()
    try {
        Write-Host "VFPOLEDB: $Label"
        $command.CommandText = $Sql
        [void] $command.ExecuteNonQuery()
    }
    catch {
        throw "VFPOLEDB failed during '$Label': $($_.Exception.Message)"
    }
    finally {
        $command.Dispose()
    }
}

function Set-VfpValue {
    param(
        [System.Data.OleDb.OleDbConnection] $Connection,
        [string] $Label,
        [int] $RecordId,
        [string] $Column,
        [System.Data.OleDb.OleDbType] $Type,
        [object] $Value,
        [int] $Size = 0
    )

    $command = $Connection.CreateCommand()
    try {
        Write-Host "VFPOLEDB: $Label"
        $command.CommandText = "UPDATE vfp9_binary SET $Column = ? WHERE ID = $RecordId"

        $parameter = New-Object System.Data.OleDb.OleDbParameter
        $parameter.OleDbType = $Type
        if ($Size -gt 0) {
            $parameter.Size = $Size
        }
        $parameter.Value =
            if ($null -eq $Value) {
                [DBNull]::Value
            }
            elseif ($Type -in @(
                [System.Data.OleDb.OleDbType]::Binary,
                [System.Data.OleDb.OleDbType]::VarBinary,
                [System.Data.OleDb.OleDbType]::LongVarBinary
            )) {
                [byte[]] @($Value)
            }
            else {
                $Value
            }
        [void] $command.Parameters.Add($parameter)
        [void] $command.ExecuteNonQuery()
    }
    catch {
        throw "VFPOLEDB failed during '$Label': $($_.Exception.Message)"
    }
    finally {
        $command.Dispose()
    }
}

function Get-ObservedStructure {
    param([string] $TablePath)

    [byte[]] $bytes = [IO.File]::ReadAllBytes($TablePath)
    $headerLength = [BitConverter]::ToUInt16($bytes, 8)
    $recordLength = [BitConverter]::ToUInt16($bytes, 10)
    $fields = @()

    for ($offset = 32; $offset -lt $headerLength; $offset += 32) {
        if ($bytes[$offset] -eq 0x0D) {
            break
        }

        $fields += [ordered]@{
            name = [Text.Encoding]::ASCII.GetString($bytes, $offset, 11).Trim([char] 0)
            type = [char] $bytes[$offset + 11]
            length = $bytes[$offset + 16]
            decimal = $bytes[$offset + 17]
            flags = $bytes[$offset + 18]
        }
    }

    return [ordered]@{
        version = $bytes[0]
        version_hex = "0x{0:X2}" -f $bytes[0]
        header_length = $headerLength
        record_length = $recordLength
        record_count = [BitConverter]::ToUInt32($bytes, 4)
        table_flags = $bytes[28]
        language_driver = $bytes[29]
        fields = $fields
    }
}

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path $OutputDirectory) {
    Remove-Item -Recurse -Force $OutputDirectory
}
[void] (New-Item -ItemType Directory -Path $OutputDirectory)

$providerPath = Join-Path ${env:ProgramFiles(x86)} "Common Files\System\Ole DB\vfpoledb.dll"
if (-not (Test-Path $providerPath)) {
    throw "The 32-bit Visual FoxPro OLE DB provider was not installed at $providerPath"
}

$connectionString = "Provider=VFPOLEDB.1;Data Source=$OutputDirectory;Collating Sequence=MACHINE;"
$connection = New-Object System.Data.OleDb.OleDbConnection($connectionString)

[byte[]] $shortBinary = 0x00, 0x20, 0x80, 0xFF, 0x41
[byte[]] $fullBinary = 0..19
[byte[]] $binaryCharacter = 0x00, 0xFF, 0x20, 0x80, 0x42
[byte[]] $memoBinary = New-Object byte[] 640
[byte[]] $blobBinary = New-Object byte[] 700

for ($index = 0; $index -lt $memoBinary.Length; $index++) {
    $memoBinary[$index] = $index % 251
}
for ($index = 0; $index -lt $blobBinary.Length; $index++) {
    $blobBinary[$index] = 255 - ($index % 251)
}

try {
    $connection.Open()

    Invoke-VfpSql $connection "create baseline table" @"
CREATE TABLE vfp9_binary FREE (ID I)
"@

    Invoke-VfpSql $connection "add nullable Varchar field" @"
ALTER TABLE vfp9_binary ADD COLUMN V_TEXT V(20) NULL
"@

    Invoke-VfpSql $connection "add nullable Varbinary field" @"
ALTER TABLE vfp9_binary ADD COLUMN Q_BYTES Q(20) NULL
"@

    Invoke-VfpSql $connection "add nullable binary Character field" @"
ALTER TABLE vfp9_binary ADD COLUMN C_BYTES C(20) NULL NOCPTRANS
"@

    Invoke-VfpSql $connection "add nullable binary Memo field" @"
ALTER TABLE vfp9_binary ADD COLUMN M_BYTES M NULL NOCPTRANS
"@

    Invoke-VfpSql $connection "add nullable Blob field" @"
ALTER TABLE vfp9_binary ADD COLUMN W_BYTES W NULL
"@

    Invoke-VfpSql $connection "add nullable Double field" @"
ALTER TABLE vfp9_binary ADD COLUMN B_VALUE B(4) NULL
"@

    foreach ($recordId in 1..4) {
        Invoke-VfpSql $connection "create record $recordId" "INSERT INTO vfp9_binary (ID) VALUES ($recordId)"
    }

    Set-VfpValue $connection "set record 1 Varchar" 1 "V_TEXT" VarChar "text with tail " 20
    Set-VfpValue $connection "set record 1 Varbinary" 1 "Q_BYTES" VarBinary $shortBinary 20
    Set-VfpValue $connection "set record 1 binary Character" 1 "C_BYTES" VarBinary $binaryCharacter 20
    Set-VfpValue $connection "set record 1 binary Memo" 1 "M_BYTES" LongVarBinary $memoBinary
    Set-VfpValue $connection "set record 1 Blob" 1 "W_BYTES" LongVarBinary $blobBinary
    Set-VfpValue $connection "set record 1 Double" 1 "B_VALUE" Double -12345.625

    Set-VfpValue $connection "set record 2 full-width Varchar" 2 "V_TEXT" VarChar "12345678901234567890" 20
    Set-VfpValue $connection "set record 2 full-width Varbinary" 2 "Q_BYTES" VarBinary $fullBinary 20
    Set-VfpValue $connection "set record 2 full-width binary Character" 2 "C_BYTES" VarBinary $fullBinary 20
    Set-VfpValue $connection "set record 2 empty binary Memo" 2 "M_BYTES" LongVarBinary ([byte[]] @())
    Set-VfpValue $connection "set record 2 empty Blob" 2 "W_BYTES" LongVarBinary ([byte[]] @())
    Set-VfpValue $connection "set record 2 Double" 2 "B_VALUE" Double 1.25

    Set-VfpValue $connection "set record 4 empty Varchar" 4 "V_TEXT" VarChar "" 20
    Set-VfpValue $connection "set record 4 empty Varbinary" 4 "Q_BYTES" VarBinary ([byte[]] @()) 20
    Set-VfpValue $connection "set record 4 empty binary Character" 4 "C_BYTES" VarBinary ([byte[]] @()) 20
    Set-VfpValue $connection "set record 4 empty binary Memo" 4 "M_BYTES" LongVarBinary ([byte[]] @())
    Set-VfpValue $connection "set record 4 empty Blob" 4 "W_BYTES" LongVarBinary ([byte[]] @())
    Set-VfpValue $connection "set record 4 zero Double" 4 "B_VALUE" Double 0.0

    Invoke-VfpSql $connection "mark the second record deleted" "DELETE FROM vfp9_binary WHERE ID = 2"
}
finally {
    $connection.Close()
    $connection.Dispose()
}

$tablePath = Join-Path $OutputDirectory "vfp9_binary.dbf"
if (-not (Test-Path $tablePath)) {
    throw "VFPOLEDB did not create vfp9_binary.dbf"
}

$providerVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($providerPath)
$expected = [ordered]@{
    generator = "tools/fixtures/vfp9/generate.ps1"
    provider = [ordered]@{
        product_name = $providerVersion.ProductName
        product_version = $providerVersion.ProductVersion
        file_version = $providerVersion.FileVersion
    }
    records = @(
        [ordered]@{
            status = "active"
            v_text = "text with tail "
            q_bytes_hex = ConvertTo-HexLiteral $shortBinary
            c_bytes_prefix_hex = ConvertTo-HexLiteral $binaryCharacter
            m_bytes_hex = ConvertTo-HexLiteral $memoBinary
            w_bytes_hex = ConvertTo-HexLiteral $blobBinary
            b_value = -12345.625
        },
        [ordered]@{
            status = "deleted"
            v_text = "12345678901234567890"
            q_bytes_hex = ConvertTo-HexLiteral $fullBinary
            c_bytes_hex = ConvertTo-HexLiteral $fullBinary
            m_bytes_hex = "0h"
            w_bytes_hex = "0h"
            b_value = 1.25
        },
        [ordered]@{
            status = "active"
            values = "all explicit null"
        },
        [ordered]@{
            status = "active"
            values = "all empty"
            b_value = 0.0
        }
    )
}

$observed = Get-ObservedStructure $tablePath
$expected | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory "expected-values.json")
$observed | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory "observed-structure.json")

$hashes = Get-ChildItem -File $OutputDirectory |
    Where-Object { $_.Name -notin @("sha256.txt") } |
    Sort-Object Name |
    ForEach-Object {
        "{0}  {1}" -f (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLowerInvariant(), $_.Name
    }
$hashes | Set-Content -Encoding ASCII (Join-Path $OutputDirectory "sha256.txt")

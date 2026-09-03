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
        [string] $Sql
    )

    $command = $Connection.CreateCommand()
    try {
        $command.CommandText = $Sql
        [void] $command.ExecuteNonQuery()
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

    Invoke-VfpSql $connection @"
CREATE TABLE vfp9_binary FREE CODEPAGE = 1252 (
    ID I AUTOINC NEXTVALUE 1 STEP 1,
    V_TEXT V(20) NULL,
    Q_BYTES Q(20) NULL,
    C_BYTES C(20) NOCPTRANS NULL,
    M_BYTES M NOCPTRANS NULL,
    W_BYTES W NULL,
    B_VALUE B(4) NULL
)
"@

    Invoke-VfpSql $connection @"
INSERT INTO vfp9_binary
    (V_TEXT, Q_BYTES, C_BYTES, M_BYTES, W_BYTES, B_VALUE)
VALUES
    ('text with tail ', $(ConvertTo-HexLiteral $shortBinary),
     $(ConvertTo-HexLiteral $binaryCharacter), $(ConvertTo-HexLiteral $memoBinary),
     $(ConvertTo-HexLiteral $blobBinary), -12345.625)
"@

    Invoke-VfpSql $connection @"
INSERT INTO vfp9_binary
    (V_TEXT, Q_BYTES, C_BYTES, M_BYTES, W_BYTES, B_VALUE)
VALUES
    ('12345678901234567890', $(ConvertTo-HexLiteral $fullBinary),
     $(ConvertTo-HexLiteral $fullBinary), 0h, 0h, 1.25)
"@

    Invoke-VfpSql $connection @"
INSERT INTO vfp9_binary
    (V_TEXT, Q_BYTES, C_BYTES, M_BYTES, W_BYTES, B_VALUE)
VALUES
    (NULL, NULL, NULL, NULL, NULL, NULL)
"@

    Invoke-VfpSql $connection @"
INSERT INTO vfp9_binary
    (V_TEXT, Q_BYTES, C_BYTES, M_BYTES, W_BYTES, B_VALUE)
VALUES
    ('', 0h, 0h, 0h, 0h, 0.0)
"@

    Invoke-VfpSql $connection "DELETE FROM vfp9_binary WHERE ID = 2"
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

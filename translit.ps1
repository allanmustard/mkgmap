param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile,
    [Parameter(Mandatory=$true)]
    [string]$OutputFile,
    [int]$LinesPerChunk = 1000000,
    [string]$LogFile = "translit_unmapped.log",
    [switch]$AsciiOutput
)

# ----------------- ENCODING PROVIDER (PowerShell 7 fix) -----------------
[System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)

# ----------------- START TIME -----------------
$StartTime = Get-Date
Write-Host "=== Transliteration started at $StartTime ==="

# ----------------- MAPPING (ASCII-only source) -----------------

$map = @{}

function AddMap($code, $latin) {
    $char = [char]$code
    $map[$char] = $latin
}

# Russian base
AddMap 1040 "A"; AddMap 1041 "B"; AddMap 1042 "V"; AddMap 1043 "G"; AddMap 1044 "D"
AddMap 1045 "E"; AddMap 1025 "Yo"; AddMap 1046 "Zh"; AddMap 1047 "Z"; AddMap 1048 "I"
AddMap 1049 "Y"; AddMap 1050 "K"; AddMap 1051 "L"; AddMap 1052 "M"; AddMap 1053 "N"
AddMap 1054 "O"; AddMap 1055 "P"; AddMap 1056 "R"; AddMap 1057 "S"; AddMap 1058 "T"
AddMap 1059 "U"; AddMap 1060 "F"; AddMap 1061 "Kh"; AddMap 1062 "Ts"; AddMap 1063 "Ch"
AddMap 1064 "Sh"; AddMap 1065 "Shch"; AddMap 1067 "Y"; AddMap 1069 "E"; AddMap 1070 "Yu"
AddMap 1071 "Ya"

AddMap 1072 "a"; AddMap 1073 "b"; AddMap 1074 "v"; AddMap 1075 "g"; AddMap 1076 "d"
AddMap 1077 "e"; AddMap 1105 "yo"; AddMap 1078 "zh"; AddMap 1079 "z"; AddMap 1080 "i"
AddMap 1081 "y"; AddMap 1082 "k"; AddMap 1083 "l"; AddMap 1084 "m"; AddMap 1085 "n"
AddMap 1086 "o"; AddMap 1087 "p"; AddMap 1088 "r"; AddMap 1089 "s"; AddMap 1090 "t"
AddMap 1091 "u"; AddMap 1092 "f"; AddMap 1093 "kh"; AddMap 1094 "ts"; AddMap 1095 "ch"
AddMap 1096 "sh"; AddMap 1097 "shch"; AddMap 1099 "y"; AddMap 1101 "e"; AddMap 1102 "yu"
AddMap 1103 "ya"

AddMap 1068 ""; AddMap 1100 ""; AddMap 1066 ""; AddMap 1098 ""

# Kazakh
AddMap 1240 "A"; AddMap 1241 "a"
AddMap 1170 "G"; AddMap 1171 "g"
AddMap 1178 "Q"; AddMap 1179 "q"
AddMap 1186 "N"; AddMap 1187 "n"
AddMap 1256 "O"; AddMap 1257 "o"
AddMap 1200 "U"; AddMap 1201 "u"
AddMap 1198 "U"; AddMap 1199 "u"
AddMap 1210 "H"; AddMap 1211 "h"

# Kyrgyz
AddMap 1256 "O"; AddMap 1257 "o"
AddMap 1198 "U"; AddMap 1199 "u"

# Tajik
AddMap 1170 "G"; AddMap 1171 "g"
AddMap 1178 "Q"; AddMap 1179 "q"
AddMap 1202 "H"; AddMap 1203 "h"
AddMap 1262 "U"; AddMap 1263 "u"
AddMap 1033 "Lj"; AddMap 1113 "lj"
AddMap 1034 "Nj"; AddMap 1114 "nj"

# Uzbek
AddMap 1170 "G"; AddMap 1171 "g"
AddMap 1178 "Q"; AddMap 1179 "q"
AddMap 1202 "H"; AddMap 1203 "h"
AddMap 1038 "O"; AddMap 1118 "o"

# Turkmen Cyrillic
AddMap 1240 "A"; AddMap 1241 "a"
AddMap 1174 "J"; AddMap 1175 "j"
AddMap 1186 "N"; AddMap 1187 "n"
AddMap 1256 "O"; AddMap 1257 "o"
AddMap 1198 "U"; AddMap 1199 "u"

# ----------------- TRANSLITERATION -----------------

function TransliterateLine([string]$line, [hashtable]$localUnmapped) {
    $len = $line.Length
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $len; $i++) {
        $ch = $line[$i]
        if ($map.ContainsKey($ch)) {
            [void]$sb.Append($map[$ch])
        } else {
            [void]$sb.Append($ch)
            if (-not $localUnmapped.ContainsKey($ch)) {
                $localUnmapped[$ch] = 1
            } else {
                $localUnmapped[$ch]++
            }
        }
    }
    $sb.ToString()
}

# ----------------- CHUNK DIRECTORY -----------------

$chunkDir = Join-Path (Split-Path $OutputFile -Parent) "chunks_tmp"
if (Test-Path $chunkDir) { Remove-Item $chunkDir -Recurse -Force }
New-Item -ItemType Directory -Path $chunkDir | Out-Null

# ----------------- SPLIT INTO CHUNKS -----------------

$chunkIndex = 0
$lineCountInChunk = 0
$buffer = New-Object System.Collections.Generic.List[string]

Get-Content $InputFile -ReadCount 1 | ForEach-Object {
    $buffer.Add($_)
    $lineCountInChunk++

    if ($lineCountInChunk -ge $LinesPerChunk) {
        $chunkIndex++
        $chunkPath = Join-Path $chunkDir ("chunk_{0:D4}.txt" -f $chunkIndex)
        [System.IO.File]::WriteAllLines($chunkPath, $buffer)
        $buffer.Clear()
        $lineCountInChunk = 0
    }
}

if ($buffer.Count -gt 0) {
    $chunkIndex++
    $chunkPath = Join-Path $chunkDir ("chunk_{0:D4}.txt" -f $chunkIndex)
    [System.IO.File]::WriteAllLines($chunkPath, $buffer)
    $buffer.Clear()
}

$chunkCount = $chunkIndex

# ----------------- PARALLEL PROCESSING -----------------

if (Test-Path $LogFile) { Remove-Item $LogFile -Force }

$encodingName = if ($AsciiOutput) { "ASCII" } else { "UTF8" }

$jobs = @()

for ($i = 1; $i -le $chunkCount; $i++) {
    $inChunk  = Join-Path $chunkDir ("chunk_{0:D4}.txt" -f $i)
    $outChunk = Join-Path $chunkDir ("chunk_{0:D4}.out.txt" -f $i)
    $logChunk = Join-Path $chunkDir ("chunk_{0:D4}.log.txt" -f $i)

    $job = Start-Job -ScriptBlock {
        param($inChunk, $outChunk, $logChunk, $encodingName, $map)

        $localUnmapped = @{}
        $buf = New-Object System.Collections.Generic.List[string]

        $enc = if ($encodingName -eq "ASCII") {
            [System.Text.Encoding]::GetEncoding(20127)
        } else {
            [System.Text.Encoding]::GetEncoding(65001)
        }

        if (-not (Test-Path $inChunk)) {
            "" | Set-Content $outChunk -Encoding $encodingName
            "" | Set-Content $logChunk -Encoding UTF8
            return
        }

        Get-Content $inChunk -ReadCount 1 | ForEach-Object {
            $line = $_
            $len = $line.Length
            $sb = New-Object System.Text.StringBuilder
            for ($j = 0; $j -lt $len; $j++) {
                $ch = $line[$j]
                if ($map.ContainsKey($ch)) {
                    [void]$sb.Append($map[$ch])
                } else {
                    [void]$sb.Append($ch)
                    if (-not $localUnmapped.ContainsKey($ch)) {
                        $localUnmapped[$ch] = 1
                    } else {
                        $localUnmapped[$ch]++
                    }
                }
            }
            $buf.Add($sb.ToString())

            if ($buf.Count -ge 10000) {
                $sw = New-Object System.IO.StreamWriter($outChunk, $true, $enc)
                foreach ($lineOut in $buf) { $sw.WriteLine($lineOut) }
                $sw.Close()
                $buf.Clear()
            }
        }

        if ($buf.Count -gt 0) {
            $sw = New-Object System.IO.StreamWriter($outChunk, $true, $enc)
            foreach ($lineOut in $buf) { $sw.WriteLine($lineOut) }
            $sw.Close()
            $buf.Clear()
        }

        if (-not (Test-Path $outChunk)) {
            "" | Set-Content $outChunk -Encoding $encodingName
        }

        $entries = $localUnmapped.GetEnumerator() | Sort-Object Name
        $logLines = New-Object System.Collections.Generic.List[string]
        $logLines.Add("Chunk: $inChunk")
        foreach ($e in $entries) {
            $line = "Char: {0} (U+{1:X4}) Count: {2}" -f $e.Key, [int][char]$e.Key, $e.Value
            $logLines.Add($line)
        }
        $logLines.Add("")
        [System.IO.File]::WriteAllLines($logChunk, $logLines, [System.Text.Encoding]::UTF8)
    } -ArgumentList $inChunk, $outChunk, $logChunk, $encodingName, $map

    $jobs += $job
}

Wait-Job -Job $jobs | Out-Null
Receive-Job -Job $jobs | Out-Null
Remove-Job -Job $jobs

Start-Sleep -Seconds 2

# ----------------- MERGE OUTPUT (StreamWriter) -----------------

if (Test-Path $OutputFile) { Remove-Item $OutputFile -Force }

$finalEnc = if ($encodingName -eq "ASCII") {
    [System.Text.Encoding]::GetEncoding(20127)
} else {
    [System.Text.Encoding]::GetEncoding(65001)
}

for ($i = 1; $i -le $chunkCount; $i++) {
    $outChunk = Join-Path $chunkDir ("chunk_{0:D4}.out.txt" -f $i)

    if (-not (Test-Path $outChunk)) {
        Write-Host "WARNING: Missing output for chunk $i — creating empty placeholder."
        "" | Set-Content $outChunk -Encoding $encodingName
    }

    $lines = Get-Content $outChunk -ReadCount 10000

    $sw = New-Object System.IO.StreamWriter($OutputFile, $true, $finalEnc)
    foreach ($batch in $lines) {
        foreach ($line in $batch) {
            $sw.WriteLine($line)
        }
    }
    $sw.Close()
}

# ----------------- MERGE LOGS -----------------

"" | Set-Content $LogFile -Encoding UTF8

for ($i = 1; $i -le $chunkCount; $i++) {
    $logChunk = Join-Path $chunkDir ("chunk_{0:D4}.log.txt" -f $i)
    if (Test-Path $logChunk) {
        Get-Content $logChunk | Add-Content -Path $LogFile -Encoding UTF8
    }
}

Remove-Item $chunkDir -Recurse -Force

# ----------------- END TIME -----------------
$EndTime = Get-Date
Write-Host "=== Transliteration finished at $EndTime ==="

$Duration = $EndTime - $StartTime
Write-Host "=== Total runtime: $($Duration.ToString()) ==="

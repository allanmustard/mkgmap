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

# ----------------- TRANSLITERATION MAP -----------------

$map = @{}

function AddMap($code, $latin) {
    $char = [char]$code
    $map[$char] = $latin
}

# ---------- ARABIC CORE ----------
AddMap 0x0621 "ʾ"
AddMap 0x0622 "a"
AddMap 0x0623 "ʾa"
AddMap 0x0624 "ʾu"
AddMap 0x0625 "ʾi"
AddMap 0x0626 "ʾy"
AddMap 0x0627 "a"
AddMap 0x0628 "b"
AddMap 0x0629 "t"
AddMap 0x062A "t"
AddMap 0x062B "th"
AddMap 0x062C "j"
AddMap 0x062D "ḥ"
AddMap 0x062E "kh"
AddMap 0x062F "d"
AddMap 0x0630 "dh"
AddMap 0x0631 "r"
AddMap 0x0632 "z"
AddMap 0x0633 "s"
AddMap 0x0634 "sh"
AddMap 0x0635 "ṣ"
AddMap 0x0636 "ḍ"
AddMap 0x0637 "ṭ"
AddMap 0x0638 "ẓ"
AddMap 0x0639 "ʿ"
AddMap 0x063A "gh"
AddMap 0x0641 "f"
AddMap 0x0642 "q"
AddMap 0x0643 "k"
AddMap 0x0644 "l"
AddMap 0x0645 "m"
AddMap 0x0646 "n"
AddMap 0x0647 "h"
AddMap 0x0648 "w"
AddMap 0x0649 "a"
AddMap 0x064A "y"

# ---------- PERSIAN ----------
AddMap 0x067E "p"
AddMap 0x0686 "ch"
AddMap 0x0698 "zh"
AddMap 0x06A9 "k"
AddMap 0x06AF "g"

# ---------- PASHTO ----------
AddMap 0x0681 "h"
AddMap 0x0685 "ts"
AddMap 0x0689 "ḍ"
AddMap 0x0693 "ṛ"
AddMap 0x0696 "gh"
AddMap 0x069A "s"
AddMap 0x069C "x"
AddMap 0x069D "ž"

# ---------- URDU ----------
AddMap 0x06CC "y"
AddMap 0x06BE "h"
AddMap 0x06D2 "e"
AddMap 0x06D3 "e"

# ---------- ARABIC-INDIC DIGITS ----------
AddMap 0x0660 "0"; AddMap 0x0661 "1"; AddMap 0x0662 "2"; AddMap 0x0663 "3"
AddMap 0x0664 "4"; AddMap 0x0665 "5"; AddMap 0x0666 "6"; AddMap 0x0667 "7"
AddMap 0x0668 "8"; AddMap 0x0669 "9"


# ---------- HEBREW ----------
# Simple consonantal transliteration

AddMap 1488 "ʾ";  # א
AddMap 1489 "b";  # ב
AddMap 1490 "g";  # ג
AddMap 1491 "d";  # ד
AddMap 1492 "h";  # ה
AddMap 1493 "v";  # ו
AddMap 1494 "z";  # ז
AddMap 1495 "ḥ";  # ח
AddMap 1496 "ṭ";  # ט
AddMap 1497 "y";  # י
AddMap 1498 "k";  # ך
AddMap 1499 "k";  # כ
AddMap 1500 "l";  # ל
AddMap 1501 "m";  # ם
AddMap 1502 "m";  # מ
AddMap 1503 "n";  # ן
AddMap 1504 "n";  # נ
AddMap 1505 "s";  # ס
AddMap 1506 "ʿ";  # ע
AddMap 1507 "p";  # ף
AddMap 1508 "p";  # פ
AddMap 1509 "ts"; # ץ
AddMap 1510 "ts"; # צ
AddMap 1511 "q";  # ק
AddMap 1512 "r";  # ר
AddMap 1513 "sh"; # ש
AddMap 1514 "t";  # ת


# ----------------- TRANSLITERATION -----------------

function TransliterateLine([string]$line, [hashtable]$localUnmapped) {
    $len = $line.Length
    $sb = New-Object System.Text.StringBuilder

    for ($i = 0; $i -lt $len; $i++) {
        $ch = $line[$i]

        if ($map.ContainsKey($ch)) {
            [void]$sb.Append($map[$ch])
        }
        else {
            [void]$sb.Append($ch)

            if (-not $localUnmapped.ContainsKey($ch)) {
                $localUnmapped[$ch] = 1
            }
            else {
                $localUnmapped[$ch]++
            }
        }
    }

    $sb.ToString()
}

function ContainsRTL {
    param([string]$Text)

    foreach ($ch in $Text.ToCharArray()) {

        $code = [int]$ch

        if (
            ($code -ge 0x0590 -and $code -le 0x05FF) -or
            ($code -ge 0x0600 -and $code -le 0x06FF) -or
            ($code -ge 0x0750 -and $code -le 0x077F) -or
            ($code -ge 0x08A0 -and $code -le 0x08FF)
        ) {
            return $true
        }
    }

    return $false
}

function Convert-ToTitleCase {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture

    return $culture.TextInfo.ToTitleCase(
        $Text.ToLowerInvariant()
    )
}

$reader = [System.IO.StreamReader]::new($InputFile)

$writer = [System.IO.StreamWriter]::new(
    $OutputFile,
    $false,
    [System.Text.Encoding]::UTF8
)

$objectCount = 0

$currentObject = New-Object System.Collections.Generic.List[string]

function Write-ObjectWithNameInt {
    param(
        [System.Collections.Generic.List[string]]$ObjectLines
    )

    $name = $null
    $nameEn = $null
    $nameInt = $null
    $intName = $null

    $nameLineIndex = -1

    $hasNameEn = $false
    $hasNameInt = $false

    for ($i = 0; $i -lt $ObjectLines.Count; $i++) {

        $line = $ObjectLines[$i]

        if ($line -match '<tag k="name" v="([^"]*)"') {
            $name = $matches[1]
            $nameLineIndex = $i
        }

        if ($line -match '<tag k="name:en" v="([^"]*)"') {
            $nameEn = $matches[1]
            $hasNameEn = $true
        }

        if ($line -match '<tag k="name_int" v="([^"]*)"') {
            $nameInt = $matches[1]
            $hasNameInt = $true
        }

        if ($line -match '<tag k="int_name" v="([^"]*)"') {
            $intName = $matches[1]
        }
    }

    #
    # Generate name_int if needed
    #
    if (
        $nameLineIndex -ge 0 -and
        -not $hasNameEn -and
        -not $hasNameInt -and
        (ContainsRTL $name)
    )
    {
        $localUnmapped = @{}

        $nameInt = TransliterateLine $name $localUnmapped

        $nameInt = Convert-ToTitleCase $nameInt

        $insertLine =
            '  <tag k="name_int" v="' +
            [System.Security.SecurityElement]::Escape($nameInt) +
            '"/>'

        $ObjectLines.Insert(
            $nameLineIndex + 1,
            $insertLine
        )

        $hasNameInt = $true
    }

    #
    # Select preferred international form
    #
    $intl = $null

    if ($nameEn) {
        $intl = $nameEn
    }
    elseif ($intName) {
        $intl = $intName
    }
    elseif ($nameInt) {
        $intl = $nameInt
    }

    #
    # Build final Garmin display name
    # RTL order: Local International
    #
    if (
        $nameLineIndex -ge 0 -and
        $name -and
        $intl -and
        $name.Trim() -ne "" -and
        $intl.Trim() -ne "" -and
        $name -ne $intl
    )
    {
        if (
            $name.IndexOf(
                $intl,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -lt 0
        )
        {
            $newName = "$name $intl"

            $ObjectLines[$nameLineIndex] =
                '  <tag k="name" v="' +
                [System.Security.SecurityElement]::Escape($newName) +
                '"/>'
        }
    }

    foreach ($outLine in $ObjectLines) {
        $writer.WriteLine($outLine)
    }
}

while (($line = $reader.ReadLine()) -ne $null)
{
    if ($line -match '^\s*<(node|way|relation)\b')
    {
        $currentObject.Clear()
        $currentObject.Add($line)

        while (($line = $reader.ReadLine()) -ne $null)
        {
            $currentObject.Add($line)

            if ($line -match '^\s*</(node|way|relation)>')
            {
                break
            }
        }

        Write-ObjectWithNameInt $currentObject

        $objectCount++

        if (($objectCount % 100000) -eq 0)
        {
            Write-Host ("Processed {0:N0} objects" -f $objectCount)
        }
    }
        else
    {
        $writer.WriteLine($line)
    }
}

$writer.Close()
$reader.Close()

$EndTime = Get-Date

Write-Host "=== Name_int generation finished at $EndTime ==="

$Duration = $EndTime - $StartTime

Write-Host "=== Total runtime: $($Duration.ToString()) ==="

$Duration = $EndTime - $StartTime
Write-Host "=== Total runtime: $($Duration.ToString()) ==="

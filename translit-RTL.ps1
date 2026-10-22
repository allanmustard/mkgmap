param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile,
    [Parameter(Mandatory=$true)]
    [string]$OutputFile,
    [int]$LinesPerChunk = 1000000,
    [string]$LogFile = "translit_rtl_unmapped.log",
    [switch]$AsciiOutput
)

[System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)

$StartTime = Get-Date
Write-Host "=== RTL Transliteration started at $StartTime ==="

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

# ----------------- CHUNK DIRECTORY -----------------

$chunkDir = Join-Path (Split-Path $OutputFile -Parent) "chunks_rtl_tmp"
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

        # ----------------- FUNCTIONS INSIDE JOB -----------------

        function StripArabicDiacritics([string]$text) {
            $sb = New-Object System.Text.StringBuilder
            foreach ($ch in $text.ToCharArray()) {
                $code = [int]$ch
                if ($code -in 0x064B..0x065F) { continue }
                [void]$sb.Append($ch)
            }
            return $sb.ToString()
        }

        function IsRTLChar([char]$ch) {
            $code = [int]$ch
            if (($code -ge 0x0600 -and $code -le 0x06FF) -or
                ($code -ge 0x0750 -and $code -le 0x077F) -or
                ($code -ge 0x08A0 -and $code -le 0x08FF) -or
                ($code -ge 0x0590 -and $code -le 0x05FF)) {
                return $true
            }
            return $false
        }

        function TransliterateWord([string]$word, [hashtable]$localUnmapped) {
            $sb = New-Object System.Text.StringBuilder
            foreach ($ch in $word.ToCharArray()) {
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
            return $sb.ToString()
        }

        function ApplyAlHeuristicToWord([string]$word, [string]$originalWord) {
            if ($originalWord.StartsWith("ال")) {
                if ($word.Length -gt 2) {
                    return "al-" + $word.Substring(2)
                } else {
                    return "al"
                }
            }
            return $word
        }

        function ReconstructShortVowels([string]$word) {
            $w = $word

            # Fix impossible 3-consonant clusters (corrected regex)
            $w = $w -replace "([bcdfghjklmnpqrstvwxyzḥḍṭẓṣʿ]{2})([bcdfghjklmnpqrstvwxyzḥḍṭẓṣʿ])", '$1a$2'

            # Common verb pattern: ystghrb -> yastaghrib
            $w = $w -replace "^yst", "yast"
            $w = $w -replace "ghrb$", "ghrib"

            # lḥẓ -> laḥẓa
            if ($w -eq "lḥẓ") { $w = "laḥẓa" }

            # wdʿ -> wadaʿ
            if ($w -eq "wdʿ") { $w = "wadaʿ" }

            # Final consonant -> add 'a'
            if ($w -match "^[bcdfghjklmnpqrstvwxyzḥḍṭẓṣʿ]+$") {
                $w = $w + "a"
            }

            return $w
        }

        function ReconstructDoubledConsonants([string]$word) {
            $w = $word

            $w = $w -replace "^tahdath", "tahaddath"
            $w = $w -replace "muhbun", "muhibbun"
            $w = $w -replace "muwadin", "muwaddin"

            return $w
        }

        function TransliterateLineWordBased([string]$line, [hashtable]$localUnmapped) {
            $parts = [System.Text.RegularExpressions.Regex]::Split($line, "(\s+)")
            $result = New-Object System.Text.StringBuilder

            for ($i = 0; $i -lt $parts.Length; $i++) {
                $segment = $parts[$i]

                if ($segment -match "^\s+$") {
                    [void]$result.Append($segment)
                    continue
                }

                $hasRTL = $false
                foreach ($ch in $segment.ToCharArray()) {
                    if (IsRTLChar $ch) { $hasRTL = $true; break }
                }

                if (-not $hasRTL) {
                    [void]$result.Append($segment)
                    continue
                }

                $words = $segment -split "\s+"
                $latinWords = New-Object System.Collections.Generic.List[string]

                foreach ($w in $words) {
                    if ([string]::IsNullOrWhiteSpace($w)) { continue }

                    $clean = StripArabicDiacritics $w
                    $latin = TransliterateWord $clean $localUnmapped
                    $latin = ApplyAlHeuristicToWord $latin $clean
                    $latin = ReconstructShortVowels $latin
                    $latin = ReconstructDoubledConsonants $latin

                    $latinWords.Add($latin)
                }

                [array]::Reverse($latinWords)
                $revSegment = [string]::Join(" ", $latinWords)

                [void]$result.Append($revSegment)
            }

            return $result.ToString()
        }

        # ----------------- PROCESS CHUNK -----------------

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

            $final = TransliterateLineWordBased $_ $localUnmapped
            $buf.Add($final)

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

        # ----------------- LOG UNMAPPED -----------------

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

# ----------------- MERGE OUTPUT -----------------

if (Test-Path $OutputFile) { Remove-Item $OutputFile -Force }

$finalEnc = if ($encodingName -eq "ASCII") {
    [System.Text.Encoding]::GetEncoding(20127)
} else {
    [System.Text.Encoding]::GetEncoding(65001)
}

for ($i = 1; $i -le $chunkCount; $i++) {
    $outChunk = Join-Path $chunkDir ("chunk_{0:D4}.out.txt" -f $i)

    if (-not (Test-Path $outChunk)) {
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

$EndTime = Get-Date
Write-Host "=== RTL Transliteration finished at $EndTime ==="

$Duration = $EndTime - $StartTime
Write-Host "=== Total runtime: $($Duration.ToString()) ==="

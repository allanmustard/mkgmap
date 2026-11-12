# This PowerShell 7 script transliterates name tags from OpenStreetMap data from Cyrillic or diacritical Latin characters to ASCII Latin characters.
# It also converts all single-quote-like characters to apostrophes for consistency and deletes double quotes (") from name tags (to deal with the Soviet habit of putting proper names of businesses in double quotes).
# The script then generates a label for POIs and highways (streets) consisting of the English, international, or ASCII transliterated name tag plus the original name tag.
#
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

# Ukrainian

AddMap 1028 "Ye"   # Є
AddMap 1108 "ye"   # є

AddMap 1030 "I"    # І
AddMap 1110 "i"    # і

AddMap 1031 "Yi"   # Ї
AddMap 1111 "yi"   # ї

AddMap 1168 "G"    # Ґ
AddMap 1169 "g"    # ґ

# Belarusian

AddMap 1038 "U"    # Ў
AddMap 1118 "u"    # ў

# Kazakh + Kyrgyz + Turkmen + Tajik + Uzbek + Azerbaijani
AddMap 1240 "A"; AddMap 1241 "a"
AddMap 1170 "G"; AddMap 1171 "g"
AddMap 1178 "Q"; AddMap 1179 "q"
AddMap 1186 "N"; AddMap 1187 "n"
AddMap 1256 "O"; AddMap 1257 "o"
AddMap 1200 "U"; AddMap 1201 "u"
AddMap 1198 "U"; AddMap 1199 "u"
AddMap 1210 "H"; AddMap 1211 "h"

# Kyrgyz only
AddMap 1198 "U"; AddMap 1199 "u"

# Tajik only
AddMap 1170 "G"; AddMap 1171 "g"
AddMap 1202 "H"; AddMap 1203 "h"
AddMap 1262 "U"; AddMap 1263 "u"
AddMap 1033 "Lj"; AddMap 1113 "lj"
AddMap 1034 "Nj"; AddMap 1114 "nj"

# Uzbek only
AddMap 1038 "O"; AddMap 1118 "o"

# Turkmen Cyrillic only
AddMap 1174 "J"; AddMap 1175 "j"

# ---------- AZERBAIJANI (Cyrillic) ----------
# Roughly ISO-based, common Latin usage

AddMap 1040 "A";  AddMap 1072 "a"
AddMap 1041 "B";  AddMap 1073 "b"
AddMap 1042 "V";  AddMap 1074 "v"
AddMap 1043 "G";  AddMap 1075 "g"
AddMap 1044 "D";  AddMap 1076 "d"
AddMap 1045 "E";  AddMap 1077 "e"
AddMap 1046 "Zh"; AddMap 1078 "zh"
AddMap 1047 "Z";  AddMap 1079 "z"
AddMap 1048 "I";  AddMap 1080 "i"
AddMap 1049 "Y";  AddMap 1081 "y"
AddMap 1050 "K";  AddMap 1082 "k"
AddMap 1051 "L";  AddMap 1083 "l"
AddMap 1052 "M";  AddMap 1084 "m"
AddMap 1053 "N";  AddMap 1085 "n"
AddMap 1054 "O";  AddMap 1086 "o"
AddMap 1055 "P";  AddMap 1087 "p"
AddMap 1056 "R";  AddMap 1088 "r"
AddMap 1057 "S";  AddMap 1089 "s"
AddMap 1058 "T";  AddMap 1090 "t"
AddMap 1059 "U";  AddMap 1091 "u"
AddMap 1060 "F";  AddMap 1092 "f"
AddMap 1061 "Kh"; AddMap 1093 "kh"
AddMap 1062 "Ts"; AddMap 1094 "ts"
AddMap 1063 "Ch"; AddMap 1095 "ch"
AddMap 1064 "Sh"; AddMap 1096 "sh"
AddMap 1065 "Shch";AddMap 1097 "shch"
AddMap 1066 "";   AddMap 1098 ""
AddMap 1067 "Y";  AddMap 1099 "y"
AddMap 1068 "";   AddMap 1100 ""
AddMap 1069 "E";  AddMap 1101 "e"
AddMap 1070 "Yu"; AddMap 1102 "yu"
AddMap 1071 "Ya"; AddMap 1103 "ya"

# Azerbaijani-specific Cyrillic letters

# ----------------- AZERBAIJANI LATIN -> ASCII -----------------

AddMap 304  "I"   # İ
AddMap 305  "i"   # ı

AddMap 214  "O"   # Ö
AddMap 246  "o"   # ö

AddMap 220  "U"   # Ü
AddMap 252  "u"   # ü

AddMap 199  "Ch"  # Ç
AddMap 231  "ch"  # ç

AddMap 350  "Sh"  # Ş
AddMap 351  "sh"  # ş

AddMap 286  "G"  # Ğ
AddMap 287  "g"  # ğ

AddMap 399  "E"   # Ə
AddMap 601  "e"   # ə

# ----------------- GEORGIAN (Mkhedruli) -----------------
# ISO 9984 (standard scientific transliteration)

AddMap 4304 "a"   # ა
AddMap 4305 "b"   # ბ
AddMap 4306 "g"   # გ
AddMap 4307 "d"   # დ
AddMap 4308 "e"   # ე
AddMap 4309 "v"   # ვ
AddMap 4310 "z"   # ზ
AddMap 4311 "t"   # თ
AddMap 4312 "i"   # ი
AddMap 4313 "k"   # კ
AddMap 4314 "l"   # ლ
AddMap 4315 "m"   # მ
AddMap 4316 "n"   # ნ
AddMap 4317 "o"   # ო
AddMap 4318 "p"   # პ
AddMap 4319 "zh"  # ჟ
AddMap 4320 "r"   # რ
AddMap 4321 "s"   # ს
AddMap 4322 "t"   # ტ
AddMap 4323 "u"   # უ
AddMap 4324 "p"   # ფ
AddMap 4325 "k"   # ქ
AddMap 4326 "gh"  # ღ
AddMap 4327 "q"   # ყ
AddMap 4328 "sh"  # შ
AddMap 4329 "ch"  # ჩ
AddMap 4330 "ts"  # ც
AddMap 4331 "dz"  # ძ
AddMap 4332 "ts"  # წ
AddMap 4333 "ch"  # ჭ
AddMap 4334 "kh"  # ხ
AddMap 4335 "j"   # ჯ
AddMap 4336 "h"   # ჰ

# ----------------- ARMENIAN -----------------
# ISO 9985 transliteration

AddMap 1329 "A"; AddMap 1377 "a"   # Ա ա
AddMap 1330 "B"; AddMap 1378 "b"   # Բ բ
AddMap 1331 "G"; AddMap 1379 "g"   # Գ գ
AddMap 1332 "D"; AddMap 1380 "d"   # Դ դ
AddMap 1333 "E"; AddMap 1381 "e"   # Ե ե
AddMap 1334 "Z"; AddMap 1382 "z"   # Զ զ
AddMap 1335 "E"; AddMap 1383 "e"   # Է է
AddMap 1336 "Y"; AddMap 1384 "y"   # Ը ը
AddMap 1337 "T"; AddMap 1385 "t"   # Թ թ
AddMap 1338 "Zh";AddMap 1386 "zh"  # Ժ ժ
AddMap 1339 "I"; AddMap 1387 "i"   # Ի ի
AddMap 1340 "L"; AddMap 1388 "l"   # Լ լ
AddMap 1341 "Kh";AddMap 1389 "kh"  # Խ խ
AddMap 1342 "Ts";AddMap 1390 "ts"  # Ծ ծ
AddMap 1343 "K"; AddMap 1391 "k"   # Կ կ
AddMap 1344 "H"; AddMap 1392 "h"   # Հ հ
AddMap 1345 "Dz";AddMap 1393 "dz"  # Ձ ձ
AddMap 1346 "Gh";AddMap 1394 "gh"  # Ղ ղ
AddMap 1347 "T"; AddMap 1395 "t"   # Ճ ճ
AddMap 1348 "M"; AddMap 1396 "m"   # Մ մ
AddMap 1349 "Y"; AddMap 1397 "y"   # Յ յ
AddMap 1350 "N"; AddMap 1398 "n"   # Ն ն
AddMap 1351 "Sh";AddMap 1399 "sh"  # Շ շ
AddMap 1352 "Vo";AddMap 1400 "vo"  # Ո ո
AddMap 1353 "Ch";AddMap 1401 "ch"  # Չ չ
AddMap 1354 "P"; AddMap 1402 "p"   # Պ պ
AddMap 1355 "J"; AddMap 1403 "j"   # Ջ ջ
AddMap 1356 "R"; AddMap 1404 "r"   # Ռ ռ
AddMap 1357 "S"; AddMap 1405 "s"   # Ս ս
AddMap 1358 "V"; AddMap 1406 "v"   # Վ վ
AddMap 1359 "T"; AddMap 1407 "t"   # Տ տ
AddMap 1360 "R"; AddMap 1408 "r"   # Ր ր
AddMap 1361 "Ts";AddMap 1409 "ts"  # Ց ց
AddMap 1362 "V"; AddMap 1410 "v"   # Ւ ւ
AddMap 1363 "P"; AddMap 1411 "p"   # Փ փ
AddMap 1364 "K"; AddMap 1412 "k"   # Ք ք
AddMap 1365 "O"; AddMap 1413 "o"   # Օ օ
AddMap 1366 "F"; AddMap 1414 "f"   # Ֆ ֆ

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

Add-Type -AssemblyName System.Web

function EscapeXmlAttribute {
    param([string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    $Text = $Text.Replace("&", "&amp;")
    $Text = $Text.Replace("<", "&lt;")
    $Text = $Text.Replace(">", "&gt;")

    return $Text
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

#
# Normalize various single-quote-like characters with apostrophe (') and delete double quotes (")
#
for ($i = 0; $i -lt $ObjectLines.Count; $i++) {

    $line = $ObjectLines[$i]

    if ($line -match '<tag k="name" v="([^"]*)"') {

    $name = [System.Web.HttpUtility]::HtmlDecode($matches[1])

    $name = $name.Replace('"', '')
    $name = $name.Replace([char]0x02BB,"'")
    $name = $name.Replace([char]0x2018,"'")
    $name = $name.Replace([char]0x2019,"'")

    $nameLineIndex = $i
}

if ($line -match '<tag k="name:en" v="([^"]*)"') {

    $nameEn = [System.Web.HttpUtility]::HtmlDecode($matches[1])

    $nameEn = $nameEn.Replace('"', '')
    $nameEn = $nameEn.Replace([char]0x02BB,"'")
    $nameEn = $nameEn.Replace([char]0x2018,"'")
    $nameEn = $nameEn.Replace([char]0x2019,"'")

    $hasNameEn = $true
}

if ($line -match '<tag k="name_int" v="([^"]*)"') {

    $nameInt = [System.Web.HttpUtility]::HtmlDecode($matches[1])

    $nameInt = $nameInt.Replace('"', '')
    $nameInt = $nameInt.Replace([char]0x02BB,"'")
    $nameInt = $nameInt.Replace([char]0x2018,"'")
    $nameInt = $nameInt.Replace([char]0x2019,"'")

    $hasNameInt = $true
}

if ($line -match '<tag k="int_name" v="([^"]*)"') {

    $intName = [System.Web.HttpUtility]::HtmlDecode($matches[1])

    $intName = $intName.Replace('"', '')
    $intName = $intName.Replace([char]0x02BB,"'")
    $intName = $intName.Replace([char]0x2018,"'")
    $intName = $intName.Replace([char]0x2019,"'")
}
}

    #
    # Generate name_int if needed
    #
    if (
        $nameLineIndex -ge 0 -and
        -not $hasNameEn -and
        -not $hasNameInt -and
        -not (ContainsRTL $name)
    )
    {
        $localUnmapped = @{}

        $nameInt = TransliterateLine $name $localUnmapped

        $nameInt = $nameInt #Convert-ToTitleCase $nameInt

        $insertLine =
    '  <tag k="name_int" v="' +
    (EscapeXmlAttribute $nameInt) +
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
    # Build Garmin display name
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

$newName = "$intl $name"

#
# Force any letter immediately following an apostrophe to lowercase
#

$chars = $newName.ToCharArray()

for ($j = 0; $j -lt ($chars.Length - 1); $j++) {

    if ($chars[$j] -eq "'") {

        $chars[$j + 1] = [char](
            [string]$chars[$j + 1]
        ).ToLowerInvariant()
    }
}

$newName = -join $chars

#$ObjectLines[$nameLineIndex] =
#    '  <tag k="name" v="' +
#    (EscapeXmlAttribute $newName) +
#    '"/>'
#        }
#    }
$escapedName = EscapeXmlAttribute $newName


$ObjectLines[$nameLineIndex] =
    '  <tag k="name" v="' +
    $escapedName +
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
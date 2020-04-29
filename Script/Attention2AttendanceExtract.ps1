Import-Module '\\Powershell\Logging\LogThis.ps1'
Import-Module '\\Powershell\Logging\logPurge.ps1'
Import-Module '\\Powershell\Pass Encryption\SecureThis.ps1'
Import-Module '\\Powershell\SQL\SQL interface.ps1'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

<#

    Pulls Attention to Attendance's Printed Letter data using REST API
    and SQL-Inserts new records into Interventions table.

    Author: MC
    Date: 3/13/19

    Required parameters: Type
    Returns: PSObject

#>


<#
    Parameters.
#>
    $dbSrv = ''        ## server name
    $db = ''           ## database name
    $siaUser = ''      ## vendor account name
    $installPath = ''  ## local filepath to script root directory
    
    $districtId =      ## id within vendor's system
    $maxSize = 100     ## Number of records returned by REST method GET

<#
    Constants.
#>
    $pwLoc = $installPath + 'A2A\Credentials\secure.txt'
    $queryPath = $installPath + 'A2A\Query\InsertLetter.txt'
    $logPath = $installPath + "A2A\Log\"
    $logDate = Get-Date -Format yyyyMMdd
    $logFile = $logPath + "Log $logDate.log"


<#
    Utilizes A2A API to fetch data from A2A servers;
    Returns PSOBject with dataset.
#>
Function Fetch-A2A() {

    param(
        [Parameter()]
        [ValidateSet(
            "letter/ALL",
            "letter/SUMMARY",
            "letter/TO_BE_PRINTED",
            "letter/PRE_LOADED",
            "letter/SUPPRESSED",
            "conference/SUMMARY",
            "conference/TO_BE_SCHEDULED",
            "conference/TO_BE_CONDUCTED",
            "conference/TO_BE_CLOSED",
            "conference/TO_BE_RESCHEDULED",
            "conference/CLOSED")]
        [String[]] $Type = $(Throw "Type must be specified."),

        [Parameter()]
        [ValidateSet(
            "json",
            "html",
            "XML")]
        [String[]] $Format = 'json',
        [String] $Page = '1',
        [String] $Size = '100',
        [String] $Student_Id = '',  ## (Optional) Specify student (ignored when type=l2)
        [String] $Username = $(Throw "Username must be specified."),
        [String] $Password = $(Throw "Password must be specified."),
        [String] $District = $(Throw "District must be specified.")
    )

    ## Compose API components
    $base_uri = "https://a2aapi.sia-us.com/api/data/$District/"
    $auth_str = "?userName=$Username&password=$Password&page=$page&page_size=$size&format=$format"
    $uri = $base_uri + $Type + $Student_Id + $auth_str

    ## Return fetched data from REST method GET
    $Cert = (dir Cert:\LocalMachine\My\9842FFA3E89B80F9EC8A1906C8903E569451168D)
    return Invoke-RestMethod -Method Get -Uri $uri -Certificate $Cert
}


<#
    Determines number of pages based on total Records returned.
#>
Function Get-PageCount() {
    Param(
        [Int] $RecordCount,
        [Int] $PageSize
    )

    return [Math]::Ceiling($RecordCount / $PageSize)
}


<#
    Formats A2A code into Aeries' Standards.
#>
Function Get-LetterStrings($code) {

    Switch ($code) {
        'L1' {return 'LT1', 'Truancy Letter 1'}
        'L2' {return 'LT2', 'Truancy Letter 2'}
        'L3' {return 'LT3', 'Truancy Letter 3'}
        'EEA1' {return 'EELtr1', 'Excessive Excused Letter 1'}
        'EEA2' {return 'EELtr2', 'Excessive Excused Letter 2'}
    }
}


<#
    Formats String to be Inserted into Intervention record's CO (Comment) column.
#>
Function Format-CommentString() {

    Param(
        [String] $Letter,
        [String] $SentDate
    )
    return "{0} was mailed to student''s home address on {1}." -f $Letter, $SentDate
}


<#
    Boolean check for if Letter has been Printed.
#>
Function Check-LetterStatus($code) {
    return $code -eq 'PR'
}


<#
    Formats Date from A2A to SQL format.
#>
Function Format-DateString($date) {
    return [datetime]::ParseExact($date, 'yyyy-mm-dd', $null).ToString("mm/dd/yyyy")
}


<#
    MAIN
#>
$queryTemplate = Get-Content -Path $queryPath
$creds = Get-Secured -Username $siaUser -Loc $pwLoc
$conn = SQL-Connection -Server $dbSrv -Database $db

$response = Fetch-A2A -Type letter/ALL -Page 1 -Size $maxSize -Username $creds.UserName -Password $creds.Password -District $districtId
$pageTotal = Get-PageCount -RecordCount $response.letter_api.navigation.total_records -PageSize $maxSize
For ($curPage = 0; $curPage -lt ($pageTotal + 1); $curPage++) {

    "INFO: Processing page $curPage of $pageTotal" | Log-This
    $response = Fetch-A2A -Type letter/ALL -Page $curPage -Username $creds.UserName -Password $creds.Password -District $districtId
    $response.letter_api.letters | ForEach-Object {

        ## Check that Letter has been Printed.
        $status = $_.letter.status
        If (Check-LetterStatus($status)) {

            $invCode, $letterName = Get-LetterStrings($_.letter.letter)
            $dateString = Format-DateString($_.letter.letter_date)
            $tokenValues = @{
                STUDENT_ID = $_.letter.student.student_code
                STUDENT_GRADE = $_.letter.student.grade
                SCHOOL_ID = $_.letter.student.site
                LETTER_DATE = "'" +  $dateString + "'"
                INTERVENTION_TYPE = $invCode
                COMMENT = Format-CommentString -Letter $letterName -SentDate $dateString
            }

            ## Replace tokens in Query template with values.
            $query = $queryTemplate
            ForEach( $token in $tokenValues.GetEnumerator() ) {
                $pattern = "#{0}#" -f $token.key
                $query = $query -replace $pattern, $token.Value
            }

            ## Query Stored Procedure using token values.
            try {
                Query-SQL -Connection $conn -Query $query
            } catch {
                "ERROR: Unable to process query." | Log-This
                $query | Log-This
            }
        }

    }
}
$conn.Close()
"Sequence Complete." | Log-This
Purge-Logs -Path $logPath -DaysOld 356

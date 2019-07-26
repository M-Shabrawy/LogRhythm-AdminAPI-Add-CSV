Function InSecure
{
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3, [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12
}

Function Get-FileName($initialDirectory)
{  
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.Title = "Select Users file to import, file format it should be First,Middle,Last,Username"
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "Comm-Separated (*.csv)| *.csv"
    $OpenFileDialog.ShowDialog() | Out-Null
    $FileName = $OpenFileDialog.filename
    if($FileName -eq "")
    {
        exit 1
    }
    else
    {
        return $FileName
    }
}


Function Get-CSV($CSVFileName)
{
    try
    {
        $CSV = Import-Csv -Path $CSVFileName
        return $CSV
     }
     catch
     {
        Write-Error "Error Importing CSV"
        exit 1
     }
}

Function BuildJSON
{
    param(
        [string]$identifierValue,
        [ValidateSet("Login","Email")][string]$identifierType,
        [string]$AccountName,
        [string]$IAMName

    )
    
    $source = [pscustomobject]@{
        "AccountName" = "$AccountName"
        "IAMName" = "$IAMName"
    }

    $identifier = [pscustomobject]@{
        "identifierType" = "$identifierType"
        "value" = "$identifierValue"
        "recordStatus" = "New"
	    "source" = $source 
    }

    $JSON = ($identifier | ConvertTo-Json -Depth 5)
    #Write-Host $JSON
    return $JSON
}

Function WriteLog
{
    Param(
        [string]$Message,
        [string]$logFile
    )
    Try
    {
        Add-Content -Path $logFile -Value $Message -Force
    } 
    Catch {
        Write-Error $_.Exception.Message
    }
}


##Main
$token = Read-Host -Prompt "Please input API Token genrated from Client Console"

$PMHost = Read-Host -Prompt "Please input PM Host IP/Name (localhost) to keep default hit Enter"
if($PMHost -eq "")
{
    $apiUrl = "http://localhost:8505"
}
else
{
    $apiUrl = "https://" + $PMHost + ":8501"
    TrustAllCerts
}
#Get CSV file
write-host "Please select CSV file CSV, file format it should be Username,Identifier"
$CSVFileName = Get-FileName([System.IO.Directory]::GetCurrentDirectory())
#Read CSV file
$CSVDoc = Get-CSV($CSVFileName)
#Log file path
$logFilePath = [System.IO.Path]::GetDirectoryName($CSVFileName)+"\"+[System.IO.Path]::GetFileName($CSVFileName).Split('\.')[0]+".log" 

foreach ($Entry in $CSVDoc)
{
    $Identifier = $Entry.Identifier

    $IdentifierJSON = BuildJSON -identifierValue $Identifier -identifierType Login -AccountName ($CSVFileName.Split('\\'))[-1] -IAMName $Entry.Source
    
    $U = $Entry.Username
    #Get Identity 
    $idresult = Invoke-WebRequest -Uri $apiURL/lr-admin-api/identities/?identifier=$U -Headers @{"Authorization" = "Bearer $token"} -ContentType 'application/json' -Method Get -UseBasicParsing
    #Write-host $result
    $Identity = ConvertFrom-Json $idresult
    if ($Identity.Length -eq 0)
    {
        WriteLog -Message "User $U not found" -logFile $logFilePath
    }
    else
    {
        $identityID = $Identity.identityID
        Try
        {
            $result = Invoke-WebRequest -Uri $apiURL/lr-admin-api/identities/$identityID/identifiers/ -Headers @{"Authorization" = "Bearer $token"} -ContentType 'application/json' -Method Post -Body $IdentifierJSON
        }
        Catch
        {
            
        }
        Write-Host $result.StatusCode
        switch ($result.StatusCode) {
            "200" {$M = "User $U updated under Identity $identityID with Identifier $Identifier"}
            "404" {$M = 'Identity does not exist or is not visible to this User'}
            "409" {$M = "User $U Identifier $Identifier already exists for this Identity and cannot be added again"}
            default {$M = "Request Failed $result"}
        }
        WriteLog -Message $M -logFile $logFilePath
    }
}

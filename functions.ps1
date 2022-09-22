$Global:config = Get-Content .\config.json | ConvertFrom-Json

function Get-ApplicationAuthToken {
    Param(
        [Parameter(Mandatory = $true)]
        [pscredential]$Credential
    )

    $ApplicationInfo = $Credential.UserName -split "\\"
    $TenantName = $ApplicationInfo[0]
    $ApplicationID = $ApplicationInfo[1]
    $Secret = $Credential.GetNetworkCredential().Password

    $TokenEndpoint = "https://login.microsoftonline.com/$TenantName/oauth2/v2.0/token"

    $requestBody = @{
        client_id     = $ApplicationID
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $Secret
        grant_type    = "client_credentials"
    }

    $tokenRequest = Invoke-RestMethod -Uri $TokenEndpoint -Method Post -Body $requestBody

    if ($tokenRequest.access_token) {
        $authToken = @{
            'Content-Type'  = 'application/json'
            'Authorization' = "Bearer " + $tokenRequest.access_token
            'ExpiresOn'     = (Get-Date).AddSeconds($tokenRequest.expires_in).ToUniversalTime()
        }
        return $authToken
    }
    else {
        throw "Failed to get authToken"
    }
}

function Get-GraphData {
    Param (
        $uri,
        $authToken
    )
    $Response = (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get)
    $Output = $Response.Value
    $NextLink = $Response."@odata.nextLink"
    
    while ($NextLink -ne $null) {
        $Response = (Invoke-RestMethod -Uri $NextLink -Headers $authToken -Method Get)
        $NextLink = $Response."@odata.nextLink"
        $Output += $Response.Value
    }

    if ($Output -eq $null) {
        $Output = $Response
    }

    return $Output
}

function Get-3StepAuthToken {
    [cmdletbinding()]
    Param(
        [uri]$Endpoint,
        [pscredential]$Credential
    )

    $ClientID = $Credential.UserName
    $ClientSecret = $Credential.GetNetworkCredential().Password

    $Body = @{
        grant_type    = 'client_credentials'
        scope         = '3_Step_Platform'
        client_id     = $ClientID
        client_secret = $ClientSecret
    }

    $authResult = Invoke-RestMethod -Uri $Endpoint -Method Post -Body $Body

    if ($authResult.access_token) {
        $authHeader = @{
            'Content-Type'  = 'application/json'
            'Authorization' = "Bearer " + $authResult.access_token
        }
        return $authHeader
    }
    else {
        return $false
    }
}


function Get-3StepDevices {
    Param(
        [uri]$Endpoint,
        $authToken
    )
    $res = Invoke-RestMethod -Uri $Endpoint -Headers $authToken
    return $res.devices
}

function Set-3StepDeviceCostCenter {
    Param(
        [uri]$Endpoint,
        [string]$DeviceID,
        [string]$CostCenter,
        $authToken,
        [switch]$Use3StepDeviceID
    )
    if ($Use3StepDeviceID) {
        $idname = 'devicenumber'
    }
    else {
        $idname = 'serialnumber'
    }
    $Body = @{
        devices = @(
            @{
                $idname    = $DeviceID
                costcenter = $CostCenter
            }
        )
    }
    $jbody = $Body | ConvertTo-Json
    $res = Invoke-RestMethod -Uri $Endpoint -Headers $authToken -Body ([System.Text.Encoding]::UTF8.GetBytes($jbody)) -Method Put
    return $res
}

function Get-TeamMembers {
    param(
        $aadGroupID,
        $authToken
    )
    $users = Get-GraphData -uri "https://graph.microsoft.com/beta/groups/$aadGroupID/members?`$select=id,userPrincipalName" -authToken $authToken | Where-Object { $_."@odata.type" -eq "#microsoft.graph.user" }
    return $users
}
    
function Get-TeamOwners {
    param(
        $aadGroupID,
        $authToken
    )
    $owners = Get-GraphData -uri "https://graph.microsoft.com/beta/groups/$aadGroupID/owners?`$select=id,userPrincipalName" -authToken $authToken | Where-Object { $_."@odata.type" -eq "#microsoft.graph.user" }
    return $owners
}

function Add-TeamOwners {
    param (
        [string[]]$UPN,
        $groupId,
        $authToken
    )
    $AADObjID = @()
    foreach ($i in $UPN) {
        $AADObjID += Get-AADUserFromUPN -UPN $i -authToken $authToken -logFile $logFile | Select-Object id
    }
    foreach ($id in $AADObjID.id) {
        try {
            $body = @{"@odata.id" = "https://graph.microsoft.com/beta/directoryObjects/$id" } | ConvertTo-Json
            $result = Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/beta/groups/$groupId/owners/`$ref" -Body $body -Headers $authToken
            Write-Output $result
        }
        catch {
            throw "Failed to add owner: $id"
        }

    }
}

function Add-TeamMembers {
    param (
        [string[]]$UPN,
        $groupId,
        $authToken
    )
    $AADObjID = @()
    foreach ($i in $UPN) {
        $AADObjID += Get-AADUserFromUPN -UPN $i -authToken $authToken -logFile $logFile | Select-Object id
    }
    foreach ($id in $AADObjID.id) {
        try {
            $body = @{"@odata.id" = "https://graph.microsoft.com/beta/directoryObjects/$id" } | ConvertTo-Json
            $result = Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/beta/groups/$groupId/members/`$ref" -Body $body -Headers $authToken
            Write-Output $result
        }
        catch {
            throw "Failed to add member: $id"
        }
    }
}

function Remove-TeamOwners {
    param (
        [string[]]$AADObjID,
        $groupId,
        $authToken
    )
    foreach ($id in $AADObjID) {
        try {
            $result = Invoke-RestMethod -Method Delete -Uri "https://graph.microsoft.com/beta/groups/$groupId/owners/$id/`$ref" -Headers $authToken
            Write-Output $result
        }
        catch {
            throw "Failed to remove owner: $id"
        }
    }
}

function Remove-TeamMembers {
    param (
        [string[]]$AADObjID,
        $groupId,
        $authToken
    )
    foreach ($id in $AADObjID) {
        try {
            $result = Invoke-RestMethod -Method Delete -Uri "https://graph.microsoft.com/beta/groups/$groupId/members/$id/`$ref" -Headers $authToken
            Write-Output $result
        }
        catch {
            throw "Failed to remove member: $id"
        }
    }
}

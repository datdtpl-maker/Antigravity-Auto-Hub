# Setup-only discovery from the installed official helper. No bundled credentials,
# account switching, browser automation, or changes to Antigravity's token store.
function Get-InstalledOAuthClients {
    param([string]$LanguageServerPath)
    if (-not [IO.File]::Exists($LanguageServerPath)) { throw 'SetupAntigravityMissing' }
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $secrets=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $patterns=@('[0-9]{6,24}-[a-z0-9]{16,64}\.apps\.googleusercontent\.com','GOCSPX-[A-Za-z0-9_-]{28}')
    $sets=@($ids,$secrets)
    $lastEnd=@([long]-1,[long]-1)
    $stream=$null
    try {
        $stream=[IO.File]::OpenRead($LanguageServerPath)
        if ($stream.Length -gt 512MB) { throw 'SetupOAuthUnsupported' }
        $buffer=New-Object byte[] 1MB
        $carry=''; $position=[long]0
        while (($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $text=$carry+[Text.Encoding]::ASCII.GetString($buffer,0,$count)
            $offset=$position-$carry.Length
            for ($i=0; $i -lt $patterns.Count; $i++) {
                foreach ($match in [regex]::Matches($text,$patterns[$i])) {
                    $start=$offset+$match.Index
                    # The overlap can contain a suffix of an already seen ID.
                    if ($start -lt $lastEnd[$i]) { continue }
                    $null=$sets[$i].Add($match.Value)
                    $lastEnd[$i]=$start+$match.Length
                }
            }
            if ($ids.Count -gt 4 -or $secrets.Count -gt 4) { throw 'SetupOAuthUnsupported' }
            $carry=$text.Substring([Math]::Max(0,$text.Length-256))
            $position+=$count
        }
    } catch { throw 'SetupOAuthUnsupported' }
    finally { if ($stream) { $stream.Dispose() } }
    if (-not $ids.Count -or -not $secrets.Count) { throw 'SetupOAuthUnsupported' }
    return [pscustomobject]@{ClientIds=@($ids | Sort-Object); Secrets=@($secrets | Sort-Object)}
}

function Get-SetupRefreshToken {
    param([string]$FallbackPath)
    $raw=$null
    try { $raw=Get-StoredCredential } catch { }
    foreach ($source in @('Credential','File')) {
        try {
            if ($source -eq 'File') {
                if (-not [IO.File]::Exists($FallbackPath) -or (Get-Item -LiteralPath $FallbackPath).Length -gt 1MB) { continue }
                $raw=[IO.File]::ReadAllText($FallbackPath)
            }
            $parsed=$raw | ConvertFrom-Json -ErrorAction Stop
            $refresh=if($parsed.token.refresh_token){$parsed.token.refresh_token}else{$parsed.refresh_token}
            if ($refresh -is [string] -and $refresh.Length -gt 0) { return $refresh }
        } catch { }
    }
    throw 'SetupOAuthLoginRequired'
}

function Test-SetupOAuthCredential {
    param([pscredential]$Credential,[string]$RefreshToken)
    try {
        $response=Invoke-RestMethod -Uri 'https://oauth2.googleapis.com/token' -Method Post -Body @{
            client_id=$Credential.UserName; client_secret=$Credential.GetNetworkCredential().Password
            refresh_token=$RefreshToken; grant_type='refresh_token'
        } -TimeoutSec 10 -ErrorAction Stop
    } catch {
        # Never return provider descriptions, request bodies, tokens or secrets.
        $code=$null
        try { $code=($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop).error } catch { }
        if ($code -in @('invalid_client','invalid_grant','unauthorized_client')) { return $false }
        if ($code) { throw 'SetupOAuthRejected' }
        throw 'SetupOAuthNetwork'
    }
    if (-not $response.access_token -or $response.expires_in -le 0) { throw 'SetupOAuthInvalidResponse' }
    return $true
}

function Save-SetupOAuthCredential {
    param([pscredential]$Credential,[string]$Root)
    $path=Join-Path $Root 'oauth.local.clixml'
    $temp="$path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Credential | Export-Clixml -LiteralPath $temp -ErrorAction Stop
        $check=Import-Clixml -LiteralPath $temp -ErrorAction Stop
        if ($check.UserName -cne $Credential.UserName -or $check.GetNetworkCredential().Password -cne $Credential.GetNetworkCredential().Password) { throw 'ReadBackFailed' }
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp,$path,[NullString]::Value) }
        else { [IO.File]::Move($temp,$path) }
    } catch { throw 'SetupOAuthSaveFailed' }
    finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Initialize-HubOAuth {
    param([string]$Root,[string]$LanguageServerPath,[string]$FallbackPath)
    $refresh=Get-SetupRefreshToken $FallbackPath
    if ($env:ANTIGRAVITY_GOOGLE_CLIENT_ID -and $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET) {
        $credential=[pscredential]::new($env:ANTIGRAVITY_GOOGLE_CLIENT_ID,(ConvertTo-SecureString $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET -AsPlainText -Force))
        if (-not (Test-SetupOAuthCredential $credential $refresh)) { throw 'SetupOAuthEnvironmentInvalid' }
        Save-SetupOAuthCredential $credential $Root
        return [pscustomobject]@{Source='Environment'}
    }
    $credential=$null
    try { $credential=Import-Clixml -LiteralPath (Join-Path $Root 'oauth.local.clixml') -ErrorAction Stop } catch { }
    if ($credential -is [pscredential] -and $credential.UserName -and $credential.GetNetworkCredential().Password) {
        if (Test-SetupOAuthCredential $credential $refresh) { return [pscustomobject]@{Source='Local'} }
    }
    $clients=Get-InstalledOAuthClients $LanguageServerPath
    # A binary may include several OAuth clients. Accept only a successful refresh
    # of this user's local login, never the first string or an invalid_grant response.
    foreach ($id in $clients.ClientIds) {
        foreach ($secret in $clients.Secrets) {
            $credential=[pscredential]::new($id,(ConvertTo-SecureString $secret -AsPlainText -Force))
            if (Test-SetupOAuthCredential $credential $refresh) {
                Save-SetupOAuthCredential $credential $Root
                return [pscustomobject]@{Source='Installed'}
            }
        }
    }
    throw 'SetupOAuthNoMatch'
}

function Get-OAuthSetupFailureMessage {
    param([string]$Code)
    switch ($Code) {
        'SetupBusy' { 'Hub dang dang nhap hoac chuyen tai khoan. Cho thao tac ket thuc roi chay lai Setup-Install.bat.' }
        'SetupAntigravityMissing' { 'Chua tim thay Antigravity Desktop tai duong dan mac dinh. Cai Antigravity, dang nhap Google, roi chay lai Setup-Install.bat.' }
        'SetupAntigravityUnsupported' { 'Ban Antigravity nay chua vuot qua kiem tra tuong thich cua Hub. Cap nhat Hub/Antigravity roi thu lai.' }
        'SetupOAuthLoginRequired' { 'Hay mo Antigravity chinh thuc va dang nhap Google tren MAY NAY, sau do chay lai Setup-Install.bat. Khong can nhap client ID/secret.' }
        'SetupOAuthUnsupported' { 'Khong doc duoc cau hinh OAuth tu ban Antigravity nay. Cap nhat Hub/Antigravity; hoac dung Configure-OAuth.ps1 voi cau hinh tuong thich.' }
        'SetupOAuthNoMatch' { 'Khong xac minh duoc OAuth voi phien dang nhap hien tai. Dang nhap lai Antigravity chinh thuc roi chay lai Setup. Neu van loi, ban Antigravity nay co the chua duoc ho tro.' }
        'SetupOAuthEnvironmentInvalid' { 'Cap bien ANTIGRAVITY_GOOGLE_CLIENT_ID/SECRET dang ghi de cau hinh va khong hop le voi phien dang nhap. Sua hoac go ca hai bien, mo lai Setup.' }
        'SetupOAuthNetwork' { 'Khong ket noi duoc Google de xac minh OAuth. Kiem tra mang/proxy/firewall va chay lai Setup. Cau hinh cu duoc giu nguyen.' }
        'SetupOAuthRejected' { 'Google tu choi yeu cau xac minh OAuth. Kiem tra tai khoan trong Antigravity; neu bi gioi han yeu cau, doi roi chay lai Setup.' }
        'SetupOAuthInvalidResponse' { 'Google chua tra ve access token hop le. Thu lai sau; chua luu cau hinh moi.' }
        'SetupOAuthSaveFailed' { 'Khong luu duoc cau hinh OAuth. Kiem tra quyen ghi thu muc repo va dung cung nguoi dung Windows voi Antigravity.' }
        default { 'Cai dat chua hoan tat. Kiem tra quyen ghi thu muc repo, Windows Script Host va chay lai Setup-Install.bat.' }
    }
}

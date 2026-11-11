function Get-ModelSelectionKey {
    param([string]$Name)
    return (($Name -replace '[()]','' -replace '\s+',' ').Trim().ToLowerInvariant())
}

function Get-SelectedModelQuota {
    param($Account,[string]$SelectedModel)
    $unknown=[pscustomobject]@{Known=$false;Remaining=-1.0;Model=$SelectedModel}
    if(-not $SelectedModel -or $Account.ModelsStatus -ne 'Available' -or -not $Account.Email){return $unknown}
    $key=Get-ModelSelectionKey $SelectedModel
    $models=@($Account.ModelQuotas|Where-Object {(Get-ModelSelectionKey $_.Name) -eq $key})
    if(-not $models.Count -or @($models|Where-Object {$_.Status -ne 'Available' -or (ConvertTo-QuotaFraction $_.Remaining) -lt 0}).Count){return $unknown}
    $values=@($models|ForEach-Object {ConvertTo-QuotaFraction $_.Remaining})
    $family=$models[0].Family
    $groups=@($Account.QuotaGroups|Where-Object {
        if($family -in @('Opus','Sonnet','GptOss')){$_.Name -match '(?i)claude|gpt'}
        elseif($family -eq 'Argon'){$_.Name -match '(?i)argon'}
        elseif($family -eq 'Carbon'){$_.Name -match '(?i)carbon'}
        else{$_.Name -match '(?i)gemini' -and $_.Name -notmatch '(?i)argon|carbon'}
    })
    if(-not $Account.Success){return $unknown}
    foreach($group in $groups){$fraction=ConvertTo-QuotaFraction $group.Remaining;if($fraction -lt 0){return $unknown};$values+=$fraction}
    return [pscustomobject]@{Known=$true;Remaining=[double]($values|Measure-Object -Minimum).Minimum;Model=$SelectedModel}
}

function Get-ModelQuotaFamily {
    param([string]$Id,[string]$Name)
    $label="$Id $Name"
    if($label -match '(?i)\bargon\b|[-_]argon[-_]'){return 'Argon'}
    if($label -match '(?i)\bcarbon\b|[-_]carbon[-_]'){return 'Carbon'}
    if($label -match '(?i)claude.*opus'){return 'Opus'}
    if($label -match '(?i)claude.*sonnet'){return 'Sonnet'}
    if($label -match '(?i)gpt[- ]oss'){return 'GptOss'}
    if($label -match '(?i)gemini.*flash' -and $label -notmatch '(?i)lite|image'){return 'Flash'}
    return 'Other'
}

function ConvertTo-QuotaFraction {
    param($Value)
    $fraction=0.0
    if($null -ne $Value -and [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$fraction) -and
        -not [double]::IsNaN($fraction) -and $fraction -ge 0 -and $fraction -le 1){return $fraction}
    return -1.0
}

function ConvertTo-QuotaReset {
    param($Value)
    $reset=[datetimeoffset]::MinValue
    if($Value -and [datetimeoffset]::TryParse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$reset)){
        return $reset.UtcDateTime.ToString('o')
    }
    return ''
}

function Convert-ModelQuotaCatalog {
    param($Response)
    foreach($entry in $Response.models.PSObject.Properties){
        if($entry.MemberType -notin @('NoteProperty','Property')){continue}
        $model=$entry.Value
        $id=([string]$entry.Name -replace '[\x00-\x1f]',' ').Trim()
        $name=([string]$model.displayName -replace '[\x00-\x1f]',' ').Trim()
        if(-not $name){continue}
        if($id.Length -gt 160 -or $name.Length -gt 160){continue}
        $fraction=ConvertTo-QuotaFraction $model.quotaInfo.remainingFraction
        $status='Unknown'
        if($model.disabled -is [bool] -and $model.disabled){$status='Disabled';$fraction=-1.0}
        elseif($null -ne $model.disabled -and $model.disabled -isnot [bool]){$fraction=-1.0}
        elseif($fraction -ge 0){$status='Available'}
        [pscustomobject]@{Id=$id;Name=$name;Family=(Get-ModelQuotaFamily $id $name);Status=$status;Remaining=$fraction;ResetAt=(ConvertTo-QuotaReset $model.quotaInfo.resetTime)}
    }
}

function Convert-QuotaGroups {
    param($Response)
    foreach($group in $Response.groups){
        foreach($bucket in $group.buckets){
            $fraction=ConvertTo-QuotaFraction $bucket.remainingFraction
            [pscustomobject]@{Name=[string]$group.displayName;Window=[string]$bucket.window;Remaining=$fraction;ResetAt=(ConvertTo-QuotaReset $bucket.resetTime)}
        }
    }
}

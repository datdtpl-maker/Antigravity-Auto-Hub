param([int]$Width=1440,[int]$Height=920,[ValidateRange(0,100)][int]$AccountCount=0)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'AntigravityHub.ps1') -Preview -NoShow
if($AccountCount -gt 0){
    $original=@($script:HubAccounts)
    $script:HubAccounts=@(for($index=0;$index -lt $AccountCount;$index++){
        $row=$original[$index % $original.Count].PSObject.Copy()
        if($index -ge $original.Count){$row.AccountName='preview.account.{0:00}' -f ($index+1);$row.Email=$row.AccountName+'@example.test';$row.IsActive=$false;$row.StatusText=Get-HubText $row.StateKey}
        $row
    })
    $window.FindName('StatTotal').Text=[string]$script:HubAccounts.Count
    $window.FindName('StatReady').Text=[string]@($script:HubAccounts|Where-Object StateKey -eq Ready).Count
    $window.FindName('StatAttention').Text=[string]@($script:HubAccounts|Where-Object StateKey -ne Ready).Count
    Update-HubAccountView
}
$output=Join-Path $repo 'work\ui-preview'
New-Item -ItemType Directory -Path $output -Force | Out-Null
function Save-Preview([string]$Name) {
    Update-HubLayout $Height
    $window.Content.Measure([Windows.Size]::new($Width,$Height))
    $window.Content.Arrange([Windows.Rect]::new(0,0,$Width,$Height))
    $window.Content.UpdateLayout()
    $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $window.Content.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($Width,$Height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($window.Content)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $file=Join-Path $output ($Name+'.png')
    $stream=[IO.File]::Create($file)
    try{$encoder.Save($stream)}finally{$stream.Dispose()}
    Write-Output $file
}
try {
    Save-Preview 'accounts'
    $window.FindName('NavHistory').IsChecked=$true
    Save-Preview 'history'
    $window.FindName('NavAccounts').IsChecked=$true
    $window.FindName('SearchAccounts').Text='no-matching-account'
    Save-Preview 'no-results'
} finally {$window.Close()}

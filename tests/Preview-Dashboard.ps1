param([int]$Width=1220,[int]$Height=800)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'AntigravityHub.ps1') -Preview -NoShow
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

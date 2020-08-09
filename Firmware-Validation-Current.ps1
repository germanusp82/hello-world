#=====================================================================================================
# Description: This script takes the rack name as the prefix and the bmc domain as the prefixt to 
# generate the iDRAC hostname list. Then runs the racadm commands to list the firmware/software 
# inventory and extracts specific component firmware and lists it. This code applies to 14G Dell Servers
#=====================================================================================================

#======================================================
# Start of code
#======================================================


## Function to create the iDRAC Hostname file for 32 hosts with the Rack name as input
function getiDRACHostnames 
{
    [string]$prefix = Read-Host -Prompt "Enter the hostname prefix for the nodes without quotes Ex: 'prod-esx'"
    [string]$suffix = Read-Host -Prompt "Enter the hostname suffix for the nodes without quotes Ex: 'e.psgt.com' or 'l.upsgt.com''"
    [string]$prefix1 = $prefix+"-0"
    [string]$prefix2 = $prefix+"-"
    $i=0
    Clear-Content -Path .\idrac-hosts.txt
        for ($i=1;$i -le 9;$i++)
        {
            Add-Content -Path .\idrac-hosts.txt -Value $prefix1$i$suffix
        }
    for ($i=10;$i -le 32;$i++)
        {
            Add-Content -Path .\idrac-hosts.txt -Value $prefix2$i$suffix
        }
}
getiDRACHostnames

$iDRACList = Get-content idrac-hosts.txt

Write-Host '***************** iDRAC LifeCycle Version *****************'

foreach ($Hostname in $iDRACList)
{
    [string[]]$RawInfo = racadm -r $Hostname -u root -p VMwar3!! swinventory | select-string -Pattern 'ElementName = Integrated Remote Access Controller','Current Version' | select -Unique
    $i = [array]::IndexOf($RawInfo,'ElementName = Integrated Remote Access Controller')
    Write-Host $Hostname -ForegroundColor Cyan
    Write-Host $RawInfo[$i],$RawInfo[$i+1] -ForegroundColor Green
}

Write-Host '***************** BIOS Version *****************'

foreach ($Hostname in $iDRACList)
{
    [string[]]$RawInfo = racadm -r $Hostname -u root -p VMwar3!! swinventory | select-string -Pattern 'ElementName = BIOS','Current Version' | select -Unique
    $i = [array]::IndexOf($RawInfo,'ElementName = BIOS')
    Write-Host $Hostname -ForegroundColor Cyan
    Write-Host $RawInfo[$i],$RawInfo[$i+1] -ForegroundColor Green
}

Write-Host '***************** Dell HBA330 Mini Version *****************'

foreach ($Hostname in $iDRACList)
{
    [string[]]$RawInfo = racadm -r $Hostname -u root -p VMwar3!! swinventory | select-string -Pattern 'ElementName = Dell HBA330 Mini','Current Version' | select -Unique
    $i = [array]::IndexOf($RawInfo,'ElementName = Dell HBA330 Mini')
    Write-Host $Hostname -ForegroundColor Cyan
    Write-Host $RawInfo[$i],$RawInfo[$i+1] -ForegroundColor Green
}

Write-Host '***************** Mellanox Version *****************'

foreach ($Hostname in $iDRACList)
{
    [string[]]$TempRawInfo = racadm -r $Hostname -u root -p VMwar3!! swinventory | select-string -Pattern 'Mellanox ConnectX-4'
    [string]$SearchInfo = $TempRawInfo[0]
    [string[]]$RawInfo = racadm -r $Hostname -u root -p VMwar3!! swinventory | select-string -Pattern $SearchInfo,'Current Version' | select -Unique
    $i = [array]::IndexOf($RawInfo,$SearchInfo)
    Write-Host $Hostname -ForegroundColor Cyan
    Write-Host $RawInfo[$i],$RawInfo[$i+1] -ForegroundColor Green
}

Write-Host '***************** BOSS Firmware Version *****************'

foreach ($Hostname in $iDRACList)
{
    [string[]]$RawInfo = racadm -r $Hostname -u root -p VMwar3!! swinventory | select-string -Pattern 'ElementName = BOSS-S1','Current Version' | select -Unique
    $i = [array]::IndexOf($RawInfo,'ElementName = BOSS-S1')
    Write-Host $Hostname -ForegroundColor Cyan
    Write-Host $RawInfo[$i],$RawInfo[$i+1] -ForegroundColor Green
}

Write-Host '***************** BackPlane Firmware Version *****************'

foreach ($Hostname in $iDRACList)
{
    [string[]]$RawInfo = racadm -r $Hostname -u root -p VMwar3!! swinventory | select-string -Pattern "ElementName = BP14G\+EXP 0:1",'Current Version' | select -Unique
    $BackplaneInfo = $RawInfo | select-string -Pattern 'ElementName' -Context 0,1
    Write-Host $Hostname -ForegroundColor Cyan
    Write-Host $BackplaneInfo -ForegroundColor Green
}

#======================================================
# End of code
#======================================================

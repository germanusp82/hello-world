## *********************************Start of script**********************************
##Get theRack Name

[string]$RackName = Read-Host "Enter the Rack Name (Ex: dfw-psc4c02)"

##Get the vCenter fqdn or IP

[string]$vCName = Read-Host "Enter the FQDN or IP address of the vCenter"

## This part of the script will create the SVM Hostname list for 32 VMs with the Rack name as input

[string]$prefix1 = $RackName+"-0"
[string]$prefix2 = $RackName+"-"
[string[]]$SVMList = @()
$i=0
for ($i=1;$i -le 4;$i++)
    {
        $suffix = 'l-sio1'
        [string[]]$SVMList += $prefix1+$i+$suffix
    }
for ($i=5;$i -le 8;$i++)
    {
        $suffix = 'l-sio2'
       [string[]]$SVMList += $prefix1+$i+$suffix
    }

        $i=9
        $suffix = 'l-sio3'
        [string[]]$SVMList += $prefix1+$i+$suffix
    
for ($i=10;$i -le 12;$i++)
    {
        $suffix = 'l-sio3'
        [string[]]$SVMList += $prefix2+$i+$suffix
    }
for ($i=13;$i -le 16;$i++)
    {
        $suffix = 'l-sio4'
        [string[]]$SVMList += $prefix2+$i+$suffix
    }
for ($i=17;$i -le 20;$i++)
    {
        $suffix = 'l-sio5'
        [string[]]$SVMList += $prefix2+$i+$suffix
    }
for ($i=21;$i -le 24;$i++)
    {
        $suffix = 'l-sio6'
        [string[]]$SVMList += $prefix2+$i+$suffix
    }
for ($i=25;$i -le 28;$i++)
    {
        $suffix = 'l-sio7'
        [string[]]$SVMList += $prefix2+$i+$suffix
    }
for ($i=29;$i -le 32;$i++)
    {
        $suffix = 'l-sio8'
        [string[]]$SVMList += $prefix2+$i+$suffix
    }


#Get vCenter Credentials
$vCenterUname = "administrator@usaa.local"
$vCenterPwd = ConvertTo-SecureString -String "VMwar3!!" -AsPlainText -Force
$vCenterCred = new-object -typename System.Management.Automation.PSCredential -argumentlist $vCenterUname,$vCenterPwd

#Connect to the vCenter
Connect-VIServer -Server $vCName -Credential $vCenterCred

#Get FlexOS SVM Credentials
$SVMUName = "root"
$SVMPwd = ConvertTo-SecureString -String "VMwar3123" -AsPlainText -Force
$SVMCred = new-object -typename System.Management.Automation.PSCredential -argumentlist $SVMUName,$SVMPwd

#Get the list of Powered On ESXi Hosts:

$ESXiHost = get-vmhost | where-object {$_.Name -match $RackName -and $_.ConnectionState -match 'Connected'}

# This part of the script will clone a template SVM to every host in the ESXiHost List on the local datastore

for ($j=0;$j -lt $SVMList.count-1;$j++)
{
$HostName = $ESXiHost[$j]
$LocalDS = Get-vmhost | Where-object {$_.Name -match $HostName} | Get-Datastore | where-object {$_.Name -match 'local'} | Select-Object -Property Name
$FlexSVMName = $SVMList[$j]
Write-host 'Creating VM ' -ForegroundColor Green -NoNewline
Write-Host $SVMList[$j] -ForegroundColor Cyan
#New-VM -Name $FlexSVMName -VM $TemplateVMName -Datastore $LocalDS -VMHost $HostName
Write-Host $HostName ',' $LocalDS
}

# Power on one SVM at a time, SSHing and updating the Hostname and IP addresses and rebooting
##The below arrays get the input from the text files
##These txt files should be populated with the list of IPs and hostnames
$eth0_IPs = Get-Content .\eth0.txt
$eth1_IPs = Get-Content .\eth1.txt
$eth2_IPs = Get-Content .\eth2.txt

##Get user input for the Output file name and default IP and hostname on the template VM

[string]$default_eth0 = Read-Host -Prompt "Enter the default or template Mgmt IP address"
[string]$default_eth1 = Read-Host -Prompt "Enter the default or template Data1 IP address"
[string]$default_eth2 = Read-Host -Prompt "Enter the default or template Data2 IP address"
[string]$default_hostname = Read-Host -Prompt "Enter the default hostname"

##Generate the commands for all the hosts listed  in the input txt files
for ($k=0;$k -le 31; $k++)
    {
        ##power-on $SVMList[$k]
        
        $Hname = (("sed -i s/$default_hostname/"+$SVMList[$k]+'.usaa.com/')+" /etc/hostname")
        $Eth0 = (("sed -i s/$default_eth0/"+$eth0_IPs[$k]+'/')+" /etc/sysconfig/network-scripts/ifcfg-eth0")
        $Eth1 = (("sed -i s/$default_eth1/"+$eth1_IPs[$k]+'/')+" /etc/sysconfig/network-scripts/ifcfg-eth1")
        $Eth2 = (("sed -i s/$default_eth2/"+$eth2_IPs[$k]+'/')+" /etc/sysconfig/network-scripts/ifcfg-eth2")
        #$SessionID = New-SSHSession -ComputerName "$default_eth0" -Credential $SVMCred -AcceptKey

        Write-Host $SVMList[$k] -ForegroundColor Cyan
        Write-host $Hname -ForegroundColor Yellow
        Write-host $Eth0 -ForegroundColor Green
        Write-Host $Eth1 -ForegroundColor Green
        Write-Host $Eth2 -ForegroundColor Green

        #Invoke-SSHCommand -Command "$Hname" -SSHSession $SessionID
        #Invoke-SSHCommand -Command "$Eth0" -SSHSession $SessionID
        #Invoke-SSHCommand -Command "$Eth1" -SSHSession $SessionID
        #Invoke-SSHCommand -Command "$Eth2" -SSHSession $SessionID
        #Invoke-SSHCommand -Command 'reboot' -SSHSession $SessionID
        
    }
## **********************************End of script***********************************



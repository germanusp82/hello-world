## This PowerShell script is to protect a single VM/list of VMs under a single consistency group. 
## Naming: The script assigns Consistency Group names and copy names based on the VM Name or the App name
## the User provides as an input. 
## Source Journal Sizing: The source journal size will be min 10GB or max 10% of the sum all protected VMs' vmdks.
## Target Jorunal Sizing: The target journal size will be min 10GB and max 50GB of the sum all protected VMs' vmdks.
## Timing: The script takes approximately 2 minutes to protect each VM in the list. 
## This delay is due to waits introduced in the script and how long it takes for the REST calls to get a response
## AUTHOR: Tom Pinto
## Version 1.0 - Last Modified 8/10/2020

## The add-type routine below this line helps run the REST command without having to use SSL/TSL certificates
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    
    public class IDontCarePolicy : ICertificatePolicy {
        public IDontCarePolicy() {}
        public bool CheckValidationResult(
            ServicePoint sPoint, X509Certificate cert,
            WebRequest wRequest, int certProb) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = new-object IDontCarePolicy

## Import modules necessary to run powercli commands from powershell ISE

Import-module VMware.VimAutomation.Core
Import-module VMware.VimAutomation.Vds
Import-module VMware.VimAutomation.Cloud
Import-module VMware.VimAutomation.PCloud
Import-module VMware.VimAutomation.Cis.Core
Import-module VMware.VimAutomation.Storage
Import-module VMware.VimAutomation.HorizonView
Import-module VMware.VimAutomation.HA
Import-module VMware.VimAutomation.vROps
Import-module VMware.VumAutomation
Import-module VMware.DeployAutomation
Import-module VMware.ImageBuilder
Import-module VMware.VimAutomation.License

## Get the VM name or Application name and derive the Consistency Group name, Source Copy name and Target Copy name

$VMNameAppName = Read-Host ("If protecting a single VM, type VM Name or if protecting multiple VMs type the application/group name")
$CGName = $VMNameAppName + "_CG"
$TgtCopyName = $VMNameAppName + "_Tgt"
$SrcCopyName = $VMNameAppName + "_Src"
#$SrcRPClusterName = Read-Host ("Enter the Source vRPA Cluster name")
#$SrcDomainName = Read-Host ("Enter the Source Domain Name")
#$TgtRPClusterName = Read-Host ("Enter the Target vRPA Cluster name")
#$TgtDomainName = Read-Host ("Enter the Target Domain Name")
$SrcRPClusterName= "vrpa-src-cl"
$SrcDomainName = "somedomain.com"
$SrcRPClusterFQDN = $SrcRPClusterName + "." + $SrcDomainName 
$TgtRPClusterName= "vrpa-tgt-cl"
$TgtDomainName = "somedomain.com"
$TgtRPClusterFQDN = $TgtRPClusterName + "." + $TgtDomainName 
#$TgtESXiHostName = Read-Host ("Enter the Target ESXi Host's name as it appears on the vCenter")
$InputVMList = Read-Host -Prompt "Enter the path to the file containing the List of VMs to be protected (please include the file name in the path)"
$VMsList = get-content $InputVMList
if ($VMsList.Count -eq 1)
    {
    $FirstVMtoProtect = $VMsList
    }
Else
    {
    $FirstVMtoProtect = $VMsList[0]
    }


$vCenterCred = Get-Credential


#Write-Host ($CGName,$TgtCopyName,$SrcCopyName,$FirstVMtoProtect)

## Getting the Source and the target vRPA cluster UIDs

$SrcRPClusterUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/ -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | ConvertTo-Json -Depth 4 | ConvertFrom-Json | `
Select-Object -Expand clustersInformation | Where-Object -Property clusterName -Match $SrcRPClusterName | Select-Object -ExpandProperty clusterUID | Select-Object -ExpandProperty id | `
Format-Table -AutoSize | Out-String -Stream

$TgtRPClusterUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/ -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | ConvertTo-Json -Depth 4 | ConvertFrom-Json | `
Select-Object -Expand clustersInformation | Where-Object -Property clusterName -Match $TgtRPClusterName | Select-Object -ExpandProperty clusterUID | Select-Object -ExpandProperty id | `
Format-Table -AutoSize | Out-String -Stream


## Getting the Source and the target vCenter UIDs

$SrcVCenterUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$SrcRPClusterUID/virtual_infra_configuration -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 4 | ConvertFrom-Json | Select-Object -Expand virtualCentersConfiguration | Select-Object -ExpandProperty virtualCenterUID | Select-Object -ExpandProperty uuid | `
Format-Table -AutoSize | Out-String -Stream

$TgtVCenterUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$TgtRPClusterUID/virtual_infra_configuration -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 4 | ConvertFrom-Json | Select-Object -Expand virtualCentersConfiguration | Select-Object -ExpandProperty virtualCenterUID | Select-Object -ExpandProperty uuid | `
Format-Table -AutoSize | Out-String -Stream


## vCenter names to confirm the correct source and target

$SrcvCenterName = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$SrcRPClusterUID/virtual_infra_configuration -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 4 | ConvertFrom-Json | Select-Object -Expand virtualCentersConfiguration | Select-Object -ExpandProperty name | Format-Table -AutoSize | Out-String -Stream

$TgtvCenterName = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$TgtRPClusterUID/virtual_infra_configuration -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 4 | ConvertFrom-Json | Select-Object -Expand virtualCentersConfiguration | Select-Object -ExpandProperty name | Format-Table -AutoSize | Out-String -Stream

Connect-VIServer -Server $SrcvCenterName -Credential $vCenterCred
Connect-VIServer -Server $TgtvCenterName -Credential $vCenterCred


## ## Getting the least used DataStore on the Source side which will be used for source journal volumes
$AvailableSrcJrnlDS = Get-Datastore -Server $SrcvCenterName | where { (Get-TagAssignment -Entity $_ | Select -ExpandProperty Tag) -match 'RP4VM_Jrnl' } | Sort-Object -Descending -Property FreeSpaceGB | Select-Object -ExpandProperty Name
$SrcJrnlDSName = $AvailableSrcJrnlDS[0]

## Getting the least used DataStore on the target side which will be used to deploy the copy VM
$AvailableTgtDS = Get-Datastore -Server $TgtvCenterName | where { (Get-TagAssignment -Entity $_ | Select -ExpandProperty Tag) -match 'RP4VM_Tgt' } | Sort-Object -Descending -Property FreeSpaceGB | Select-Object -ExpandProperty Name
$TgtDatastoretName = $AvailableTgtDS[0]

## Getting the least used DataStore on the target side which will be used for target journal volumes

$AvailableTgtJrnlDS = Get-Datastore -Server $TgtvCenterName | where { (Get-TagAssignment -Entity $_ | Select -ExpandProperty Tag) -match 'RP4VM_Jrnl' } | Sort-Object -Descending -Property FreeSpaceGB | Select-Object -ExpandProperty Name
$TgtJrnlDSName = $AvailableTgtJrnlDS[0]

## Getting the Target ESXi host for the copy VM

$clusters = get-cluster -Server $TgtvCenterName
$myClusters = @()
foreach ($cluster in $clusters) 
    {
    $hosts = $cluster | get-vmhost -Server $TgtvCenterName
    }
$SortHost = $hosts | Sort-Object -Property CpuUsageMhz | Sort-Object -Property MemoryUsageGB
$TgtESXiHostName = $SortHost[0] | Select-Object -ExpandProperty Name

## Get the target ESXi Host UID

$TgtESXUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$TgtRPClusterUID/virtual_infra_configuration -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 12 | ConvertFrom-Json | Select-Object -Expand virtualCentersConfiguration | Select-Object -ExpandProperty datacentersConfiguration | Select-Object -ExpandProperty esxClustersConfiguration |`
Select-Object -ExpandProperty esxsConfiguration | Where-Object -Property name -Match $TgtESXiHostName | Select-Object -ExpandProperty esxUID | Select-Object -ExpandProperty uuid | `
Format-Table -AutoSize | Out-String -Stream

## Get the target Datastore UID

$TgtDatastoreUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$TgtRPClusterUID/virtual_infra_configuration -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 12 | ConvertFrom-Json | Select-Object -Expand virtualCentersConfiguration | Select-Object -ExpandProperty datacentersConfiguration | Select-Object -ExpandProperty datastoresConfiguration | `
Where-Object -Property name -Match $TgtDatastoretName | Select-Object -ExpandProperty datastoreUID | Select-Object -ExpandProperty uuid | Format-Table -AutoSize | Out-String -Stream

## Source VM's (VM to be protected) UUID

## First we look up the ESXi cluster name using PowerCLI and this name will later be used to look up the VM UID

$VMHostCluster = Get-Cluster -VM $FirstVMtoProtect -Server $SrcvCenterName | Select Name | Select-Object -ExpandProperty Name | Format-Table -AutoSize | Out-String -Stream


## Getting the ESXi Cluster UID of the ESXi cluster on which the source VM resides

$SrcESXiClusterUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$SrcRPClusterUID/virtual_infra_configuration -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 12 | ConvertFrom-Json | Select-Object -Expand virtualCentersConfiguration | Select-Object -ExpandProperty datacentersConfiguration | Select-Object -ExpandProperty esxClustersConfiguration | `
Where-Object -Property name -Match $VMHostCluster | Select-Object -ExpandProperty esxClusterUID | Select-Object -ExpandProperty uuid | Format-Table -AutoSize | Out-String -Stream


## Getting the source VM's UUID

$SrcVirtualMachineUID = `
Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$SrcRPClusterUID/vcenter_servers/$SrcVCenterUID/datacenter-2/$SrcESXiClusterUID/available_vms_for_replication `
-Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | ConvertTo-Json -Depth 12 | ConvertFrom-Json | Select-Object -Expand innerSet | `
Where-Object -Property name -Match $FirstVMtoProtect | Select-Object -ExpandProperty vmUID | Select-Object -ExpandProperty uuid | Format-Table -AutoSize | Out-String -Stream

## Source Virtual Machines total disk size


## Get the VM's total Disk size and comput the Source and Target journal capacity
[double]$MinJrnlSize = 10737418240
[double]$SrcMaxJrnlSize = 53687091200
[decimal]$TotalDiskSize = 0

foreach ($vMachine in $VMsList)
{
$VMDiskSize = Get-HardDisk -VM $vMachine -Server $SrcvCenterName | Measure-Object -Sum CapacityGB | `
Select-Object -ExpandProperty Sum | Format-Table -AutoSize | Out-String -Stream
[decimal]$VMSize = [int]$VMDiskSize
$TotalDiskSize += $VMSize
}
[decimal]$SrcJrnlSize = ($TotalDiskSize*.10)*1024*1024*1024
[decimal]$TgtJrnlSize = ($TotalDiskSize*.20)*1024*1024*1024
if ($SrcJrnlSize -lt 10737418240)
    {
    $SrcJournalSize = $MinJrnlSize
    }
Elseif ($SrcJrnlSize -gt 53687091200)
    {
    $SrcJournalSize = $SrcMaxJrnlSize
    }
Else
    {
    $SrcJournalSize = [math]::Truncate($SrcJrnlSize)
    }
if ($TgtJrnlSize -lt 10737418240)
    {
    $TgtJournalSize = $MinJrnlSize
    }
Else
    {
    $TgtJournalSize = [math]::Truncate($TgtJrnlSize)
    }

## Getting the Source and Target vCenter Array UID, Resource

$SrcResourcePoolUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/system/settings -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 15 | ConvertFrom-Json | Select-Object -Expand clustersSettings | Where-Object -Property clusterName -Match $SrcRPClusterName | `
Select-Object -ExpandProperty ampsSettings | Select-Object -ExpandProperty managedArrays | Select-Object -ExpandProperty resourcePools | `
Where-Object -Property name -Match $SrcJrnlDSName | Select-Object -ExpandProperty resourcePoolUID | Select-Object -ExpandProperty uuid |  `
Format-Table -AutoSize | Out-String -Stream

$SrcStorageResourcePoolUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/system/settings -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 15 | ConvertFrom-Json | Select-Object -Expand clustersSettings | Where-Object -Property clusterName -Match $SrcRPClusterName | `
Select-Object -ExpandProperty ampsSettings | Select-Object -ExpandProperty managedArrays | Select-Object -ExpandProperty resourcePools | `
Where-Object -Property name -Match $SrcJrnlDSName | Select-Object -ExpandProperty resourcePoolUID | Select-Object -ExpandProperty storageResourcePoolId |  `
Format-Table -AutoSize | Out-String -Stream

$SrcArrayUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/system/settings -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 15 | ConvertFrom-Json | Select-Object -Expand clustersSettings | Where-Object -Property clusterName -Match $SrcRPClusterName | `
Select-Object -ExpandProperty ampsSettings | Select-Object -ExpandProperty managedArrays | Select-Object -ExpandProperty resourcePools | `
Where-Object -Property name -Match $SrcJrnlDSName | Select-Object -ExpandProperty resourcePoolUID | Select-Object -ExpandProperty arrayUid | `
Select-Object -ExpandProperty id | Format-Table -AutoSize | Out-String -Stream

$TgtResourcePoolUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/system/settings -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 15 | ConvertFrom-Json | Select-Object -Expand clustersSettings | Where-Object -Property clusterName -Match $TgtRPClusterName | `
Select-Object -ExpandProperty ampsSettings | Select-Object -ExpandProperty managedArrays | Select-Object -ExpandProperty resourcePools | `
Where-Object -Property name -Match $TgtJrnlDSName | Select-Object -ExpandProperty resourcePoolUID | Select-Object -ExpandProperty uuid |  `
Format-Table -AutoSize | Out-String -Stream

$TgtStorageResourcePoolUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/system/settings -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 15 | ConvertFrom-Json | Select-Object -Expand clustersSettings | Where-Object -Property clusterName -Match $TgtRPClusterName | `
Select-Object -ExpandProperty ampsSettings | Select-Object -ExpandProperty managedArrays | Select-Object -ExpandProperty resourcePools | `
Where-Object -Property name -Match $TgtJrnlDSName | Select-Object -ExpandProperty resourcePoolUID | Select-Object -ExpandProperty storageResourcePoolId |  `
Format-Table -AutoSize | Out-String -Stream

$TgtArrayUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/system/settings -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 15 | ConvertFrom-Json | Select-Object -Expand clustersSettings | Where-Object -Property clusterName -Match $TgtRPClusterName | `
Select-Object -ExpandProperty ampsSettings | Select-Object -ExpandProperty managedArrays | Select-Object -ExpandProperty resourcePools | `
Where-Object -Property name -Match $TgtJrnlDSName | Select-Object -ExpandProperty resourcePoolUID | Select-Object -ExpandProperty arrayUid | `
Select-Object -ExpandProperty id | Format-Table -AutoSize | Out-String -Stream

## Generating the JSON payload to protect a single VM using a consistency group. All the values derived above wil be substitued in the JSON payload below

$JsonReplicatePayload='{
     "cgName": "'+$CGName+'",
     "productionCopy": {
          "clusterUID": {
               "id": '+$SrcRPClusterUID+'
          },
          "copyUID": 0
     },
     "vmReplicationSets":
     [{
               "replicationSetVms":
               [{
                         "copyUID": {
                              "clusterUID": {
                                   "id": '+$TgtRPClusterUID+'
                              },
                              "copyUID": 1
                         },
                         "vmParam": {
                              "JsonSubType": "CreateVMParam",
                              "targetVirtualCenterUID": {
                                   "uuid": "'+$TgtVCenterUID+'"
                              },
                              "targetResourcePlacementParam": {
                                   "JsonSubType": "CreateTargetVMManualResourcePlacementParam",
                                   "targetEsxUID": {
                                        "uuid": "'+$TgtESXUID+'"
                                   }
                              },
                              "targetDatastoreUID": {
                                   "uuid": "'+$TgtDatastoreUID+'"
                              }
                         }
                    }, {
                         "copyUID": {
                              "clusterUID": {
                                   "id": '+$SrcRPClusterUID+'
                              },
                              "copyUID": 0
                         },
                         "vmParam": {
                              "JsonSubType": "ExistingVMParam",
                              "vmUID": {
                                   "uuid": "'+$SrcVirtualMachineUID+'",
                                   "virtualCenterUID": {
                                        "uuid": "'+$SrcVCenterUID+'"
                                   }
                              }
                         }
                    }
               ],
               "virtualHardwareReplicationPolicy": {
                    "provisionPolicy": "SAME_AS_SOURCE",
                    "hwChangesPolicy": "REPLICATE_HW_CHANGES"
               },
               "virtualDisksReplicationPolicy": {
                    "autoReplicateNewVirtualDisks": "true"
                   
               }
          }
     ],
     "links":
     [{
               "linkPolicy": {
                    "JsonSubType": "ConsistencyGroupLinkPolicy",
                    "protectionPolicy": {
                         "protectionType": "ASYNCHRONOUS",
                         "syncReplicationLatencyThresholds": {
                              "resumeSyncReplicationBelow": {
                                   "value": 3000,
                                   "type": "MICROSECONDS"
                              },
                              "startAsyncReplicationAbove": {
                                   "value": 5000,
                                   "type": "MICROSECONDS"
                              },
                              "thresholdEnabled": "true"
                         },
                         "syncReplicationThroughputThresholds": {
                              "resumeSyncReplicationBelow": {
                                   "value": 35000,
                                   "type": "KB"
                              },
                              "startAsyncReplicationAbove": {
                                   "value": 45000,
                                   "type": "KB"
                              },
                              "thresholdEnabled": "false"
                         },
                         "rpoPolicy": {
                              "allowRegulation": "false",
                              "maximumAllowedLag": {
                                   "value": 25,
                                   "type": "SECONDS"
                              },
                              "minimizationType": "IRRELEVANT"
                         },
                         "replicatingOverWAN": "true",
                         "compression": "LOW",
                         "bandwidthLimit": "0.0",
                         "measureLagToTargetRPA": "true",
                         "deduplication": "true",
                         "weight": 1
                    },
                    "advancedPolicy": {
                         "snapshotGranularity": "DYNAMIC",
                         "performLongInitialization": "true"
                    },
                    "snapshotShippingPolicy": null
               },
               "linkUID": {
                    "groupUID": {
                         "id": 0
                    },
                    "firstCopy": {
                         "clusterUID": {
                              "id": '+$SrcRPClusterUID+'
                         },
                         "copyUID": 0
                    },
                    "secondCopy": {
                         "clusterUID": {
                              "id": '+$TgtRPClusterUID+'
                         },
                         "copyUID": 1
                    }
               }
          }
     ],
     "copies":
     [{
               "copyUID": {
                    "clusterUID": {
                         "id": '+$TgtRPClusterUID+'
                    },
                    "copyUID": 1
               },
               "copyName": "'+$TgtCopyName+'",
               "JsonSubType": "ConsistencyGroupCopyParam",
               "volumeCreationParams": {
                    "volumeParams":
                    [{
                              "JsonSubType": "VolumeCreationParams",
                              "volumeSize": {
                                   "sizeInBytes": '+$TgtJournalSize+'
                              },
                              "arrayUid": {
                                   "id": '+$TgtArrayUID+',
                                   "clusterUID": {
                                        "id": '+$TgtRPClusterUID+'
                                   }
                              },
                              "poolUid": {
                                   "uuid": '+$TgtResourcePoolUID+',
                                   "storageResourcePoolId": "'+$TgtStorageResourcePoolUID+'",
                                   "arrayUid": {
                                        "id": '+$TgtArrayUID+',
                                        "clusterUID": {
											"id": '+$TgtRPClusterUID+'
                                        }
                                   }
                              },
                              "tieringPolicy": null,
                              "resourcePoolType": "VC_DATASTORE"
                         }
                    ]
               }
          }, {
               "copyUID": {
                    "clusterUID": {
                         "id": '+$SrcRPClusterUID+'
                    },
                    "copyUID": 0
               },
               "copyName": "'+$SrcCopyName+'",
               "JsonSubType": "ConsistencyGroupCopyParam",
               "volumeCreationParams": {
                    "volumeParams":
                    [{
                              "JsonSubType": "VolumeCreationParams",
                              "volumeSize": {
                                   "sizeInBytes": '+$SrcJournalSize+'
                              },
                              "arrayUid": {
                                   "id": '+$SrcArrayUID+',
                                   "clusterUID": {
                                        "id": '+$SrcRPClusterUID+'
                                   }
                              },
                              "poolUid": {
                                   "uuid": '+$SrcResourcePoolUID+',
                                   "storageResourcePoolId": "'+$SrcStorageResourcePoolUID+'",
                                   "arrayUid": {
                                        "id": '+$SrcArrayUID+',
                                        "clusterUID": {
											"id": '+$SrcRPClusterUID+'
                                        }
                                   }
                              },
                              "tieringPolicy": null,
                              "resourcePoolType": "VC_DATASTORE"
                         }
                    ]
               }
          }
     ],
     "startTransfer": true,
     "JsonSubType":  "ReplicateVmsParam"
}'

## The below REST POST call be used to create the Consistency Group. The response will be a new Consistey Group ID

$RESTurl= "https://$SrcRPClusterFQDN/fapi/rest/5_1/groups/virtual_machines/replicate"

$NewGroupID = Invoke-RestMethod -Uri $RESTurl -Body $JsonReplicatePayload -ContentType application/json `
-Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="}  -Method Post | Select-Object -ExpandProperty id |Format-Table -AutoSize | Out-String -Stream

## The below REST GET call is used to retrieve the Group Name with the new Group ID generated in the above step

$GroupNameString=Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/groups/$NewGroupID/name -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | ConvertTo-Json | ConvertFrom-Json
$GroupName=$GroupNameString | Select-Object -ExpandProperty string

## Output: All the details of the newly created Consistency Group will be written to the screen

Write-Host "****************** Results of CG Creation ******************"
Write-Host "New CG ID: $NewGroupID"
Write-Host "New CG Name: $GroupName"
Write-Host "First Protected VM: $FirstVMtoProtect"
Write-Host "Source Journal Size: $SrcJournalSize B"
Write-Host "Datastore used for Source Journal space: $SrcJrnlDSName"
Write-Host "Target Journal Size: $TgtJournalSize B"
Write-Host "Datastore used for Target Journal space: $TgtJrnlDSName"
Write-Host "Target Host for Copy VM: $TgtESXiHostName"
Write-Host "Target Datastore for Copy VM: $TgtDatastoretName"
Write-Host "******************** End of CG Creation ********************"

Write-Host "Sleeping for 20 seconds....."

Start-Sleep -s 20

## Protecting additional VMs in the list ##

if ($VMsList.Count -ge 2)
    {
    foreach ($AddnlVM in $VMsList[1..($VMsList.Length-1)])
        {
        ## Getting addtional Source VM's UUID (These are the VMs to be protected int he same CG) 

        ## First we look up the ESXi cluster name using PowerCLI and this name will later be used to look up the VM UID

        $AddnlVMHostCluster = Get-Cluster -VM $AddnlVM -Server $SrcvCenterName | Select Name | Select-Object -ExpandProperty Name | Format-Table -AutoSize | Out-String -Stream
                
        ## Getting the ESXi Cluster UID of the ESXi cluster on which the source VM resides
        
        $AddnlSrcESXiClusterUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$SrcRPClusterUID/virtual_infra_configuration -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
        ConvertTo-Json -Depth 12 | ConvertFrom-Json | Select-Object -Expand virtualCentersConfiguration | Select-Object -ExpandProperty datacentersConfiguration | Select-Object -ExpandProperty esxClustersConfiguration | `
        Where-Object -Property name -Match $AddnlVMHostCluster | Select-Object -ExpandProperty esxClusterUID | Select-Object -ExpandProperty uuid | Format-Table -AutoSize | Out-String -Stream


        ## Getting the source VM's UUID

        $AddnlSrcVMUID = `
        Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$SrcRPClusterUID/vcenter_servers/$SrcVCenterUID/datacenter-2/$AddnlSrcESXiClusterUID/available_vms_for_replication `
        -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | ConvertTo-Json -Depth 12 | ConvertFrom-Json | Select-Object -Expand innerSet | `
        Where-Object -Property name -Match $AddnlVM | Select-Object -ExpandProperty vmUID | Select-Object -ExpandProperty uuid | Format-Table -AutoSize | Out-String -Stream

        ## Getting the Target ESXi host for the copy VM

        $Addnlclusters = get-cluster -Server $TgtvCenterName
        $AddnlmyClusters = @()
        foreach ($cluster in $Addnlclusters) 
            {
            $Addnlhosts = $cluster | get-vmhost -Server $TgtvCenterName
            }
        $AddnlSortHost = $Addnlhosts | Sort-Object -Property CpuUsageMhz | Sort-Object -Property MemoryUsageGB
        $AddnlTgtESXiHostName = $AddnlSortHost[0] | Select-Object -ExpandProperty Name

        $AddnlTgtESXUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$TgtRPClusterUID/virtual_infra_configuration -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
        ConvertTo-Json -Depth 12 | ConvertFrom-Json | Select-Object -Expand virtualCentersConfiguration | Select-Object -ExpandProperty datacentersConfiguration | Select-Object -ExpandProperty esxClustersConfiguration |`
        Select-Object -ExpandProperty esxsConfiguration | Where-Object -Property name -Match $AddnlTgtESXiHostName | Select-Object -ExpandProperty esxUID | Select-Object -ExpandProperty uuid | `
        Format-Table -AutoSize | Out-String -Stream

        ## Getting the least used DataStore on the target side which will be used to deploy the Copy VMs
        $AddnlAvailableTgtDS = Get-Datastore -Server $TgtvCenterName | where { (Get-TagAssignment -Entity $_ | Select -ExpandProperty Tag) -match 'RP4VM_Tgt' } | Sort-Object -Descending -Property FreeSpaceGB | Select-Object -ExpandProperty Name
        $AddnlTgtDatastoretName = $AddnlAvailableTgtDS[0]

        $AddnlTgtDatastoreUID = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/clusters/$TgtRPClusterUID/virtual_infra_configuration -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
        ConvertTo-Json -Depth 12 | ConvertFrom-Json | Select-Object -Expand virtualCentersConfiguration | Select-Object -ExpandProperty datacentersConfiguration | Select-Object -ExpandProperty datastoresConfiguration | `
        Where-Object -Property name -Match $AddnlTgtDatastoretName | Select-Object -ExpandProperty datastoreUID | Select-Object -ExpandProperty uuid | Format-Table -AutoSize | Out-String -Stream

        ## The below payload will be used to protect additiona VMs in the initial list after the above values are substituted for each VM

        $JsonPayloadAddVMs='{
                            "innerSet": [
                                {
                                    "replicationSetVms": [
                                        {
                                            "copyUID": {
                                                "clusterUID": {
                                                    "id": '+$SrcRPClusterUID+'
                                                },
                                                "copyUID": 0
                                            },
                                            "vmParam": {
                                                "JsonSubType": "SourceVmParam",
                                                "vmUID": {
                                                    "uuid": "'+$AddnlSrcVMUID+'",
                                                    "virtualCenterUID": {
                                                        "uuid": "'+$SrcVCenterUID+'"
                                                    }
                                                },
                                                "clusterUID": {
                                                    "id": '+$SrcRPClusterUID+'
                                                }
                                            }
                                        },
                                        {
                                            "copyUID": {
                                                "clusterUID": {
                                                    "id": '+$TgtRPClusterUID+'
                                                },
                                                "copyUID": 1
                                            },
                                            "vmParam": {
                                                "JsonSubType": "CreateVMParam",
                                                "targetVirtualCenterUID": {
                                                    "uuid": "'+$TgtVCenterUID+'"
                                                },
                                                "targetResourcePlacementParam": {
                                                    "JsonSubType": "CreateTargetVMManualResourcePlacementParam",
                                                    "targetEsxUID": {
                                                        "uuid": "'+$AddnlTgtESXUID+'"
                                                    }
                                                },
                                                "targetDatastoreUID": {
                                                    "uuid": "'+$AddnlTgtDatastoreUID+'"
                                                }
                                            }
                                        }
                                    ],
                                    "virtualHardwareReplicationPolicy": {
                                        "provisionPolicy": "SAME_AS_SOURCE",
                                        "hwChangesPolicy": "REPLICATE_HW_CHANGES"
                                    },
                                    "virtualDisksReplicationPolicy": {
                                        "autoReplicateNewVirtualDisks": true,
                                        "diskSettings": null
                                    }
                                }
                            ]
                        }'

        ## REST URL and REST POST call to protect additional VMs that were provided in the intial list
        
        $AddVMRestURL= "https://$SrcRPClusterFQDN/fapi/rest/5_1/groups/$NewGroupID/virtual_machines"

        Invoke-RestMethod -Method Post -Uri $AddVMRestURL -Body $JsonPayloadAddVMs -ContentType application/json -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="}

        Write-Host "***** Protection Result *****"
        Write-Host "Protected VM: $AddnlVM"
        Write-Host "Target Host: $AddnlTgtESXiHostName"
        Write-Host "Target Datastore: $AddnlTgtDatastoretName"
        Write-Host "******* End of Result *******"
        Write-Host "Sleeping for 20 seconds....."

        Start-Sleep -s 20

        }
    }

if ($VMsList.Count -eq 1)
    {
    Write-Host "There are no additional VMs to be protected. Please wait 30 seconds to see the only VM protected under CG ID $NewGroupID ...."
    Start-Sleep -s 30
    }
Else
    {
    Write-Host "Additional VMs have been protected successfully. Please wait 2 mins to see the list of hosts protected under CG ID $NewGroupID ...."
    Start-Sleep -s 120
    }


## REST GET call to list the additional VMs that were protected in the CG

$AddnlVMsProtected = Invoke-RestMethod -Uri https://$SrcRPClusterFQDN/fapi/rest/5_1/groups/$NewGroupID/information -Headers @{"AUTHORIZATION"="Basic YWRtaW46YWRtaW4="} -Method Get | `
ConvertTo-Json -Depth 8 | ConvertFrom-Json | Select-Object -Expand groupCopiesInformation | Where-Object -Property role -Match "ACTIVE" | Select-Object -ExpandProperty vmsInformation | `
Select-Object -ExpandProperty vmName | Format-Table -AutoSize | Out-String -Stream

Write-Host "***** End Result *****"
Write-Host "All VMs in the CG are:" 
$AddnlVMsProtected
Write-Host "If you are not seeing all VMs that are supposed to be part of the CG, it is possible that the copy VMs are still getting created"
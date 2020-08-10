# Contents of hello-world repo
Have started automating a few tasks. This is what each script can do.

Firmware-Validation-Current.ps1 :
This powershell script can be used to validate the version of certain firmware. This will work only for Dell PowerEdge 14G servers. It takes the server idrac hostnames or ip address as the input and runs rackadm commands against each server to get the firmware version and displays the version of each firware for all the hosts

HCI_SVM_Deployment.ps1:
This powershell script deploys FlexOS Storage Virtual Machines (SVMs) using a template on every host in a single ESXi cluster. Can be used when deploying FlexOS clusters manually.

Replicate_Multiple_VMs.ps1:
Recoverpoint for VMs (RP4VM) is a Disastery Recovery solution for virtual machines from Dell EMC. This powershell script takes the list of VMs as an input and protects each VM in its own Consistency group (CG). The script needs to be modified in order to protect multiple VMs in the same CG. Will require a different payload for the REST Call. The script also uses fixed percentage of the VM size for the journal space at the source and target. This needs to be modified based on the business needs/protection window needed. There are other details that need to be updated in the script. The source/target domain names, vRPA cluster and vCenter names and the vCenter credentials.

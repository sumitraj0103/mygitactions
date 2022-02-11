# Upload a notebook to Azure Databricks
# Docs at https://docs.microsoft.com/en-us/azure/databricks/dev-tools/api/latest/workspace#--import


$fileName = "$(System.DefaultWorkingDirectory)/<path to file in artifact>/<filename>.py"
$newNotebookName = "ImportedNotebook"
# Get our secret from the variable
$Secret = "Bearer " + "$(Databricks)"

# Set the URI of the workspace and the API endpoint
$Uri = "https://<your region>.azuredatabricks.net/api/2.0/workspace/import"

# Open and import the notebook
$BinaryContents = [System.IO.File]::ReadAllBytes($fileName)
$EncodedContents = [System.Convert]::ToBase64String($BinaryContents)

$Body = @{
    content = "$EncodedContents"
    language = "PYTHON"
    overwrite = $true
    format = "SOURCE"
    path= "/Users/<your user>/" + "$newNotebookName"
}

#Convert body to JSON
$BodyText = $Body | ConvertTo-Json

$headers = @{
    Authorization = $Secret
}

Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $BodyText


#######################################################
#
# Deploy Multiple Runbooks
#
######################################################
param(

   [Parameter(Mandatory=$true)][string]$tenant_id,
   [Parameter(Mandatory=$true)][string]$client_id,
   [Parameter(Mandatory=$true)][string]$client_secret,
   [Parameter(Mandatory=$true)][string]$subscription_id,
   [Parameter(Mandatory=$true)][string]$resourceGroup,
   [Parameter(Mandatory=$true)][string]$workspaceName,
   [Parameter(Mandatory=$true)][string]$notebookPath_workspace
)

##############################
# Get Access Token
##############################
# Variables
$DBXressource = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" # CF. AzureDatabricks AzureAD application. Seems unique for all Azure AD tenant.
$servicePrincipalName = "dbx-adm-spn1" # Service Principal that has the Owner privilege on the Databricks resource "dld-corp-mvp-dbx"
$servicePrincipalSecret = "SecureSecret" # The Service Principal Secret
$SubscriptionId="0b8ec247-78c7-4124-9330-cf76462b47a3" # The Subscription id where the Databricks ressource belongs to 
$ResourceGroupName = "monoline-Dev" # The Rresource Group name where the Databricks ressource belongs to
$WorkspaceName = "monoline-adb-Dev" # The name of the Databricks ressource
$Resource = "https://management.core.windows.net/"

# Connect to Azure
Connect-AzAccount
$TenantId=(Get-AzContext).Tenant.Id
$RequestAccessTokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/token"

# Get Databricks
$dbxurl = (Get-AzResource -Name $WorkspaceName -ResourceGroupName $ResourceGroupName -ExpandProperties).Properties.workspaceUrl
$uriroot = "https://$dbxurl/api" 

# Get the Service Principal that has been granted the "Owner" privilege on Databricks
$servicePrincipal = Get-AzADServicePrincipal -DisplayName $servicePrincipalName 
$servicePrincipleNameId = $servicePrincipal.ApplicationId.Guid

# Get AzureDatabricks app token
$body = "grant_type=client_credentials&client_id=$servicePrincipleNameId&client_secret=$servicePrincipalSecret&resource=$DBXressource"
$Token = Invoke-RestMethod -Method Post -Uri $RequestAccessTokenUri -Body $body -ContentType 'application/x-www-form-urlencoded'
$apiKey = $Token.access_token

# Get Azure Management token
$bodyManagement = "grant_type=client_credentials&client_id=$servicePrincipleNameId&client_secret=$servicePrincipalSecret&resource=$Resource"
$Token = Invoke-RestMethod -Method Post -Uri $RequestAccessTokenUri -Body $bodyManagement -ContentType 'application/x-www-form-urlencoded'
$apiKeyManagement = $Token.access_token

# Get Databricks workspace URL
 $Params = @{
     Uri = "https://management.azure.com/subscriptions/$subscription_id/resourcegroups/$resourceGroup/providers/Microsoft.Databricks/workspaces/$workspaceName?api-version=2018-04-01"
     Authentication = "Bearer"
     Token = $apiKeyManagement
 }
 $workspaceUrl=(Invoke-RestMethod @Params).properties.workspaceUrl

######################################################################################
# Deploy notebooks (resursively)
######################################################################################

  $filenames = get-childitem $notebookPath_workspace -recurse | where {$_.extension -eq ".py"};
                $filenames | ForEach-Object {
                  $NewNotebookName = $_.Name
                  #Get Our PAT Token for workspace from the Variable 
                  $Secret = "Bearer "+ "$apiKey";
                  #Set the URI for API Endpoint
                  $ImportNoteBookAPI = "$workspaceUrl"+"/api/2.0/workspace/import";
                  $FolderCheckAPI= "$workspaceUrl"+"/api/2.0/workspace/get-status";
                  $FolderCreateAPI = "$workspaceUrl"+"/api/2.0/workspace/mkdirs"
                  #Open and Import the Notebook to Workspace
                  $BinaryContents = [System.IO.File]::ReadAllBytes($_.FullName);
                  $EncodedContents = [System.Convert]::ToBase64String($BinaryContents);
                  $foldername = $_.FullName.split("\")[$_.FullName.split("\").length-2];
                  $folderpath = "/"+$foldername + "/";
                  $notebookpath = $folderpath + "$NewNotebookName"
                  #API Body for Importing Notebooks 
                  $ImportNoteBookBody = @{
                      content = "$EncodedContents"
                      language = "PYTHON"
                      overwrite = $true
                      format = "SOURCE"
                      path = $notebookpath 	
                  }
                  #Convert body to JSON
                  $ImportNoteBookBodyText = $ImportNoteBookBody | ConvertTo-Json

                  #API Body for Creating Folder 
                  $CreateFolderBody = @{
                      path = $folderpath 	
                  }
                  #Convert body to JSON
                  $CreateFolderBodyText = $CreateFolderBody | ConvertTo-Json
                  #Headers for all the API calls
                  $headers = @{
                      Authorization = $Secret
                  }
                  try{

                  #Check if the folder exists 
                  $CheckPath = $FolderCheckAPI + "?path="+ $folderpath; 
                  $CheckFolder = Invoke-RestMethod -Uri $CheckPath -Method Get -Headers $headers;
                  }
                  catch [System.Net.WebException] 
                 {
                  Write-Host "Entering the catch block and Creating Folder"; 
                  #Creating a Folder if it does not exists  
                  Invoke-RestMethod -Uri $FolderCreateAPI -Method Post -Headers $headers -Body $CreateFolderBodyText
                 }
                 #Importing a notebook to the Folder in Target DataBricks Workspace
                  Write-Host "Creating Notebook " + $notebookpath 
                  Invoke-RestMethod -Uri $ImportNoteBookAPI -Method Post -Headers $headers -Body $ImportNoteBookBodyText
                 }
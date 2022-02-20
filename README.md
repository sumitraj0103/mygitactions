# Azure-Databricks-Dev-Ops
Complete end to end sample of doing DevOps with Azure Databricks. The included code utilizes KeyVault for each environement and uses Azure AD authorization tokens to call the Databricks REST API.

This will show you how to deploy your Databricks assests via **GitHub Actions** so that your Notebooks, Clusters, Jobs and Init Scipts are automatically deployed and configured per environment.

## How to deploy this in your subscription
- Create a service principal that will be used for your DevOps pipeline.
      - Add the service principal to the Contributor role to your Subscription.
   - Create Azure Resource
      - Create resource groups
         - Databricks-monoline-Dev
         - Databricks-monoline-PrProd
         - Databricks-monoline-Prod
      - Grant the service principal to the Contributor role to each Resource Group

## GitHub Actions Setup
- Click on Settings | Secrets and create a secret named: DEV_AZURE_CREDENTIALS/PROD_AZURE_CREDENTIALS
  - Add this values of your Service Principal 
    ```
    {
      "clientId": "REPLACE:00000000-0000-0000-0000-000000000000",
      "clientSecret": "REPLACE: YOUR PASSWORD/SECRET",
      "subscriptionId": "REPLACE:00000000-0000-0000-0000-000000000000",
      "tenantId": "REPLACE:00000000-0000-0000-0000-000000000000",
      "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
      "resourceManagerEndpointUrl": "https://management.azure.com/",
      "activeDirectoryGraphResourceId": "https://graph.windows.net/",
      "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
      "galleryEndpointUrl": "https://gallery.azure.com/",
      "managementEndpointUrl": "https://management.core.windows.net/"
    }
    ```
- In the Azure Portal
     - Go to the KeyVault and Create KeyVault-Monoline-Dev
     - Click on Access Policies
         - NOTE: You might have to wait a few minutes to add the policies, mine gave a error at first and then was okay.
         - Click ```Add Access Policy```
            - Configure from template: ```Secret Management```
            - Key Permissions ```0 Selected``` 
            - Secret Permissions ```2 Selected``` (select just Get and List)
            - Certificate Permissions ```0 Selected``` 
            - Select your Azure Pipeline Service Principal (you can enter the Client ID (Guid) in the search box)
            - Click Add
            - Click Save
         - Repeat the above steps and add yourself as a Full Secret management.  You need to add yourself so you can set the secrets. 
            - Select the template ```Secret Management```
            - **Leave** all the Secret Permissions selected
            - Select yourself as the Principal
            - Click Add
            - Click Save
     - Click on Secrets
       - Click Generate / Import
       - You set the secret value 
          - databricks-monoline-dev-subscription-id
          - databricks-monoline-dev-tenant-id
          - databricks-monoline-dev-client-id
          - databricks-monoline-dev-client-secret
         
- Click on ```Actions``` and click ```Databricks-CI-CD``` and click  ```Run workflow```
   - Fill in the fields (only **bold** are not the defaults)
      - Notebooks Relative Path in Git: ```notebooks/Monoline```
      - Notebooks Deployment Path to Databricks: ```/Monoline```
      - Resource Group Name: ```Databricks-Monoline``` (NOTE: "-Dev" will be appended)
      - Azure Region: ```SouthestAsia```
      - Databricks workspace name: ```Databricks-Monoline-Dev```
      - KeyVault name: ```KeyVault-Monoline-Dev``` ** NOTE: You need to put a 1 or 2, etc on the end of this to make it globally unique**
      - Azure Subscription Id: **replace this ```00000000-0000-0000-0000-000000000000```**
      - Deployment Mode: **```Initialize KeyVault```**
      - Click "Run workflow"


### Setting Approvals
You shoudl set approvals on each environment so the pipeline does not deploy to Dev/PreProd/Prod without an Approval.
 
## What Happens during the Pipeline (GitHub Actions / Azure Pipeline)

- KeyVault Secrets are downloaded by DevOps
  - This allows you to have a KeyVault per Environemnt (Dev, QA, Prod)
  - A lot of customers deploy QA and Prod to different Azure Subscriptions, so this allows each environment to be secured appropriately.  The Pipeline Template just references KeyVault secret names and each environment will be able to obtain the secrets is requires.
  - If you re-run the KeyVault mode of the pipeline all your secrets and access policies will be overwritten.  That is why you just want to run it once.  If you mess up, no big deal, just redo the settings.

- Init Scripts are deployed
   - The script obtains an Azure AD authorization token using the Service Principal in KeyVault.  This token is then used to call the Databricks REST API
   - A DBFS path of ```dbfs:/init-scripts``` is created
   - All init scripts are then uploaded 
   - Init scripts are deploy before clusters since clusters can reference them

- Clusters are deployed
   - The script obtains an Azure AD authorization token using the Service Principal in KeyVault.  This token is then used to call the Databricks REST API
   - New clusters created
   - Existing clusters are updated
   - Clusters are then Stopped. 
      - If you deploy with active jobs, you might not want to run the stop code.
      - You might get a cores quota warning (meaning you do not have enough cores in your Azure subscription to start that many clusters), but the code will stop the clusters anyway, so it might not be an issue.
   ![alt tag](https://raw.githubusercontent.com/AdamPaternostro/Azure-Databricks-Dev-Ops/master/images/Databricks-Clusters-Deployed.png)

- Notebooks are deployed
   - The script obtains an Azure AD authorization token using the Service Principal in KeyVault.  This token is then used to call the Databricks REST API
   - The notebooks are deployed to the ```/Users``` folder under a new folder that your specify.  The new folder is not under any specific user, it will be at the root.  I consider notebooks under a user as experimental and should not be used for official jobs.  
   ![alt tag](https://raw.githubusercontent.com/AdamPaternostro/Azure-Databricks-Dev-Ops/master/images/Databricks-Notebooks-Deployed.png)

- Jobs are deployed
   - The script obtains an Azure AD authorization token using the Service Principal in KeyVault.  This token is then used to call the Databricks REST API
   - Jobs are deployed as follows:
      - Get the list of Jobs and Clusters (we need this for cluster ids)
      - Process the each jobs.json
      - Search the list of jobs based upon the job name
      - If the jobs does not exists
         - If the attribute "existing_cluster_id" exists in the JSON (it does not have to), the script replace the value by looking up the Cluster Id and call "Create"
            - **NOTE: YOU DO NOT PUT YOUR CLUSTER ID** in the existing cluster id field.  You need to put the **Cluster Name** and this script will swap it out for you.  Your cluster id will change per environment.
      - If the job exists
         - If the attribute "existing_cluster_id" exists in the JSON (it does not have to), the script replace the value by looking up the Cluster Id and call "Create"
            - **NOTE: YOU DO NOT PUT YOUR CLUSTER ID** in the existing cluster id field.  You need to put the **Cluster Name** and this script will swap it out for you.  Your cluster id will change per environment.
         - The script will take the entire JSON (in your file) and place it under a new attribute named "new_settings"
         - The script will inject the attribute "job_id" and set the value
         - Call "Reset" which is "Update"
   ![alt tag](https://raw.githubusercontent.com/AdamPaternostro/Azure-Databricks-Dev-Ops/master/images/Databricks-Jobs-Deployed.png)

## Adding your own items
  - You might want to deploy policies, upload JAR files, etc.
  - You start by placing these in source control
  - You edit the pipeline to place the item in an artifact
  - You can should created a new script under the ```deployment-scripts``` folder.
     - Borrow some code from one of the other tasks.
     - Look up the Databricks REST API and see what JSON you need
     - Some calls have a Create and a seperate Update with slightly different JSON
  - Think about the order of operations.  If you are creating a Databricks Job and it references a cluster, then you should deploy the Job after the clusters.
  - NOTE: If you need to inject a value (e.g. Databricks "cluster_id"), you can see the technique in the deploy-clusters.sh script.  Some items require you to reference an internal Databricks value during your deployment.

## How to use with your own existing Databricks environment
- Your existing workspace will mostlikely be your "work area" that you need to tie to source control.
   -  In my example I would create a resource group in Azure named ```Databricks-MyProject-WorkArea```
   - Create a Databricks workspace in Azure named ```Databricks-MyProject-WorkArea``` in the resource group ```Databricks-MyProject-WorkArea```
- Link your Databricks to source control
   - https://docs.databricks.com/notebooks/github-version-control.html
- Create or import some notebooks 
   - I imported some test notebooks from Databricks for this test repo
- Link the Notebook to the Azure DevOps repo 
- Save your Notebook
- Create a cluster
  - Int the cluster UI there is a "JSON" link that will show you the JSON to create the cluster.  You can cut and paste that as your cluster defination.  You will need to remove the "cluster_id" since Databricks determines this, you cannot send it in your JSON.
- Re-run the pipeline and the Notebook should be pushed to Dev, QA and Prod

## Important Details
- You can test everything locally.  Open a bash prompt and change to the directory of the items you want to deploy and call the appropriate deployment script.
- The deployment scripts expect to have their ```working directory``` set to be in the folder as the ```artifacts``` (e.g. if deploying jobs then run from jobs folder)
   - You can run via command line locall to test
   ```
   # Change the below path
   cd ./Azure-Databricks-Dev-Ops/notebooks/MyProject 
   
   ../../deployment-scripts/deploy-notebooks.sh \
      '00000000-0000-0000-0000-000000000000 (tenant id)' \
      '00000000-0000-0000-0000-000000000000 (client id)' \
      '... (client secret)' \
      '00000000-0000-0000-0000-000000000000 (subscription id)' \
      'Databricks-MyProject-Dev' \
      'Databricks-MyProject-Dev' 
      '/ProjectFolder'   
   ```
- In the Test-DevOps-Job-Interactive-Cluster.json, note the code ```"existing_cluster_id": "Small"```.  The existing cluster id says "Small" which is **NOT** an actual cluster id.  It is actually the name field in the small-cluster.json (```"cluster_name": "Small",```).  During deployment the deploy-jobs.sh will lookup the **existing_cluster_id** value in the **name** field and populate the jobs JSON with the correct Databricks cluster id.
   ```
   {
      "name": "Test-DevOps-Job-Interactive-Cluster",
      "existing_cluster_id": "Small", <- this gets replaced with the actual cluster id
      "email_notifications": {},
      "timeout_seconds": 0,
      "notebook_task": {
         "notebook_path": "/MyProject/Pop vs. Price SQL.sql",
         "revision_timestamp": 0
      },
      "max_concurrent_runs": 1
   }
   ```
- You do not need to use the Resource Groups names with just a suffix of "-Dev", "-QA" or "-Prod", you can edit the azure-pipelines.yml to make these values whatever you like.
      

## Notes
- You can used your own KeyVault
  - The DevOps service principal just needs access to read the keys.
  - Just add the secrets to your KeyVault and grant the service principal access via a policy.
- I do **not** use the Databricks CLI.  
  - I know there are some DevOps Marketplace items that will deploy Notebooks, etc.  The reason for this is that customers have had issues with the CLI installing on top of one another and their DevOps pipelines break.  The Databricks REST API calls are simple and installing the CLI adds a dependency which could break.
- To get the JSON to deploy, you can use the script ```Sample-REST-API-To-Databricks.sh``` to call the ```List``` operation to get existing items from a workspace.  If you create a new Job in Databricks, then run this script calling the ```jobs/list``` to grab the JSON to place in source control. 


## Potential Improvements
- This does not deleted items removed from source control from the Databricks workspace.  At the end of each script you would need to add code to get a list of items and then remove any that are no longer under source control.
- Change pipeline test for the existance of a KeyVault if you want to eliminate the Mode parameter (Intialize-KeyVault | Databricks).  If the KeyVault exists, then just skip the KeyVault ARM template task.
- Seperate the tasks into another repo and call then from this pipeline.  This would make the tasks more re-useable, especially accross many differnet Git repos.  
   - See https://docs.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops#use-other-repositories
- This architecture needs to be updated this based upon the new Data Science Git Projects instead of using the Notebook per Git integration.
   - Databricks has a new feature where Notebooks do not need to be indiviually linked.  
   - This should make deploying notebooks easier, but existing customers might need time to migrate
- Deploy Hive/Metastore table changes/scripts
  - The above pipeline does not deploy Hive tables.
  - You could deploy a notebook with you Hive CREATE tables in the notebook and then execute the notebook
- Deal with deploying Mount Points.  
  - Most customers tha use mount ponits will run a Notebook, one time, and then delete it.  This configures the mount points and then the notebook is deleted to hide the secrets.
- Databricks does not have a REST API to configure Azure KeyVault to be the backing store of your Databricks Secrets. 
  - https://docs.microsoft.com/en-us/azure/databricks/security/secrets/secret-scopes#--create-an-azure-key-vault-backed-secret-scope
  - When there is one, this should be updated to include a sample.   
  - You could try using a Selenium Task to automate a browser experience
- You can deploy your Databricks to a VNET.  See here for how to update the include Databricks ARM template ([Link](https://github.com/Azure/azure-quickstart-templates/blob/master/101-databricks-all-in-one-template-for-vnet-injection/azuredeploy.jsong "Link"))
- The Bash scripts could be re-written in PowerShell Core for users who are more familiar with PowerShell.

## What about Data Thrist and Azure Docs
- Some people have asked if they should use Data Thrist from the Azure Dev Ops marketplace
   - https://marketplace.visualstudio.com/items?itemName=DataThirstLtd.databricksDeployScriptsTasks
   - If this works for you then it is a good choice.
   - I prefer the Databricks REST API calls since I can use Azure Dev Ops Pipelines or GitHub Actions
- What about this advice on Azure Docs: https://docs.microsoft.com/en-us/azure/databricks/dev-tools/ci-cd/ci-cd-azure-devops
   - Great reading around packaging up a Python library and deploying to a cluster
   - If you prefer Python versus Bash "deployment-scripts" then grab these for your DevOps
   - I like how they do a test and ingest the results back into Azure Dev Ops .

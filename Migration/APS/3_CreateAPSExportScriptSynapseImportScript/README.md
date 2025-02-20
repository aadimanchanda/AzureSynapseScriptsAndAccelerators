
# **3_CreateAPSExportScriptSynapseImportScript:** Generates the export and import statements required to move the data from APS to Azure Synapse

The program processing logic and information flow is illustrated in the diagram below: 


![Create APS Export amd Synapse Import Scripts Programs](../Images/3_CreateAPSExportScriptSynapseImportScript_v2.PNG)

## **What the Script Does** ##

The PowerShell script generates T-SQL scripts to export APS data into Azure Blob Storage. It also generates T-SQL Scripts to import exported data from Azure Blob Storage into Azure Synapse. 

The program generates the right structure, with the specified table, specified external data source name, the specified file format, and the specified location in Azure Blob Storage to store the data. All the specifications are set in the configuration driver CSV file. 

Below are example of the T-SQL scripts for one single table.

Sample generated T-SQL scripts to export APS table data into Azure Blob Storage:    

```sql
CREATE EXTERNAL TABLE AdventureWorksDW.EXT_aw.FactFinance
WITH (
	LOCATION='/AdventureWorksDW/dbo_FactFinance',
	DATA_SOURCE = AZURE_STAGING_STORAGE,
	FILE_FORMAT = DelimitedFileFormat
)
AS 
SELECT * FROM AdventureWorksDW.dbo.FactFinance
OPTION (LABEL= 'Export_Table_AdventureWorksDW.dbo.FactFinance')
```

Sample generated T-SQL scripts to import data into Azure Synapse using External Table (Polybase):

```sql
INSERT INTO aw.FactFinance
SELECT * FROM EXT_aw.FactFinance
OPTION (LABEL = 'Import_Table_aw.FactFinance')
```

Sample generated T-SQL scripts to import data into Azure Synapse using COPY INTO command:

```sql
COPY INTO [aw].[FactFinance]
FROM 'https://apsmigrationstaging.blob.core.windows.net/aps-export/AdventureWorksDW/dbo_FactFinance/*.txt'
WITH ( 
	FILE_TYPE = 'CSV', 
	CREDENTIAL = (IDENTITY = 'Managed Identity'), 
	FIELDQUOTE = '"', 
	FIELDTERMINATOR='|', 
	ROWTERMINATOR = '0x0A', 
	FIRSTROW = 1, 
	--[DATEFORMAT = 'date_format'], 
	ENCODING = 'UTF8' 
) 
OPTION (LABEL = 'Import_Table_aw.FactFinance')
```



> Note that you can also use PowerShell-script to extract source data to Parquet-files. The script is available under [/Migration/SQLServer/2B_ExportSourceDataToParquet](../../SQLServer/2B_ExportSourceDataToParquet) folder (it is applicable to APS/PDW too). It allows to offload data to Parquet-files on a local storage, network storage, or Azure Data Box appliance without configuring Polybase.




## **How to Run the Script** ##

Below are the steps to run the PowerShell script: 

**Step 3A:** Prepare the configuration CSV file for PowerShell script. 
Create the configuration driver CSV File based on the definition below. Sample CSV configuration file is provided to aid this preparation task. 

There is also a job-aid PowerShell script called [**Generate_Step3_ConfigFiles.ps1**](Generate_Step3_ConfigFiles.ps1) which can help you to generate an initial configuration file for this step. This Generate_Step3_ConfigFiles.ps1 uses a driver configuration CSV file named [**ConfigFileDriver_Step3.csv**](ConfigFileDriver_Step3.csv) which has instructions inside for each parameter to be set. 

Refer ***[Job Aid: Programmatically Generate Config Files](#job-aid:-programmatically-generate-config-files)*** after the steps for more details.

| **Parameter**      | **Purpose**                                                  | **Value (Sample)**                                           |
| ------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| Active             | 1 – Run line, 0 – Skip line                                  | 0 or 1                                                       |
| DatabaseName       | The name of the database in APS                              | AdventureWorksDW                                             |
| OutputFolderPath   | The path to output folder where generated scripts will be stored.<br />*Both absolute and relative paths are supported.* | ..\Output\3_CreateAPSExportScriptSynapseImportScript<br />\ExportAPS\AdventureWorksDW |
| FileName           | The name of the output file                                  | DimAccount.sql                                               |
| SourceSchemaName   | The name of the source Schema                                | dbo                                                          |
| SourceObjectName   | The name of the source table                                 | DimAccount                                                   |
| DestSchemaName     | The name of the destination schema in  Synapse for external tables | EXT_aw                                                       |
| DestObjectName     | The name of the destination table                            | DimAccount                                                   |
| DataSource         | The name of the External Data Source to use for the external table | AZURE_STAGING_STORAGE                                        |
| FileFormat         | The name of the External File Format to use  when exporting the data | DelimitedFileFormat                                          |
| ExportLocation     | Folder path in the staging  container. Each Table should have its own file location. | /AdventureWorksDW/dbo_DimAccount                             |
| InsertFilePath     | The path to folder where INSERT INTO scripts will be created.<br />*Both absolute and relative paths are supported.* | ..\Output\3_CreateAPSExportScriptSynapseImportScript<br />\ImportSynapse\AdventureWorksDW\ |
| CopyFilePath       | The path to folder where COPY INTO scripts will be created.<br />*Both absolute and relative paths are supported.* | ..\Output\3_CreateAPSExportScriptSynapseImportScript<br />\CopySynapse\AdventureWorksDW\ |
| ImportSchema       | The name of the target schema in Synapse                     | aw                                                           |
| StorageAccountName | The name of Azure staging storage  account                   | apsmigrationstaging                                          |
| ContainerName      | The name of the container in Azure staging storage account   | aps-export                                                   |

**Step 3B:** 
Run PowerShell script [**ScriptCreateExportImportStatementsDriver.ps1**](ScriptCreateExportImportStatementsDriver.ps1). 
Provide the prompted information: The path and name of the Configuration Driver CSV File. The script does not connect to APS or Synapse.  The only input for this script is the [**ConfigFileDriver_Step3.csv**](ConfigFileDriver_Step3.csv). 

> ###### Note 1
>
> Later before actually exporting data from APS you will need to have External Data Source and External File Format created in APS. You can use sample script [CreateExternalObjects.sql](CreateExternalObjects.sql) as a template. 

> ###### Note 2
>
> When exporting data from APS to Azure Blob Storage make sure that you Azure storage account is configured for **Minimum TLS Version 1.0**. Otherwise you may encounter an error when creating external tables.
>
> `CREATE EXTERNAL TABLE AS SELECT statement failed as the path name 'wasbs://container@storageaccount.blob.core.windows.net/DatabaseName/TableName' could not be used for export. Please ensure that the specified path is a directory which exists or can be created, and that files can be created in that directory.` 




## Job Aid: Programmatically Generate Config Files

There is a job-aid PowerShell script named [**Generate_Step3_ConfigFiles.ps1**](Generate_Step3_ConfigFiles.ps1) to help you to produce configuration file(s) programmatically. It uses output produced by previous steps (for example: T-SQL script files from step 2, and schema mapping file from step 2). 

It uses parameters set inside the file named [**ConfigFileDriver_Step3.csv**](ConfigFileDriver_Step3.csv). The CSV file contains fields as value-named pairs with instructions for each field. You can set the value for each named field based on your own setup and output files. 

| **Name**                   | Description                                                  | **Value (Sample)**                                           |
| -------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| OneConfigFile              | Yes - a single configuration file will be created for all databases.<br />No - separate configuration files will be created for each database. | Yes or No                                                    |
| OneConfigFileName          | The name of configuration file in case of single configuration file. | One_ExpImptStmtDriver_Generated.csv                          |
| ExtTableShemaPrefix        | Schema name prefix for external tables (can be empty)        | EXT_                                                         |
| ExtTablePrefix             | Name prefix for external tables (can be empty)               | -                                                            |
| InputObjectsFolder         | The path to a folder where converted table DDL scripts are stored.<br />*Both absolute and relative paths are supported.* | ..\Output\2_ConvertDDLScripts                                |
| SchemaMappingFileFullPath  | The path to schema mapping file (the file from previous module can be used).<br />*Both absolute and relative paths are supported.* | ..\2_ConvertDDLScripts\schemas.csv                           |
| ApsExportScriptsFolder     | The path to a folder where APS CETAS scripts will be created.<br />*Both absolute and relative paths are supported.* | ..\Output<br />\3_CreateAPSExportScriptSynapseImportScript<br />\ExportAPS |
| SynapseImportScriptsFolder | The path to a folder where Synapse INSERT INTO scripts will be created.<br />*Both absolute and relative paths are supported.* | ..\Output<br />\3_CreateAPSExportScriptSynapseImportScript<br />\ImportSynapse |
| SynapseCopyScriptsFolder   | The path to a folder where Synapse COPY INTO scripts will be created.<br />*Both absolute and relative paths are supported.* | ..\Output<br />\3_CreateAPSExportScriptSynapseImportScript<br />\CopySynapse |
| ExternalDataSourceName     | The name of external data source used by Polybase to export/import data | AZURE_STAGING_STORAGE                                        |
| FileFormat                 | The name of external file format used by Polybase to export/import data | DelimitedFileFormat                                          |
| ExportLocation             | Root folder in storage account container where data will be exported/imported. | /                                                            |
| StorageAccountName         | The name of Azure storage account which will be used to export/import data | apsmigrationstaging                                          |
| ContainerName              | The name of a container in Azure storage account which will be used to export/import data | aps-export                                                   |

After running the [**Generate_Step3_ConfigFiles.ps1**](Generate_Step3_ConfigFiles.ps1), you can then review and edit the programmatically generated configuration files based on your own needs and environment. The generated config file(s) can then be used as input to the step 3 main script [**ScriptCreateExportImportStatementsDriver.ps1**](ScriptCreateExportImportStatementsDriver.ps1).


​    

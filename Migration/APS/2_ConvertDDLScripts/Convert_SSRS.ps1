﻿#======================================================================================================================#
#                                                                                                                      #
#  AzureSynapseScriptsAndAccelerators - PowerShell and T-SQL Utilities                                                 #
#                                                                                                                      #
#  This utility was developed to aid SMP/MPP migrations to Azure Synapse Migration Practitioners.                      #
#  It is not an officially supported Microsoft application or tool.                                                    #
#                                                                                                                      #
#  The utility and any script outputs are provided on "AS IS" basis and                                                #
#  there are no warranties, express or implied, including, but not limited to implied warranties of merchantability    #
#  or fitness for a particular purpose.                                                                                #
#                                                                                                                      #                    
#  The utility is therefore not guaranteed to generate perfect code or output. The output needs carefully reviewed.    #
#                                                                                                                      #
#                                       USE AT YOUR OWN RISK.                                                          #
#                                                                                                                      #
#======================================================================================================================#
#
# =================================================================================================================================================
# Description:
#       Updates object names in SSRS project according to schema mappings (APS-->Synapse)
#        
# =================================================================================================================================================
# 
# Authors: Andrey Mirskiy
# Tested with APS (Analytics Platform System)
# 
# Use this to set Powershell permissions (examples)
# Set-ExecutionPolicy Unrestricted -Scope CurrentUser 
# Unblock-File -Path C:\AzureSynapseScriptsAndAccelerators\Migration\APS\2_ConvertDDLScripts\Convert_SSRS.ps1


param(
    [Parameter(Mandatory=$false, HelpMessage="Path to SSRS project folder.")]
    [string]
    $ProjectFolder = "C:\Users\user\Sales reports",

    [Parameter(Mandatory=$false, HelpMessage="Path to schema mapping file.")]
    [string] 
    $schemasFilePath = "C:\AzureSynapseScriptsAndAccelerators\Migration\APS\2_ConvertDDLScripts\schemas.csv",

    [Parameter(Mandatory=$false, HelpMessage="Default schema which will be used if schema name is omitted.")] 
    [string]
    $defaultSchema = "dbo",

    [Parameter(Mandatory=$false, HelpMessage="Save changes to data source files.")] 
    [bool]
    $UpdateDataSources = $true,

    [Parameter(Mandatory=$false)] 
    [string]
    $AzureSqlServerName = "servername.sql.azuresynapse.net",
    
    [Parameter(Mandatory=$false)] 
    [string]
    $SynapseName = "dwoty",

    [Parameter(Mandatory=$false, HelpMessage="Save changes to SSRS source code.")] 
    [bool]
    $SaveFiles = $true
)


Import-Module $PSScriptRoot\FixSchemas.ps1 -Force


$startTime = Get-Date


$schemaCsvFile = Import-Csv $schemasFilePath
$dsFiles = Get-Item -Path $projectFolder\*.rds
$rsdFiles = Get-Item -Path $projectFolder\*.rsd
$rdlFiles = Get-Item -Path $projectFolder\*.rdl 

$dataSources = @{}
foreach ($dsFile in $dsFiles)
{
    Write-Host "Processing data source file - $dsFile" -ForegroundColor Yellow

    $content = [xml](Get-Content $dsFile)
    $ID = $content.RptDataSource.DataSourceID
    $name = $content.RptDataSource.Name
    $extension = $content.RptDataSource.ConnectionProperties.Extension
    $connectionString = $content.RptDataSource.ConnectionProperties.ConnectString

    # If it's not APS connection
    if (!$connectionString.Contains(",17001") -or ($extension -ne "SQL")) {
        continue
    }           

    $builder = New-Object -TypeName System.Data.OleDb.OleDbConnectionStringBuilder -ArgumentList $connectionString
    $databaseName = $builder["initial catalog"]
    $dataSources.Add($name, $databaseName)

    if ($UpdateDataSources -eq $true)
    {
        $newConnectionString = "Provider=MSOLEDBSQL.1;Data Source=$AzureSqlServerName;Persist Security Info=True;Password=;User ID=$userId;Initial Catalog=$SynapseName"        
        $content.RptDataSource.ConnectionProperties.ConnectString = $newConnectionString

        $content.Save($dsFile)
    }
}


$i = 0

foreach ($rsdFile in $rsdFiles)
{
    Write-Host "Processing shared dataset file - $rsdFile" -ForegroundColor Yellow

    $content = [xml](Get-Content $rsdFile)
    $changed = $false

    $dataSourceName = $content.SharedDataSet.DataSet.Query.DataSourceReference
    if ($datasources.Contains($dataSourceName) -eq $false) {
        continue
    }
    $currentDatabaseName = $datasources[$dataSourceName]
    if ([string]::IsNullOrEmpty($currentDatabaseName)) {
        continue
    }

    $commandText = $content.SharedDataSet.DataSet.Query.CommandText

    Write-Host "BEFORE:", $commandText -ForegroundColor Yellow

    if ($commandType -in ("StoredProcedure", "TableDirect")) 
    {
        # This is Stored Procedure or Table or View
        $commandText = AddMissingSchemasSimple -query $commandText -defaultSchema $defaultSchema
        $changed = $true
    }
    else
    {
        $commandText = AddMissingSchemas -query $commandText -defaultSchema $defaultSchema
        $changed = $true
    }
    Write-Host "BEFORE:", $commandText -ForegroundColor Yellow

    $commandText = ChangeSchemas -DatabaseName $currentDatabaseName -SchemaMappings $schemaCsvFile -DefaultSchema $defaultSchema -query $commandText
    Write-Host "AFTER:", $commandText -ForegroundColor Green

    $content.SharedDataSet.DataSet.Query.CommandText = $commandText

    if ($SaveFiles -and $changed)
    {
        $content.Save($rsdFile)
    }

    Write-Progress -PercentComplete (++$i * 100.0 / $rdlFiles.Count) -Activity "Updating RDL files"
}



$i = 0

foreach ($rdlFile in $rdlFiles)
{
    Write-Host "Processing report file - $rdlFile" -ForegroundColor Yellow

    $content = [xml](Get-Content $rdlFile)

    $datasets = $content.Report.DataSets.DataSet
    $changed = $false
    
    foreach ($dataset in $datasets)
    {
        if (![string]::IsNullOrEmpty($dataset.SharedDataSet)) {
            continue
        }

        $dataSourceName = $dataset.Query.DataSourceName
        $commandType = $dataset.Query.CommandType
        $commandText = $dataset.Query.CommandText

        $dataSourceName = $content.Report.DataSources.DataSource | where {$_.Name -eq $dataSourceName} | select -ExpandProperty Name
        if ($datasources.Contains($dataSourceName) -eq $false) {
            continue
        }
        $currentDatabaseName = $datasources[$dataSourceName]

        # This is Stored Procedure or Table or View
        Write-Host "BEFORE:", $commandText -ForegroundColor Yellow

        if ($commandType -in ("StoredProcedure", "TableDirect")) 
        {
            $commandText = AddMissingSchemasSimple -query $commandText -defaultSchema $defaultSchema
            $changed = $true
        }
        else
        {
            $commandText = AddMissingSchemas -query $commandText -defaultSchema $defaultSchema
            $changed = $true
        }
        Write-Host "BEFORE:", $commandText -ForegroundColor Yellow

        $commandText = ChangeSchemas -DatabaseName $currentDatabaseName -SchemaMappings $schemaCsvFile -DefaultSchema $defaultSchema -query $commandText
        Write-Host "AFTER:", $commandText -ForegroundColor Green

        $dataset.Query.CommandText = $commandText
    }

    if ($SaveFiles -and $changed)
    {
        $content.Save($rdlFile)
    }

    Write-Progress -PercentComplete (++$i * 100.0 / $rdlFiles.Count) -Activity "Updating RDL files"
}

$finishTime = Get-Date

Write-Host "Program Start Time:   ", $startTime -ForegroundColor Green
Write-Host "Program Finish Time:  ", $finishTime -ForegroundColor Green
Write-Host "Program Elapsed Time: ", ($finishTime-$startTime) -ForegroundColor Green

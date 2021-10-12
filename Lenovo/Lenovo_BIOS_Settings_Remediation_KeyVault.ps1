#********************************************************************************************
# Part to fill
#
$CSV_URL = "" # Path of CSV containing BIOS settings with value to set
#
# Azure application info (for getting secret from Key Vault)
$TenantID = ""
$App_ID = ""
$ThumbPrint = ""
#
# Mode to install Az modules, 
# Choose Install if you want to install directly modules from PSGallery
# Choose Download if you want to download modules a blob storage and import them
$Az_Module_Install_Mode = "Install" # Install or Download
# Modules path on the web, like blob storage if the Az_Module_Install_Mode is setted to Download
$Az_Accounts_URL = ""
$Az_KeyVault_URL = ""
#
$vaultName = "" # Name of theKey Vault
$Secret_Name_New_PWD = "" # Name of the Secret containing the BIOS password
#********************************************************************************************

$SystemRoot = $env:SystemRoot
$Log_File = "$SystemRoot\Debug\Lenovo_BIOS_Settings_Remediation.log" 
If(!(test-path $Log_File)){new-item $Log_File -type file -force | out-null}

Function Write_Log
	{
	param(
	$Message_Type, 
	$Message
	)
		$MyDate = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
		Add-Content $Log_File  "$MyDate - $Message_Type : $Message" 
		write-host "$MyDate - $Message_Type : $Message" 
	} 
	
Add-Content $Log_File ""		
Write_Log -Message_Type "INFO" -Message "Starting BIOS settings remediation part"	
	
	
# Function used if Az_Module_Install_Mode is setted to Download
Function Import_from_Blob
	{
		$Modules_Path = "$env:temp\Modules"		
		$Az_Accounts_ZIP_Path = "$Modules_Path\Az_Accounts.zip"
		$Az_KeyVault_ZIP_Path = "$Modules_Path\Az_KeyVault.zip"
		$AzAccounts_Module = "$Modules_Path\Az.Accounts"
		$AzKeyVault_Module = "$Modules_Path\Az.KeyVault"

		Write_Log -Message_Type "INFO" -Message "Downloading AZ modules"	
		Try
			{
				Invoke-WebRequest -Uri $Az_Accounts_URL -OutFile $Az_Accounts_ZIP_Path
				Invoke-WebRequest -Uri $Az_KeyVault_URL -OutFile $Az_KeyVault_ZIP_Path
				Write_Log -Message_Type "SUCCESS" -Message "Downloading AZ modules"		
			}
		Catch
			{
				Write_Log -Message_Type "ERROR" -Message "Downloading AZ modules"		
				Remove_Current_script
				EXIT 1
			}	
		
		Write_Log -Message_Type "INFO" -Message "Extracting AZ modules"	
		Try
			{
				Expand-Archive -Path $Az_Accounts_ZIP_Path -DestinationPath $AzAccounts_Module -Force	
				Expand-Archive -Path $Az_KeyVault_ZIP_Path -DestinationPath $AzKeyVault_Module -Force	
				Write_Log -Message_Type "SUCCESS" -Message "Extracting AZ modules"		
			}
		Catch
			{
				Write_Log -Message_Type "ERROR" -Message "Extracting AZ modules"
				Remove_Current_script
				EXIT 1
			}	

		Write_Log -Message_Type "INFO" -Message "Importing AZ modules"	
		Try
			{
				import-module $AzAccounts_Module 
				import-module $AzKeyVault_Module 	
				Write_Log -Message_Type "SUCCESS" -Message "Importing AZ modules"		
			}
		Catch
			{
				Write_Log -Message_Type "ERROR" -Message "Importing AZ modules"		
				Remove_Current_script
				EXIT 1
			}	
	}

# Function used if Az_Module_Install_Mode is setted to Install
Function Install_Az_Module
	{ 	
		If($Is_Nuget_Installed -eq $True)
			{
				$Modules = @("Az.accounts","Az.KeyVault")
				ForEach($Module_Name in $Modules)
					{
						If (!(Get-InstalledModule $Module_Name)) 
							{ 
								Write_Log -Message_Type "INFO" -Message "The module $Module_Name has not been found"	
								Try
									{
										Write_Log -Message_Type "INFO" -Message "The module $Module_Name is being installed"								
										Install-Module $Module_Name -Force -Confirm:$False -AllowClobber -ErrorAction SilentlyContinue | out-null	
										Write_Log -Message_Type "SUCCESS" -Message "The module $Module_Name has been installed"	
										Write_Log -Message_Type "INFO" -Message "AZ.Accounts version $Module_Version"	
									}
								Catch
									{
										Write_Log -Message_Type "ERROR" -Message "The module $Module_Name has not been installed"			
										write-output "The module $Module_Name has not been installed"			
										Remove_Current_script
										EXIT 1							
									}															
							} 
						Else
							{
								Try
									{
										Write_Log -Message_Type "INFO" -Message "The module $Module_Name has been found"												
										Import-Module $Module_Name -Force -ErrorAction SilentlyContinue 
										Write_Log -Message_Type "INFO" -Message "The module $Module_Name has been imported"	
									}
								Catch
									{
										Write_Log -Message_Type "ERROR" -Message "The module $Module_Name has not been imported"	
										write-output "The module $Module_Name has not been imported"	
										Remove_Current_script
										EXIT 1							
									}				
							} 				
					}
					
					If ((Get-Module "Az.accounts" -listavailable) -and (Get-Module "Az.KeyVault" -listavailable)) 
						{
							Write_Log -Message_Type "INFO" -Message "Both modules are there"																			
						}
			}
	}
	
	
$Get_Manufacturer_Info = (gwmi win32_computersystem).Manufacturer
If($Get_Manufacturer_Info -notlike "*lenovo*")	
	{
		Write_Log -Message_Type "ERROR" -Message "Device manufacturer not supported"											
		write-output "Device manufacturer not supported"		
		EXIT 1			
	}
Else	
	{
		Write_Log -Message_Type "ERROR" -Message "Device manufacturer is Lenovo"											
	}
	
$Exported_CSV = "$env:TEMP\Lenovo_BIOS_Settings.CSV"
If(test-path $Exported_CSV)
	{
		Write_Log -Message_Type "INFO" -Message "The BIOS Settings CSV exists"  
		Write_Log -Message_Type "INFO" -Message "CSV path: $Exported_CSV"  		
	}
Else
	{
		Write_Log -Message_Type "INFO" -Message "The BIOS Settings CSV does not exist"  
		Invoke-WebRequest -Uri $CSV_URL -OutFile $Exported_CSV		
	}
	
# Prepare the CSV to be imported
Write_Log -Message_Type "INFO" -Message "Importing CSV file"  
$Get_CSV_FirstLine = Get-Content $Exported_CSV | Select -First 1
$Get_Delimiter = If($Get_CSV_FirstLine.Split(";").Length -gt 1){";"}Else{","};
Write_Log -Message_Type "INFO" -Message "Delimiter to use is: $Get_Delimiter"  
$Get_CSV_Content = Import-CSV $Exported_CSV  -Delimiter $Get_Delimiter		  
  
$Is_BIOS_Password_Protected = $False 
$IsPasswordSet = (gwmi -Class Lenovo_BiosPasswordSettings -Namespace root\wmi).PasswordState
If(($IsPasswordSet -eq 1) -or ($IsPasswordSet -eq 2) -or ($IsPasswordSet -eq 3))
	{
		Write_Log -Message_Type "INFO" -Message "There is a BIOS password"  
	
		$Check_Cert = (Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object {$_.Thumbprint -match "$Thumbprint"})
		If($Check_Cert -eq $null)
			{
				Write_Log -Message_Type "ERROR" -Message  "Can not find certificate" 			
				write-output "Can not find certificate"
				EXIT 1
			}	
		Else
			{
				Write_Log -Message_Type "INFO" -Message  "The certificate is there" 			
			}			
	
		$Is_BIOS_Password_Protected = $True
		$Is_Nuget_Installed = $False	
		If (!(Get-PackageProvider NuGet -listavailable)) 
			{
				Try
					{
						[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
						Install-PackageProvider -Name Nuget -MinimumVersion 2.8.5.201 -Force | out-null							
						Write_Log -Message_Type "SUCCESS" -Message "The NuGet package has been successfully installed"	
						$Is_Nuget_Installed = $True						
					}
				Catch
					{
						Write_Log -Message_Type "ERROR" -Message "An issue occured while installing NuGet package"	
						Break
					}
			}
		Else
			{
				Write_Log -Message_Type "INFO" -Message "The NuGet package is already installed" 						
				$Is_Nuget_Installed = $True	
			}

		If($Is_Nuget_Installed -eq $True)
			{
				If($Az_Module_Install_Mode -eq "Install")
					{
						Install_Az_Module
					}
				Else
					{
						Import_from_Blob
					}	
			}


		If(($TenantID -eq "") -and ($App_ID -eq "") -and ($ThumbPrint -eq ""))
			{
				Write_Log -Message_Type "ERROR" -Message "Info is missing, please fill: TenantID, appid and thumbprint"		
				write-output "Info is missing, please fill: TenantID, appid and thumbprint"
				Remove_Current_script
				EXIT 1					
			}

		Try
			{
				Write_Log -Message_Type "INFO" -Message "Connecting to your Azure application"														
				Connect-AzAccount -tenantid $TenantID -ApplicationId $App_ID -CertificateThumbprint $ThumbPrint | Out-null
				Write_Log -Message_Type "SUCCESS" -Message "Connection OK to your Azure application"			
				$Azure_App_Connnected = $True
			}
		Catch
			{
				Write_Log -Message_Type "ERROR" -Message "Connection KO to your Azure application"	
				write-output "Connection KO to your Azure application"	
				Remove_Current_script
				EXIT 1							
			}

		If($Azure_App_Connnected -eq $True)
			{
				# Getting the BIOS password
				$Secret_New_PWD = (Get-AzKeyVaultSecret -vaultName $vaultName -name $Secret_Name_New_PWD) | select *
				$Get_New_PWD = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret_New_PWD.SecretValue) 
				$Script:New_PWD = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($Get_New_PWD) 			
				$Get_New_PWD_Date = $Secret_New_PWD.Updated
				$Get_New_PWD_Date = $Get_New_PWD_Date.ToString("mmddyyyy")
				$Get_New_PWD_Version = $Secret_New_PWD.Version	

				$Getting_KeyVault_PWD = $True				
			}			
	}
Else
	{
		Write_Log -Message_Type "INFO" -Message "There is no BIOS password"  
	}
	
	
# Prepare the BIOS WMI language parameter	
$Get_culture_language = (Get-Culture).Name
If(($Get_culture_language -eq "fr-FR") -or ($Get_culture_language -eq "fr-BE"))
	{
		$Script:Language = 'fr'
		Write_Log -Message_Type "INFO" -Message "The default language will be fr"
	}
ElseIf(($Get_culture_language -like "*de*") -or ($Get_culture_language -like "*cs*") -or ($Get_culture_language -like "*sk*") -or ($Get_culture_language -like "*sl*"))
	{
		$Script:Language = 'gr'	
		Write_Log -Message_Type "INFO" -Message "The default language will be gr"
	}			
Else
	{
		Write_Log -Message_Type "INFO" -Message "The default language will be US" 
		$Script:Language = 'us'
	}	

# Change BIOS settings 
$BIOS = gwmi -class Lenovo_SetBiosSetting -namespace root\wmi 

# If there is a BIOS password
If(($Is_BIOS_Password_Protected -eq $True) -and ($Getting_KeyVault_PWD -eq $True))
	{		
		$MyPassword = $New_PWD		
		If($MyPassword -eq "")
			{
				Write_Log -Message_Type "WARNING" -Message "No password has been sent to the script"  	
				Break
			}
			
		ForEach($Settings in $Get_CSV_Content)
			{
				$MySetting = $Settings.Setting
				$NewValue = $Settings.Value						
				Write_Log -Message_Type "INFO" -Message "Change to do: $MySetting - $NewValue"  		
				$Execute_Change_Action = $BIOS.SetBiosSetting("$MySetting,$NewValue,$MyPassword,ascii,$Language")	
				$Change_Return_Code = $Execute_Change_Action.return				
				If(($Change_Return_Code) -eq "Success")        				
					{
						Write_Log -Message_Type "INFO" -Message "New value for $MySetting is $NewValue"  
						Write_Log -Message_Type "SUCCESS" -Message "The setting has been setted"  						
					}
				Else
					{
						Write_Log -Message_Type "ERROR" -Message "Can not change setting $MySetting (Return code $Change_Return_Code)"  						
					}
			}			
	}
Else
	{
		# If there is no BIOS password
		ForEach($Settings in $Get_CSV_Content)
			{
				$MySetting = $Settings.Setting
				$NewValue = $Settings.Value				
				Write_Log -Message_Type "INFO" -Message "Change to do: $MySetting - $NewValue"  
				$Execute_Change_Action = $BIOS.SetBiosSetting("$MySetting,$NewValue") 			
				$Change_Return_Code = $Execute_Change_Action.return			
				If(($Change_Return_Code) -eq "Success")        								
					{
						Write_Log -Message_Type "INFO" -Message "New value for $MySetting is $NewValue"  	
						Write_Log -Message_Type "SUCCESS" -Message "The setting has been setted"  												
					}
				Else
					{
						Write_Log -Message_Type "ERROR" -Message "Can not change setting $MySetting (Return code $Change_Return_Code)"  											
					}								
			}	
	}
	

	
# Save BIOS change part	
$Save_BIOS = (gwmi -class Lenovo_SaveBiosSettings -namespace root\wmi)
If(($Is_BIOS_Password_Protected -eq $True) -and ($Getting_KeyVault_PWD -eq $True))
	{	
		$Execute_Save_Change_Action = $SAVE_BIOS.SaveBiosSettings("$MyPassword,ascii,$Language")			
		$Save_Change_Return_Code = $Execute_Save_Change_Action.return			
		If(($Save_Change_Return_Code) -eq "Success")
			{
				Write_Log -Message_Type "SUCCESS" -Message "BIOS settings have been saved"  																	
			}
		Else
			{
				Write_Log -Message_Type "ERROR" -Message "An issue occured while saving changes - $Save_Change_Return_Code"  																				
			}
	}
Else
	{
		$Execute_Save_Change_Action = $SAVE_BIOS.SaveBiosSettings()	
		$Save_Change_Return_Code = $Execute_Save_Change_Action.return			
		If(($Save_Change_Return_Code) -eq "Success")
			{
				Write_Log -Message_Type "SUCCESS" -Message "BIOS settings have been saved"  																	
			}
		Else
			{
				Write_Log -Message_Type "ERROR" -Message "An issue occured while saving changes - $Save_Change_Return_Code"  																				
			}		
	}		


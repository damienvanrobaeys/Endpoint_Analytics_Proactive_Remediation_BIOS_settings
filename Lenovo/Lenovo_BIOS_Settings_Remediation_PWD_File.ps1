#********************************************************************************************
# Part to fill
#
$CSV_URL = "https://dams.blob.core.windows.net/bios-settings/lenovo_bios_settings.csv" # Path of CSV containing BIOS settings with value to set
$PWD_File_URL = "https://dams.blob.core.windows.net/bios-settings/PWD_File.txt"	
#
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
	
Function Download_Password_File
	{
		Try
			{
				Invoke-WebRequest -Uri $PWD_File_URL -OutFile $Exported_PWD_File		
				Write_Log -Message_Type "SUCCESS" -Message "The password file has been downnloaded"  						
			}
		Catch
			{
				Write_Log -Message_Type "ERROR" -Message "The password file has not been downnloaded"  
				write-output "The password file has not been downnloaded"  
				EXIT 1
			}
	}	

	
$Get_Manufacturer_Info = (gwmi win32_computersystem).Manufacturer
If($Get_Manufacturer_Info -notlike "*lenovo*")	
	{
		Write_Log -Message_Type "ERROR" -Message "Device manufacturer not supported"											
		write-output "Device manufacturer not supported"		
		EXIT 1			
	}	
	
$Exported_CSV = "$env:TEMP\Lenovo_BIOS_Settings.CSV"
If(test-path $Exported_CSV)
	{
		Write_Log -Message_Type "INFO" -Message "The BIOS Settings CSV exists"  
	}
Else
	{
		Write_Log -Message_Type "INFO" -Message "The BIOS Settings CSV does not exist"  
		$CSV_URL = "https://dams.blob.core.windows.net/bios-settings/lenovo_bios_settings.csv"	
		Invoke-WebRequest -Uri $CSV_URL -OutFile $Exported_CSV		
	}
	
$Exported_PWD_File = "$env:TEMP\PWD_File.txt"
	
# Prepare the CSV to be imported
$Get_CSV_FirstLine = Get-Content $Exported_CSV | Select -First 1
$Get_Delimiter = If($Get_CSV_FirstLine.Split(";").Length -gt 1){";"}Else{","};
Write_Log -Message_Type "INFO" -Message "Delimiter to use is: $Get_Delimiter"  
$Get_CSV_Content = Import-CSV $Exported_CSV  -Delimiter $Get_Delimiter		
Add-Content $Log_File ""	
  
  
$Is_BIOS_Password_Protected = $False 
$IsPasswordSet = (gwmi -Class Lenovo_BiosPasswordSettings -Namespace root\wmi).PasswordState
If(($IsPasswordSet -eq 1) -or ($IsPasswordSet -eq 2) -or ($IsPasswordSet -eq 3))
	{
		Download_Password_File	
		$Is_BIOS_Password_Protected = $True

		If(test-path $Exported_PWD_File)
			{
				[Byte[]] $Encrypt_key = (1..16)			
				$secureString = Get-Content $Exported_PWD_File | ConvertTo-SecureString -Key $Encrypt_key
				$Script:MyPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString))											
			
				If($MyPassword -eq "")
					{
						Write_Log -Message_Type "WARNING" -Message "No password has been sent to the script"  	
						Break
					}
			}						
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
If($Is_BIOS_Password_Protected -eq $True)
	{		
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
				Add-Content $Log_File ""	
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
				Add-Content $Log_File ""	
			}	
	}
	

	
# Save BIOS change part	
$Save_BIOS = (gwmi -class Lenovo_SaveBiosSettings -namespace root\wmi)
If($Is_BIOS_Password_Protected -eq $True)
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


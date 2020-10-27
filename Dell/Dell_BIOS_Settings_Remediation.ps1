$SystemRoot = $env:SystemRoot
$Log_File = "$SystemRoot\Debug\Dell_BIOS_Settings_Remediation.log" 
If(!(test-path $Log_File)){new-item $Log_File -type file -force}

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
	
	
Function Get-DellBIOSProvider
{
    [CmdletBinding()]
    param()		
	If (!(Get-Module DellBIOSProvider -listavailable)) 
		{
			Install-Module DellBIOSProvider -ErrorAction SilentlyContinue
			Write_Log -Message_Type "INFO" -Message "DellBIOSProvider has been installed"  			
		}
	Else
		{
			Import-Module DellBIOSProvider -ErrorAction SilentlyContinue
			Write_Log -Message_Type "INFO" -Message "DellBIOSProvider has been imported"  			
		}
}

Get-DellBIOSProvider 	
  
$Exported_CSV = "$env:TEMP\BIOS_Settings.CSV"
$Exported_PWD_File = "$env:TEMP\PWD_File.txt"

If(test-path $Exported_CSV)
	{
		Write_Log -Message_Type "INFO" -Message "The BIOS Settings CSV exists"  
	}
Else
	{
		Write_Log -Message_Type "INFO" -Message "The BIOS Settings CSV does not exist"  
		$CSV_URL = "https://dams.blob.core.windows.net/bios-settings/dell_bios_settings.csv"	
		Invoke-WebRequest -Uri $CSV_URL -OutFile $Exported_CSV		
	}
	
$Get_CSV_FirstLine = Get-Content $Exported_CSV | Select -First 1
$Get_Delimiter = If($Get_CSV_FirstLine.Split(";").Length -gt 1){";"}Else{","};
Write_Log -Message_Type "INFO" -Message "Delimiter to use is: $Get_Delimiter"  
$Get_CSV_Content = Import-CSV $Exported_CSV  -Delimiter $Get_Delimiter		
Add-Content $Log_File ""

Function Download_Password_File
	{
		$PWD_File_URL = "https://dams.blob.core.windows.net/bios-settings/Dell_PWD_File.txt"	
		Try
			{
				Invoke-WebRequest -Uri $PWD_File_URL -OutFile $Exported_PWD_File		
				Write_Log -Message_Type "SUCCESS" -Message "The password file has been downnloaded"  						
			}
		Catch
			{
				Write_Log -Message_Type "ERROR" -Message "The password file has not been downnloaded"  
			}
	}

$Need_Password = $False
$IsPasswordSet = (Get-Item -Path DellSmbios:\Security\IsAdminPasswordSet).currentvalue 
If($IsPasswordSet -eq $true)	
	{
		Write_Log -Message_Type "INFO" -Message "A password is configured"  
		Download_Password_File
		$Need_Password = $True
		
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
	
Add-Content $Log_File ""	

$Dell_BIOS = get-childitem -path DellSmbios:\ | foreach {
get-childitem -path @("DellSmbios:\" + $_.Category)  | select-object attribute, currentvalue, possiblevalues, PSChildName}   

ForEach($Settings in $Get_CSV_Content)
	{
		$MySetting = $Settings.Setting
		$NewValue = $Settings.Value		
		
		Write_Log -Message_Type "INFO" -Message "Change to do: $MySetting - $NewValue"  
	
		ForEach($Current_Setting in $Dell_BIOS | Where {$_.attribute -eq $MySetting})
			{
				$Attribute = $Current_Setting.attribute
				$Setting_Cat = $Current_Setting.PSChildName
				$Setting_Current_Value = $Current_Setting.CurrentValue

				If (($IsPasswordSet -eq $true))
					{   
						& Set-Item -Path Dellsmbios:\$Setting_Cat\$Attribute -Value $NewValue -Password $MyPassword -ea silentlycontinue -errorvariable bios_error
						Write_Log -Message_Type "INFO" -Message "Current value for $Attribute is $Setting_Current_Value"

						If($bios_error -ne $null)
							{
								Write_Log -Message_Type "ERROR" -Message "Can not change setting $Attribute"  
								Write_Log -Message_Type "ERROR" -Message "Error: $bios_error"  									
							}
						Else
							{
								Write_Log -Message_Type "SUCCESS" -Message "New value for $Attribute is $NewValue"
							}
					}
				Else
					{
						& Set-Item -Path Dellsmbios:\$Setting_Cat\$Attribute -Value $NewValue -ea silentlycontinue -errorvariable bios_error
						Write_Log -Message_Type "INFO" -Message "Current value for $Attribute is $Setting_Current_Value"

						If($bios_error -ne $null)
							{
								Write_Log -Message_Type "ERROR" -Message "Can not change setting $Attribute"  
								Write_Log -Message_Type "ERROR" -Message "Error: $bios_error"  									
							}
						Else
							{
								Write_Log -Message_Type "SUCCESS" -Message "New value for $Attribute is $NewValue"
							}
					}        
			}
		write-host ""
		Add-Content $Log_File ""
	}	

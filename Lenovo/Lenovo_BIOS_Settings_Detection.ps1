$SystemRoot = $env:SystemRoot
$Log_File = "$SystemRoot\Debug\Lenovo_BIOS_Settings_Detection.log" 
If(!(test-path $Log_File)){new-item $Log_File -type file -force}

Function Write_Log
	{
	param(
	$Message_Type, 
	$Message
	)
		$MyDate = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
		Add-Content $Log_File  "$MyDate - $Message_Type : $Message" 
		# write-host  "$MyDate - $Message_Type : $Message"
	} 
  	
	
$Script:Get_BIOS_Settings = gwmi -class Lenovo_BiosSetting -namespace root\wmi  | select-object currentsetting | Where-Object {$_.CurrentSetting -ne ""} |
select-object @{label = "Setting"; expression = {$_.currentsetting.split(",")[0]}} , 
@{label = "Value"; expression = {$_.currentsetting.split(",*;[")[1]}} 

$CSV_URL = "https://dams.blob.core.windows.net/bios-settings/lenovo_bios_settings.csv"	

$Exported_CSV = "$env:TEMP\BIOS_Settings.CSV"

Try
	{
		Invoke-WebRequest -Uri $CSV_URL -OutFile $Exported_CSV
		Write_Log -Message_Type "SUCCESS" -Message "BIOS settings CSV has been downloaded in $Exported_CSV"  
	}
Catch
	{
		Write_Log -Message_Type "ERROR" -Message "BIOS settings CSV has not been downloaded"  
	}									

$Get_CSV_FirstLine = Get-Content $Exported_CSV | Select -First 1
$Get_Delimiter = If($Get_CSV_FirstLine.Split(";").Length -gt 1){";"}Else{","};
Write_Log -Message_Type "INFO" -Message "Delimiter to use is: $Get_Delimiter"  

$Get_CSV_Content = Import-CSV $Exported_CSV  -Delimiter $Get_Delimiter				
		
$Script:Bad_Value_Count = 0							
# $Get_Current_Settings = Get_Dell_BIOS_Settings | select Setting, Value
$Get_Current_Settings = $Get_BIOS_Settings | select Setting, Value
ForEach($CSV_Settings in $Get_CSV_Content)
	{
		$CSV_Setting_Name = $CSV_Settings.Setting
		$CSV_Setting_Value = $CSV_Settings.Value
			
		ForEach($Current_Setting in $Get_BIOS_Settings | Where{$_.Setting -eq $CSV_Setting_Name})
			{
				Write_Log -Message_Type "INFO" -Message "Analyzing setting $CSV_Setting_Name"  
			
				$Current_Setting_Name = $Current_Setting.Setting
				$Current_Setting_Value = $Current_Setting.Value
				# If($Current_Setting_Name -eq $CSV_Setting_Name)
					# {
				If($CSV_Setting_Value -ne $Current_Setting_Value)
					{
						Write_Log -Message_Type "INFO" -Message "The setting $Current_Setting_Name is not conform"
						Write_Log -Message_Type "INFO" -Message "Current setting value is: $Current_Setting_Value"
						Write_Log -Message_Type "INFO" -Message "Setting should has value: $CSV_Setting_Value"
						$Script:Bad_Value_Count = $Bad_Value_Count + 1								
					}
				Else
					{
						Write_Log -Message_Type "INFO" -Message "The setting $Current_Setting_Name is conform"
					}
					# }
				# Else
					# {
						# Write_Log -Message_Type "INFO" -Message "Can not find the setting $CSV_Setting_Name"					
					# }
				Break
			}
		Add-Content $Log_File ""
		write-host ""
	}	

If($Bad_Value_Count -gt 0)
	{
		Exit 1	
	}	
Else
	{
		Exit 0	
	}
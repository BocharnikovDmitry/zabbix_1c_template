$ITEM = [string]$args[0]
$VER = [string]$args[1]
$CLUSTERID = [string]$args[2]

# Script: zabbix_1c_job
# Author: Бочарников Дмитрий
# Description: Скрипт собирает информацию с 1С сервера с помощью утилит RAC.exe
#
# USAGE:
#
#   as a script:    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\zabbix_1c_job.ps1" <ITEM><VER><CLUSTERID> 
#   as an item:     1csrv[<ITEM><VER><CLUSTERID>]
#   Доступные ITEMS (Switch) :
# - DiscoveryCluster - находит все кластеры на данном хосте
# - 1CV8 - находит все сессии с толстыми клиентами на заданном кластере
# - 1CV8C - находит все сессии с тонкими клиентами на заданном кластере
# - WebClient - находит все сессии с WEB клиентами на заданном кластере
# - Designer - находит все сессии с конфигуратором на заданном кластере
# - BackgroundJob - находит все фоновые задания на заданном кластере
# - InfoBase - выводит информацию о БД на кластере
# - licenses - находит количество выданных сервером лицензий.
#   Лицензии вычислялись опытным путем. Возможно логика охватывает не все ситуации
#   1. Если хост выдавший лицензию тот который мы мониторим - значит эта лицензия считается, ее выдал именно этот сервер (rmngr-address), остальные не считаются
#   2. Если на сервере через клиентскую часть запустить 1С то одна лицензия будет занята, считаем и ее (host)
#   3. Все остальные не считаем как занятые

################# ОПИСАНИЕ ФУНКЦИЙ #################
function PrepareConvertTo-Json{
}

function ConvertTo-ZabbixDiscoveryJson([array]$arrClusters)
{
   $out = @()
   $Element = @{ }	
   if ($arrClusters.Count -gt 0) {
		$arrClusters | ForEach-Object {
            $_ = $_ -replace '"',""
            $Property = ""
            $Value = $null
           
            if ( $_ -match "^([-a-zA-Z0-9]*)\s*:" ) {
                $Property = $Matches[1]
    		}
            if ($_ -match ":\s*([-a-zA-Z0-9\s_]*)$" ) {
                if  ( $Matches[1] -notmatch "^\d+$" ) {
                    $Value = [string]$Matches[1]
                } 
                else {
                    $Value = [int]$Matches[1]
                }
    		}
            if ($Property) {
                $Element.Add("{#$($Property.ToUpper())}",$Value)
   			}
            if (!$_) {
                 $out += $Element
                 $Element = @{ }
            }
		}
	}
    @{ 'data' = $out } | ConvertTo-Json -Compress
}

function Get1CLic([array]$arrClusters) {
  $lic = 0
   $isCountMng = $true
   $out = @()
   $Element = @{ }	
   if ($arrClusters.Count -gt 0) {
		$arrClusters | ForEach-Object {
            $_ = $_ -replace '"',""
            $Property = ""
            $Value = $null
           
            if ( $_ -match "^([-a-zA-Z0-9]*)\s*:" ) {
                $Property = $Matches[1]
                $Property = $Property -replace '-',""
    		}
            if ($_ -match ":\s*([-a-zA-Z0-9\s_]*)$" ) {
                if  ( $Matches[1] -notmatch "^\d+$" ) {
                    $Value = [string]$Matches[1]
                } 
                else {
                    $Value = [int]$Matches[1]
                }
    		}
            if ($Property) {
                $Element.Add("$($Property.ToUpper())",$Value)
   			}
            if (!$_) {
                 $out += $Element
                 $Element = @{ }
            }
		}
	}
    $Result = $out | ConvertTo-Json -Compress
    $arrJson = ConvertFrom-Json -InputObject $Result 
    $arrJson | ForEach-Object {
        if ( ($_.RMNGRADDRESS.ToUpper() -eq $CLUSTERID.ToUpper()) -or ( ( $_.HOST.ToUpper().Trim(" ") -eq $CLUSTERID.ToUpper()) -and $isCountMng ) )   {
            $lic++
            if ( $_.HOST.ToUpper().Trim(" ") -eq $CLUSTERID.ToUpper() ) { 
                $isCountMng = $false 
            }
        }
    }
    $lic
}
################# КОНЕЦ ОПИСАНИЯ ФУНКЦИЙ #################

################# ТОЧКА СТАРТА #################
cls

$Path1C = $env:ProgramFiles+"\1cv8\"+$VER+"\bin\rac.exe"

if ( !(Test-Path $Path1C) ) {
    $strOut = "-- No Find File -- : " + $Path1C
    write-output $strOut
}

switch ($ITEM)
{
    "DiscoveryCluster"
    {
        $Result = & $Path1C cluster list
        ConvertTo-ZabbixDiscoveryJson( $Result )
    }

    "1CV8"
    {
        $Result = &$Path1C session --cluster=$CLUSTERID list 
        ($Result -match "app-id\s*:\s*"+$ITEM+"\s*$").Count
    }

    "1CV8C"
    {
        $Result = &$Path1C session --cluster=$CLUSTERID list 
        ($Result -match "app-id\s*:\s*"+$ITEM+"\s*$").Count
    }
    
    "WebClient"
    {
        $Result = &$Path1C session --cluster=$CLUSTERID list 
        ($Result -match "app-id\s*:\s*"+$ITEM+"\s*$").Count
    }
    
    "BackgroundJob"
    {
        $Result = &$Path1C session --cluster=$CLUSTERID list 
        ($Result -match "app-id\s*:\s*"+$ITEM+"\s*$").Count
    }

    "Designer"
    {
        $Result = &$Path1C session --cluster=$CLUSTERID list 
        ($Result -match "app-id\s*:\s*"+$ITEM+"\s*$").Count
    }
    
    "licenses"
    {
        $lic = 0
        $arrClusters = &$Path1C cluster list
        $arrClusters | ForEach-Object {
            if ($_ -match "^cluster\s*:\s*(.*)\s*") {
                $ID = $Matches[1]
                $Result = &$Path1C session --cluster=$ID list --licenses
                if ($Result) {
                    $lic += Get1CLic($Result)
                }
            }
        }
        $lic
    }

    "InfoBase" {
        $strOut = ""
        $out = ""
        $UID = ""
        $NameDB = ""
        $DescrDB = ""
        
        $Result = &$Path1C infobase --cluster=$CLUSTERID summary list
        $Result | ForEach-Object {
            if ($_ -match "^(.*)\s*:\s*(.*)\s*") {
                $Prop = $Matches[1]
                $Val = $Matches[2]
                switch ($Prop.Trim()) {
                    "infobase"
                    {
                        $UID = $Val.Trim()
                    }

                    "name"
                    {
                        $NameDB = $Val.Trim()
                    }

                    "descr"
                    {
                        $DescrDB = $Val.Trim()
                    }
                }
            }
            else
            {
                $strOut += "Base: "+$NameDB
                if ($DescrDB) {$strOut += " - "+$DescrDB}
                $strOut += "; UID: "+$UID
                $strOut
                $UID = ""
                $NameDB = ""
                $DescrDB = ""
                $strOut = "" 
                $out += $strOut + [System.Environment]::NewLine
            }
        }
        $out
     }
    
    default
	{
		write-output "-- ERROR -- : Need an option !"
	}
}
 
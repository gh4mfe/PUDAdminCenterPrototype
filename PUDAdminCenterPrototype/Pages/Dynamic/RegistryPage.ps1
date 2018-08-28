$RegistryPageContent = {
    param($RemoteHost)

    $PUDRSSyncHT = $global:PUDRSSyncHT

    # Load PUDAdminCenter Module Functions Within ScriptBlock
    $ThisModuleFunctionsStringArray | Where-Object {$_ -ne $null} | foreach {Invoke-Expression $_ -ErrorAction SilentlyContinue}

    # For some reason, scriptblocks defined earlier can't be used directly here. They need to be a different objects before
    # they actually behave as expected. Not sure why.
    #$RecreatedDisconnectedPageContent = [scriptblock]::Create($DisconnectedPageContentString)

    $RHostIP = $($PUDRSSyncHT.RemoteHostList | Where-Object {$_.HostName -eq $RemoteHost}).IPAddressList[0]

    #region >> Ensure $RemoteHost is Valid

    if ($PUDRSSyncHT.RemoteHostList.HostName -notcontains $RemoteHost) {
        $ErrorText = "The Remote Host $($RemoteHost.ToUpper()) is not a valid Host Name!"
    }

    if ($ErrorText) {
        New-UDRow -Columns {
            New-UDColumn -Size 4 -Content {
                New-UDHeading -Text ""
            }
            New-UDColumn -Size 4 -Content {
                New-UDHeading -Text $ErrorText -Size 6
            }
            New-UDColumn -Size 4 -Content {
                New-UDHeading -Text ""
            }
        }
    }

    # If $RemoteHost isn't valid, don't load anything else
    if ($ErrorText) {
        return
    }

    #endregion >> Ensure $RemoteHost is Valid

    #region >> Loading Indicator

    New-UDRow -Columns {
        New-UDColumn -Endpoint {
            $Session:RegistryPageLoadingTracker = [System.Collections.ArrayList]::new()
        }
        New-UDColumn -AutoRefresh -RefreshInterval 5 -Endpoint {
            if ($Session:RegistryPageLoadingTracker -notcontains "FinishedLoading") {
                New-UDHeading -Text "Loading...Please wait..." -Size 5
                New-UDPreloader -Size small
            }
        }
    }

    #endregion >> Loading Indicator

    # Master Endpoint - All content will be within this Endpoint so that we can reference $Cache: and $Session: scope variables
    New-UDColumn -Size 12 -Endpoint {
        #region >> Ensure We Are Connected / Can Connect to $RemoteHost

        $PUDRSSyncHT = $global:PUDRSSyncHT

        # Load PUDAdminCenter Module Functions Within ScriptBlock
        $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -ne $null} | foreach {Invoke-Expression $_ -ErrorAction SilentlyContinue}

        # For some reason, scriptblocks defined earlier can't be used directly here. They need to be a different objects before
        # they actually behave as expected. Not sure why.
        #$RecreatedDisconnectedPageContent = [scriptblock]::Create($DisconnectedPageContentString)

        $RHostIP = $($PUDRSSyncHT.RemoteHostList | Where-Object {$_.HostName -eq $RemoteHost}).IPAddressList[0]

        if ($Session:CredentialHT.$RemoteHost.PSRemotingCreds -eq $null) {
            Invoke-UDRedirect -Url "/Disconnected/$RemoteHost"
        }

        try {
            $ConnectionStatus = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {"Connected"}
        }
        catch {
            $ConnectionStatus = "Disconnected"
        }

        # If we're not connected to $RemoteHost, don't load anything else
        if ($ConnectionStatus -ne "Connected") {
            #Invoke-Command -ScriptBlock $RecreatedDisconnectedPageContent -ArgumentList $RemoteHost
            Invoke-UDRedirect -Url "/Disconnected/$RemoteHost"
        }
        else {
            New-UDRow -EndPoint {
                New-UDColumn -Size 3 -Content {
                    New-UDHeading -Text ""
                }
                New-UDColumn -Size 6 -Endpoint {
                    New-UDTable -Id "TrackingTable" -Headers @("RemoteHost","Status","DateTime") -AutoRefresh -RefreshInterval 2 -Endpoint {
                        $PUDRSSyncHT = $global:PUDRSSyncHT

                        # Load PUDAdminCenter Module Functions Within ScriptBlock
                        $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -ne $null} | foreach {Invoke-Expression $_ -ErrorAction SilentlyContinue}
                        
                        $RHostIP = $($PUDRSSyncHT.RemoteHostList | Where-Object {$_.HostName -eq $RemoteHost}).IPAddressList[0]

                        $WSMan5985Available = $(TestPort -HostName $RHostIP -Port 5985).Open
                        $WSMan5986Available = $(TestPort -HostName $RHostIP -Port 5986).Open

                        if ($WSMan5985Available -or $WSMan5986Available) {
                            $TableData = @{
                                RemoteHost      = $RemoteHost.ToUpper()
                                Status          = "Connected"
                            }
                        }
                        else {
                            Invoke-UDRedirect -Url "/Disconnected/$RemoteHost"
                        }

                        # SUPER IMPORTANT NOTE: ALL Real-Time Enpoints on the Page reference LiveOutputClone!
                        if ($PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataRSInfo.LiveOutput.Count -gt 0) {
                            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataTracker.Previous -eq $null) {
                                $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataTracker.Previous = $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataRSInfo.LiveOutput.Clone()
                            }
                            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataTracker.Current.Count -gt 0) {
                                $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataTracker.Previous = $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataTracker.Current.Clone()
                            }
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataTracker.Current = $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataRSInfo.LiveOutput.Clone()
                        }

                        $TableData.Add("DateTime",$(Get-Date -Format MM-dd-yy_hh:mm:sstt))

                        [PSCustomObject]$TableData | Out-UDTableData -Property @("RemoteHost","Status","DateTime")
                    }
                }
                New-UDColumn -Size 3 -Content {
                    New-UDHeading -Text ""
                }
            }
        }

        #endregion >> Ensure We Are Connected / Can Connect to $RemoteHost

        #region >> Gather Some Initial Info From $RemoteHost
        if (!$Session:HKLMChildKeys -or !$Session:HKCUChildKeys -or !$Session:HKCRChildKeys -or !$Session:HKUChildKeys -or !$Session:HKCCChildKeys) {
            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
            $StaticInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                Invoke-Expression $using:GetRegistrySubKeysFunc
                Invoke-Expression $using:GetRegistryValuesFunc

                # HKLM and HKCU are already defined by default...
                New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT
                New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS
                New-PSDrive -Name HKCC -PSProvider Registry -Root HKEY_CURRENT_CONFIG

                <#
                'Get-RegistryValues -path HKLM:\SYSTEM\CurrentControlSet\Control\Network\Connections' Output Example
                Name                 type data
                ----                 ---- ----
                ClassManagers MultiString {{B4C8DF59-D16F-4042-80B7-3557A254B7C5}, {BA126AD3-2166-11D1-B1D0-00805FC1270E}, {BA126AD5-2166-11D1-B1D0-00805FC1270E}, {BA126ADD-2166-11D1-B1D0-00805FC1270E}}


                'Get-RegistrySubKeys -path HKLM:\SYSTEM\CurrentControlSet\Control\Network' Output Example
                Name                                   Path                                                                                                                                   childCount
                ----                                   ----                                                                                                                                   ----------
                {4D36E972-E325-11CE-BFC1-08002BE10318} Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Network\{4D36E972-E325-11CE-BFC1-08002BE10318}          8
                {4d36e973-e325-11ce-bfc1-08002be10318} Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Network\{4d36e973-e325-11ce-bfc1-08002be10318}          1
                {4d36e974-e325-11ce-bfc1-08002be10318} Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Network\{4d36e974-e325-11ce-bfc1-08002be10318}          9
                {4d36e975-e325-11ce-bfc1-08002be10318} Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Network\{4d36e975-e325-11ce-bfc1-08002be10318}         19
                Connections                            Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Network\Connections                                     0
                LightweightCallHandlers                Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Network\LightweightCallHandlers                         2
                NetworkLocationWizard                  Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Network\NetworkLocationWizard                           0
                SharedAccessConnection                 Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Network\SharedAccessConnection                          0
                #>

                $HKLMChildKeys = Get-RegistrySubKeys -path "HKLM:\" -ErrorAction SilentlyContinue
                $HKLMValues = Get-RegistryValues -path "HKLM:\" -ErrorAction SilentlyContinue
                $HKLMCurrentDir = "HKLM:\"

                $HKCUChildKeys = Get-RegistrySubKeys -path "HKCU:\" -ErrorAction SilentlyContinue
                $HKCUValues = Get-RegistryValues -path "HKCU:\" -ErrorAction SilentlyContinue
                $HKCUCurrentDir = "HKCU:\"

                $HKCRChildKeys = Get-RegistrySubKeys -path "HKCR:\" -ErrorAction SilentlyContinue
                $HKCRValues = Get-RegistryValues -path "HKCR:\" -ErrorAction SilentlyContinue
                $HKCRCurrentDir = "HKCR:\"
                
                $HKUChildKeys = Get-RegistrySubKeys -path "HKU:\" -ErrorAction SilentlyContinue
                $HKUValues = Get-RegistryValues -path "HKU:\" -ErrorAction SilentlyContinue
                $HKUCurrentDir = "HKU:\"
                
                $HKCCChildKeys = Get-RegistrySubKeys -path "HKCC:\" -ErrorAction SilentlyContinue
                $HKCCValues = Get-RegistryValues -path "HKCC:\" -ErrorAction SilentlyContinue
                $HKCCCurrentDir = "HKCC:\"

                [pscustomobject]@{
                    HKLMChildKeys   = $HKLMChildKeys
                    HKLMValues      = $HKLMValues
                    HKLMCurrentDir  = $HKLMCurrentDir
                    HKCUChildKeys   = $HKCUChildKeys
                    HKCUValues      = $HKCUValues
                    HKCUCurrentDir  = $HKCUCurrentDir
                    HKCRChildKeys   = $HKCRChildKeys
                    HKCRValues      = $HKCRValues
                    HKCRCurrentDir  = $HKCRCurrentDir
                    HKUChildKeys    = $HKUChildKeys
                    HKUValues       = $HKUValues
                    HKUCurrentDir   = $HKUCurrentDir
                    HKCCChildKeys   = $HKCCChildKeys
                    HKCCValues      = $HKCCValues
                    HKCCCurrentDir  = $HKCCCurrentDir
                }
            }
            $Session:HKLMChildKeys = $StaticInfo.HKLMChildKeys | Where-Object {$_.Name}
            $Session:HKLMValues = $StaticInfo.HKLMValues
            $Session:HKLMCurrentDir = $StaticInfo.HKLMCurrentDir
            $Session:HKCUChildKeys = $StaticInfo.HKCUChildKeys | Where-Object {$_.Name}
            $Session:HKCUValues = $StaticInfo.HKCUValues
            $Session:HKCUCurrentDir = $StaticInfo.HKCUCurrentDir
            $Session:HKCRChildKeys = $StaticInfo.HKCRChildKeys | Where-Object {$_.Name}
            $Session:HKCRValues = $StaticInfo.HKCRValues
            $Session:HKCRCurrentDir = $StaticInfo.HKCRCurrentDir
            $Session:HKUChildKeys = $StaticInfo.HKUChildKeys | Where-Object {$_.Name}
            $Session:HKUValues = $StaticInfo.HKUValues
            $Session:HKUCurrentDir = $StaticInfo.HKUCurrentDir
            $Session:HKCCChildKeys  = $StaticInfo.HKCCChildKeys | Where-Object {$_.Name}
            $Session:HKCCValues = $StaticInfo.HKCCValues
            $Session:HKCCCurrentDir = $StaticInfo.HKCCCurrentDir
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKLMChildKeys") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKLMChildKeys",$($StaticInfo.HKLMChildKeys | Where-Object {$_.Name}))
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMChildKeys = $StaticInfo.HKLMChildKeys | Where-Object {$_.Name}
            }
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKLMValues") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKLMValues",$StaticInfo.HKLMValues)
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMValues = $StaticInfo.HKLMValues
            }
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKLMCurrentDir") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKLMCurrentDir",$StaticInfo.HKLMCurrentDir)
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMCurrentDir = $StaticInfo.HKLMCurrentDir
            }

            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKCUChildKeys") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKCUChildKeys",$($StaticInfo.HKCUChildKeys | Where-Object {$_.Name}))
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCUChildKeys = $StaticInfo.HKCUChildKeys | Where-Object {$_.Name}
            }
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKCUValues") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKCUValues",$StaticInfo.HKCUValues)
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCUValues = $StaticInfo.HKCUValues
            }
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKCUCurrentDir") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKCUCurrentDir",$StaticInfo.HKCUCurrentDir)
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCUCurrentDir = $StaticInfo.HKCUCurrentDir
            }

            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKCRChildKeys") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKCRChildKeys",$($StaticInfo.HKCRChildKeys | Where-Object {$_.Name}))
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCRChildKeys = $StaticInfo.HKCRChildKeys | Where-Object {$_.Name}
            }
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKCRValues") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKCRValues",$StaticInfo.HKCRValues)
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCRValues = $StaticInfo.HKCRValues
            }
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKCRCurrentDir") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKCRCurrentDir",$StaticInfo.HKCRCurrentDir)
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCRCurrentDir = $StaticInfo.HKCRCurrentDir
            }

            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKUChildKeys") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKUChildKeys",$($StaticInfo.HKUChildKeys | Where-Object {$_.Name}))
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKUChildKeys = $StaticInfo.HKUChildKeys | Where-Object {$_.Name}
            }
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKUValues") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKUValues",$StaticInfo.HKUValues)
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKUValues = $StaticInfo.HKUValues
            }
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKUCurrentDir") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKUCurrentDir",$StaticInfo.HKUCurrentDir)
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKUCurrentDir = $StaticInfo.HKUCurrentDir
            }

            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKCCChildKeys") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKCCChildKeys",$($StaticInfo.HKCCChildKeys | Where-Object {$_.Name}))
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCCChildKeys = $StaticInfo.HKCCChildKeys | Where-Object {$_.Name}
            }
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKCCValues") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKCCValues",$StaticInfo.HKCCValues)
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCCValues = $StaticInfo.HKCCValues
            }
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.Keys -notcontains "HKCCCurrentDir") {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.Add("HKCCCurrentDir",$StaticInfo.HKCCCurrentDir)
            }
            else {
                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCCCurrentDir = $StaticInfo.HKCCCurrentDir
            }
        }

        #endregion >> Gather Some Initial Info From $RemoteHost

        #region >> Page Name and Horizontal Nav

        New-UDRow -Endpoint {
            New-UDColumn -Content {
                New-UDHeading -Text "Registry (In Progress)" -Size 3
                New-UDHeading -Text "NOTE: Domain Group Policy trumps controls with an asterisk (*)" -Size 6
            }
        }
        New-UDRow -Endpoint {
            New-UDColumn -Size 12 -Content {
                New-UDCollapsible -Items {
                    New-UDCollapsibleItem -Title "More Tools" -Icon laptop -Active -Endpoint {
                        New-UDRow -Endpoint {
                            foreach ($ToolName in $($Cache:DynamicPages | Where-Object {$_ -notmatch "PSRemotingCreds|ToolSelect"})) {
                                New-UDColumn -Endpoint {
                                    New-UDLink -Text $ToolName -Url "/$ToolName/$RemoteHost" -Icon dashboard
                                }
                            }
                            #New-UDCard -Links $Links
                        }
                    }
                }
            }
        }

        #endregion >> Page Name and Horizontal Nav

        #region >> Setup LiveData

        <#
        New-UDColumn -Endpoint {
            $PUDRSSyncHT = $global:PUDRSSyncHT

            $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -ne $null} | foreach {Invoke-Expression $_ -ErrorAction SilentlyContinue}

            $RHostIP = $($PUDRSSyncHT.RemoteHostList | Where-Object {$_.HostName -eq $RemoteHost}).IPAddressList[0]

            # Remove Existing Runspace for LiveDataRSInfo if it exists as well as the PSSession Runspace within
            if ($PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataRSInfo -ne $null) {
                $PSSessionRunspacePrep = @(
                    Get-Runspace | Where-Object {
                        $_.RunspaceIsRemote -and
                        $_.Id -gt $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataRSInfo.ThisRunspace.Id -and
                        $_.OriginalConnectionInfo.ComputerName -eq $RHostIP
                    }
                )
                if ($PSSessionRunspacePrep.Count -gt 0) {
                    $PSSessionRunspace = $($PSSessionRunspacePrep | Sort-Object -Property Id)[0]
                }
                $PSSessionRunspace.Dispose()
                $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataRSInfo.ThisRunspace.Dispose()
            }

            # Create a Runspace that creates a PSSession to $RemoteHost that is used once every second to re-gather data from $RemoteHost

            # The New-Runspace function handles scope for you behind the scenes, so just pretend that everything within -ScriptBlock {} is in the current scope
            New-Runspace -RunspaceName "Registry$RemoteHost`LiveData" -ScriptBlock {
                $PUDRSSyncHT = $global:PUDRSSyncHT
            
                $LiveDataPSSession = New-PSSession -Name "Registry$RemoteHost`LiveData" -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds

                # Load needed functions in the PSSession
                Invoke-Command -Session $LiveDataPSSession -ScriptBlock {
                    $using:LiveDataFunctionsToLoad | foreach {Invoke-Expression $_}
                }

                $RSLoopCounter = 0

                while ($PUDRSSyncHT) {
                    # $LiveOutput is a special ArrayList created and used by the New-Runspace function that collects output as it occurs
                    # We need to limit the number of elements this ArrayList holds so we don't exhaust memory
                    if ($LiveOutput.Count -gt 1000) {
                        $LiveOutput.RemoveRange(0,800)
                    }

                    # Stream Results to $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataRSInfo.LiveOutput
                    Invoke-Command -Session $LiveDataPSSession -ScriptBlock {
                        # Place most resource intensive operations first

                        # Operations that you only want running once every 30 seconds go within this 'if; block
                        # Adjust the timing as needed with deference to $RemoteHost resource efficiency.
                        if ($using:RSLoopCounter -eq 0 -or $($using:RSLoopCounter % 30) -eq 0) {
                            #@{RootRegistry = Get-ChildItem -Path "$env:SystemDrive\" }
                        }

                        # Operations that you want to run once every second go here
                        @{RootRegistry = Get-ChildItem -Path "$env:SystemDrive\"}

                    } | foreach {$null = $LiveOutput.Add($_)}

                    $RSLoopCounter++

                    [GC]::Collect()

                    Start-Sleep -Seconds 1
                }
            }
            # The New-Runspace function outputs / continually updates a Global Scope variable called $global:RSSyncHash. The results of
            # the Runspace we just created can be found in $global:RSSyncHash's "Registry$RemoteHost`LiveDataResult" Property - which is just
            # the -RunspaceName value plus the word 'Info'. By setting $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataRSInfo equal to
            # $RSSyncHash."Registry$RemoteHost`LiveDataResult", we can now reference $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataRSInfo.LiveOutput
            # to get the latest data from $RemoteHost.
            $PUDRSSyncHT."$RemoteHost`Info".Registry.LiveDataRSInfo = $RSSyncHash."Registry$RemoteHost`LiveDataResult"
        }
        #>

        #endregion >> Setup LiveData

        #region >> Controls


        # Static Data Element Example

        New-UDCollapsible -Items {
            New-UDCollapsibleItem -Title "HKEY_LOCAL_MACHINE" -Icon laptop -Endpoint {
                New-UDRow -Endpoint {
                    New-UDColumn -Size 3 -Endpoint {}
                    New-UDColumn -Size 6 -Endpoint {
                        New-UDElement -Id "CurrentHKLMRootDirTB" -Tag div -EndPoint {
                            <#
                            $RootDirSlashCheck = $Session:HKLMChildKeys[0].Path -split "HKEY_LOCAL_MACHINE\\"
                            $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKLM:"} else {"HKLM:\"}
                            $CurrentDirectory = $Session:HKLMChildKeys[0].Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                            #>
                            New-UDHeading -Text "Current Directory: $($Session:HKLMCurrentDir)" -Size 5
                        }
                        New-UDElement -Id "NewHKLMRootDirTB" -Tag div -EndPoint {
                            New-UDTextbox -Id "NewHKLMRootDirTBProper" -Label "New Directory"
                        }
                        New-UDButton -Text "Explore" -OnClick {
                            $NewRootDirTextBox = Get-UDElement -Id "NewHKLMRootDirTBProper"
                            $FullPathToExplore = $NewRootDirTextBox.Attributes['value']

                            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                Invoke-Expression $using:GetRegistrySubKeysFunc
                                Invoke-Expression $using:GetRegistryValuesFunc

                                $HKLMChildKeys = Get-RegistrySubKeys -path $args[0] -ErrorAction SilentlyContinue
                                $HKLMValues = Get-RegistryValues -path $args[0] -ErrorAction SilentlyContinue
                                $HKLMCurrentDir = $args[0]

                                [pscustomobject]@{
                                    HKLMChildKeys   = $HKLMChildKeys
                                    HKLMValues      = $HKLMValues
                                    HKLMCurrentDir  = $HKLMCurrentDir
                                }
                            } -ArgumentList $FullPathToExplore
                            $Session:HKLMChildKeys = $NewPathInfo.HKLMChildKeys | Where-Object {$_.Name}
                            $Session:HKLMValues = $NewPathInfo.HKLMValues
                            $Session:HKLMCurrentDir = $NewPathInfo.HKLMCurrentDir
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMChildKeys = $NewPathInfo.HKLMChildKeys | Where-Object {$_.Name}
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMValues = $NewPathInfo.HKLMValues
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMCurrentDir = $NewPathInfo.HKLMCurrentDir

                            Sync-UDElement -Id "HKLMChildItemsUDGrid"
                            Sync-UDElement -Id "NewHKLMRootDirTB"
                            Sync-UDElement -Id "CurrentHKLMRootDirTB"
                        }

                        New-UDButton -Text "Parent Directory" -OnClick {
                            <#
                            $RootDirSlashCheck = $Session:HKLMChildKeys[0].Path -split "HKEY_LOCAL_MACHINE\\"
                            $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKLM:"} else {"HKLM:\"}
                            $FullPathToExplorePrep = $Session:HKLMChildKeys[0].Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                            #>
                            $FullPathToExplore = if ($($Session:HKLMCurrentDir | Split-Path -Parent) -eq "") {
                                $Session:HKLMCurrentDir
                            }
                            else {
                                $Session:HKLMCurrentDir | Split-Path -Parent
                            }

                            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                Invoke-Expression $using:GetRegistrySubKeysFunc
                                Invoke-Expression $using:GetRegistryValuesFunc

                                $HKLMChildKeys = Get-RegistrySubKeys -path $args[0] -ErrorAction SilentlyContinue
                                $HKLMValues = Get-RegistryValues -path $args[0] -ErrorAction SilentlyContinue
                                $HKLMCurrentDir = $args[0]

                                [pscustomobject]@{
                                    HKLMChildKeys   = $HKLMChildKeys
                                    HKLMValues      = $HKLMValues
                                    HKLMCurrentDir  = $HKLMCurrentDir
                                }
                            } -ArgumentList $FullPathToExplore
                            $Session:HKLMChildKeys = $NewPathInfo.HKLMChildKeys | Where-Object {$_.Name}
                            $Session:HKLMValues = $NewPathInfo.HKLMValues
                            $Session:HKLMCurrentDir = $NewPathInfo.HKLMCurrentDir
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMChildKeys = $NewPathInfo.HKLMChildKeys | Where-Object {$_.Name}
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMValues = $NewPathInfo.HKLMValues
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMCurrentDir = $NewPathInfo.HKLMCurrentDir

                            Sync-UDElement -Id "HKLMChildItemsUDGrid"
                            Sync-UDElement -Id "NewHKLMRootDirTB"
                            Sync-UDElement -Id "CurrentHKLMRootDirTB"
                        }
                    }
                    New-UDColumn -Size 3 -Endpoint {}
                }
                New-UDRow -Endpoint {
                    New-UDColumn -Size 12 -Endpoint {
                        $Session:HKLMUDGridLoadingTracker = [System.Collections.ArrayList]::new()
                            
                        New-UDColumn -AutoRefresh -RefreshInterval 1 -Endpoint {
                            if ($Session:HKLMUDGridLoadingTracker -notcontains "FinishedLoading") {
                                New-UDHeading -Text "Loading...Please wait..." -Size 6
                                New-UDPreloader -Size small
                            }
                        }

                        $RootRegistryProperties = @("Name","Path","Type","Data","ChildCount","Explore")
                        $RootRegistryUDGridSplatParams = @{
                            Id              = "HKLMChildItemsUDGrid"
                            Headers         = $RootRegistryProperties
                            Properties      = $RootRegistryProperties
                            PageSize        = 20
                        }
                        New-UDGrid @RootRegistryUDGridSplatParams -Endpoint {
                            $PUDRSSyncHT = $global:PUDRSSyncHT

                            $RHostIP = $($PUDRSSyncHT.RemoteHostList | Where-Object {$_.HostName -eq $RemoteHost}).IPAddressList[0]

                            # We do NOT want to display UDGridData as values are sent through the pipe because if the user clicks on a
                            # button while the foreach loop is still enumerating, it will throw an error. So, output UDGridData *after*
                            # $HKLMUDGridData is fully defined.
                            $ObjectsToPass = $Session:HKLMChildKeys + $Session:HKLMValues
                            $ObjectsToPass | foreach {
                                if ($_.Name) {
                                    if ($_.Path) {
                                        $RootDirSlashCheck = $_.Path -split "HKEY_LOCAL_MACHINE\\"
                                        $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKLM:"} else {"HKLM:\"}
                                        $PathUpdatedFormat = $_.Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                                    }

                                    #elseif ($_.ChildCount -eq 0 -and $($PathUpdatedFormat -split "\\").Count -gt 2) {'Empty'}
                                    [pscustomobject]@{
                                        Name            = $_.Name
                                        Path            = if ($_.Path) {$PathUpdatedFormat} else {$null}
                                        Type            = if ($_.Type) {$_.Type.ToString()} else {"Key"}
                                        Data            = if ($_.Data) {$_.Data -join ", "} else {$null}
                                        ChildCount      = if ($_.ChildCount) {$_.ChildCount} else {$null}
                                        Explore         = if (!$_.Path) {'-'} else {
                                            New-UDButton -Text "Explore" -OnClick {
                                                #$NewRootDirTextBox = Get-UDElement -Id "NewRootDirTB"
                                                $FullPathToExplore = $PathUpdatedFormat

                                                $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                                                $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                                                $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                                    Invoke-Expression $using:GetRegistrySubKeysFunc
                                                    Invoke-Expression $using:GetRegistryValuesFunc

                                                    $HKLMChildKeys = Get-RegistrySubKeys -path $args[0] -ErrorAction SilentlyContinue
                                                    $HKLMValues = Get-RegistryValues -path $args[0] -ErrorAction SilentlyContinue
                                                    $HKLMCurrentDir = $args[0]

                                                    [pscustomobject]@{
                                                        HKLMChildKeys   = $HKLMChildKeys
                                                        HKLMValues      = $HKLMValues
                                                        HKLMCurrentDir  = $HKLMCurrentDir
                                                    }
                                                } -ArgumentList $FullPathToExplore
                                                $Session:HKLMChildKeys = $NewPathInfo.HKLMChildKeys | Where-Object {$_.Name}
                                                $Session:HKLMValues = $NewPathInfo.HKLMValues
                                                $Session:HKLMCurrentDir = $NewPathInfo.HKLMCurrentDir
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMChildKeys = $NewPathInfo.HKLMChildKeys | Where-Object {$_.Name}
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMValues = $NewPathInfo.HKLMValues
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKLMCurrentDir = $NewPathInfo.HKLMCurrentDir

                                                Sync-UDElement -Id "HKLMChildItemsUDGrid"
                                                Sync-UDElement -Id "NewHKLMRootDirTB"
                                                Sync-UDElement -Id "CurrentHKLMRootDirTB"
                                            }
                                        }
                                    }
                                }
                            } | Out-UDGridData

                            $null = $Session:HKLMUDGridLoadingTracker.Add("FinishedLoading")
                        }
                    }
                }
            }
        }

        New-UDCollapsible -Items {
            New-UDCollapsibleItem -Title "HKEY_CURRENT_USER" -Icon laptop -Endpoint {
                New-UDRow -Endpoint {
                    New-UDColumn -Size 3 -Endpoint {}
                    New-UDColumn -Size 6 -Endpoint {
                        New-UDElement -Id "CurrentHKCURootDirTB" -Tag div -EndPoint {
                            $RootDirSlashCheck = $Session:HKCUChildKeys[0].Path -split "HKEY_CURRENT_USER\\"
                            $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKCU:"} else {"HKCU:\"}
                            $CurrentDirectory = $Session:HKCUChildKeys[0].Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                            New-UDHeading -Text "Current Directory: $($CurrentDirectory | Split-Path -Parent)" -Size 5
                        }
                        New-UDElement -Id "NewHKCURootDirTB" -Tag div -EndPoint {
                            New-UDTextbox -Id "NewHKCURootDirTBProper" -Label "New Directory"
                        }
                        New-UDButton -Text "Explore" -OnClick {
                            $NewRootDirTextBox = Get-UDElement -Id "NewHKCURootDirTBProper"
                            $FullPathToExplore = $NewRootDirTextBox.Attributes['value']

                            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                Invoke-Expression $using:GetRegistrySubKeysFunc
                                Invoke-Expression $using:GetRegistryValuesFunc

                                $HKCUChildKeys = Get-RegistrySubKeys -path "HKCU:\" -ErrorAction SilentlyContinue
                                $HKCUValues = Get-RegistryValues -path "HKCU:\" -ErrorAction SilentlyContinue

                                [pscustomobject]@{
                                    HKCUChildKeys   = $HKCUChildKeys
                                    HKCUValues      = $HKCUValues
                                }
                            } -ArgumentList $FullPathToExplore
                            $Session:HKCUChildKeys = $StaticInfo.HKCUChildKeys | Where-Object {$_.Name}
                            $Session:HKCUValues = $StaticInfo.HKCUValues
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCUChildKeys = $StaticInfo.HKCUChildKeys | Where-Object {$_.Name}
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCUValues = $StaticInfo.HKCUValues

                            Sync-UDElement -Id "HKCUChildItemsUDGrid"
                            Sync-UDElement -Id "NewHKCURootDirTB"
                            Sync-UDElement -Id "CurrentHKCURootDirTB"
                        }

                        New-UDButton -Text "Parent Directory" -OnClick {
                            $RootDirSlashCheck = $Session:HKCUChildKeys[0].Path -split "HKEY_CURRENT_USER\\"
                            $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKCU:"} else {"HKCU:\"}
                            $FullPathToExplorePrep = $Session:HKCUChildKeys[0].Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                            $FullPathToExplore = if ($($($FullPathToExplorePrep | Split-Path -Parent) | Split-Path -Parent) -eq "") {
                                $FullPathToExplorePrep | Split-Path -Parent
                            }
                            else {
                                $($FullPathToExplorePrep | Split-Path -Parent) | Split-Path -Parent
                            }

                            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                Invoke-Expression $using:GetRegistrySubKeysFunc
                                Invoke-Expression $using:GetRegistryValuesFunc

                                $HKCUChildKeys = Get-RegistrySubKeys -path "HKCU:\" -ErrorAction SilentlyContinue
                                $HKCUValues = Get-RegistryValues -path "HKCU:\" -ErrorAction SilentlyContinue

                                [pscustomobject]@{
                                    HKCUChildKeys   = $HKCUChildKeys
                                    HKCUValues      = $HKCUValues
                                }
                            } -ArgumentList $FullPathToExplore
                            $Session:HKCUChildKeys = $StaticInfo.HKCUChildKeys | Where-Object {$_.Name}
                            $Session:HKCUValues = $StaticInfo.HKCUValues
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCUChildKeys = $StaticInfo.HKCUChildKeys | Where-Object {$_.Name}
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCUValues = $StaticInfo.HKCUValues

                            Sync-UDElement -Id "HKCUChildItemsUDGrid"
                            Sync-UDElement -Id "NewHKCURootDirTB"
                            Sync-UDElement -Id "CurrentHKCURootDirTB"
                        }
                    }
                    New-UDColumn -Size 3 -Endpoint {}
                }
                New-UDRow -Endpoint {
                    New-UDColumn -Size 12 -Endpoint {
                        $RootRegistryProperties = @("Name","Path","Type","Data","ChildCount","Explore")
                        $RootRegistryUDGridSplatParams = @{
                            Id              = "HKCUChildItemsUDGrid"
                            Headers         = $RootRegistryProperties
                            Properties      = $RootRegistryProperties
                            PageSize        = 20
                        }
                        New-UDGrid @RootRegistryUDGridSplatParams -Endpoint {
                            $PUDRSSyncHT = $global:PUDRSSyncHT

                            $RHostIP = $($PUDRSSyncHT.RemoteHostList | Where-Object {$_.HostName -eq $RemoteHost}).IPAddressList[0]

                            $($Session:HKCUChildKeys + $Session:HKCUValues) | foreach {
                                if ($_.Name) {
                                    if ($_.Path) {
                                        $RootDirSlashCheck = $_.Path -split "HKEY_CURRENT_USER\\"
                                        $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKCU:"} else {"HKCU:\"}
                                        $PathUpdatedFormat = $_.Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                                    }

                                    #elseif ($_.ChildCount -eq 0 -and $($PathUpdatedFormat -split "\\").Count -gt 2) {'Empty'}
                                    [pscustomobject]@{
                                        Name            = $_.Name
                                        Path            = if ($_.Path) {$PathUpdatedFormat} else {$null}
                                        Type            = if ($_.Type) {$_.Type.ToString()} else {"Key"}
                                        Data            = if ($_.Data) {$_.Data -join ", "} else {$null}
                                        ChildCount      = if ($_.ChildCount) {$_.ChildCount} else {$null}
                                        Explore         = if (!$_.Path) {'-'} else {
                                            New-UDButton -Text "Explore" -OnClick {
                                                #$NewRootDirTextBox = Get-UDElement -Id "NewRootDirTB"
                                                $FullPathToExplore = $PathUpdatedFormat

                                                $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                                                $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                                                $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                                    Invoke-Expression $using:GetRegistrySubKeysFunc
                                                    Invoke-Expression $using:GetRegistryValuesFunc

                                                    $HKCUChildKeys = Get-RegistrySubKeys -path "HKCU:\" -ErrorAction SilentlyContinue
                                                    $HKCUValues = Get-RegistryValues -path "HKCU:\" -ErrorAction SilentlyContinue

                                                    [pscustomobject]@{
                                                        HKCUChildKeys   = $HKCUChildKeys
                                                        HKCUValues      = $HKCUValues
                                                    }
                                                } -ArgumentList $FullPathToExplore
                                                $Session:HKCUChildKeys = $StaticInfo.HKCUChildKeys | Where-Object {$_.Name}
                                                $Session:HKCUValues = $StaticInfo.HKCUValues
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCUChildKeys = $StaticInfo.HKCUChildKeys | Where-Object {$_.Name}
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCUValues = $StaticInfo.HKCUValues

                                                Sync-UDElement -Id "HKCUChildItemsUDGrid"
                                                Sync-UDElement -Id "NewHKCURootDirTB"
                                                Sync-UDElement -Id "CurrentHKCURootDirTB"
                                            }
                                        }
                                    }
                                }
                            } | Out-UDGridData
                        }
                    }
                }
            }
        }

        New-UDCollapsible -Items {
            New-UDCollapsibleItem -Title "HKEY_CLASSES_ROOT" -Icon laptop -Endpoint {
                New-UDRow -Endpoint {
                    New-UDColumn -Size 3 -Endpoint {}
                    New-UDColumn -Size 6 -Endpoint {
                        New-UDElement -Id "CurrentHKCRRootDirTB" -Tag div -EndPoint {
                            $RootDirSlashCheck = $Session:HKCRChildKeys[0].Path -split "HKEY_CLASSES_ROOT\\"
                            $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKCR:"} else {"HKCR:\"}
                            $CurrentDirectory = $Session:HKCRChildKeys[0].Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                            New-UDHeading -Text "Current Directory: $($CurrentDirectory | Split-Path -Parent)" -Size 5
                        }
                        New-UDElement -Id "NewHKCRRootDirTB" -Tag div -EndPoint {
                            New-UDTextbox -Id "NewHKCRRootDirTBProper" -Label "New Directory"
                        }
                        New-UDButton -Text "Explore" -OnClick {
                            $NewRootDirTextBox = Get-UDElement -Id "NewHKCRRootDirTBProper"
                            $FullPathToExplore = $NewRootDirTextBox.Attributes['value']

                            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                Invoke-Expression $using:GetRegistrySubKeysFunc
                                Invoke-Expression $using:GetRegistryValuesFunc

                                New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT

                                $HKCRChildKeys = Get-RegistrySubKeys -path "HKCR:\" -ErrorAction SilentlyContinue
                                $HKCRValues = Get-RegistryValues -path "HKCR:\" -ErrorAction SilentlyContinue

                                [pscustomobject]@{
                                    HKCRChildKeys   = $HKCRChildKeys
                                    HKCRValues      = $HKCRValues
                                }
                            } -ArgumentList $FullPathToExplore
                            $Session:HKCRChildKeys = $StaticInfo.HKCRChildKeys | Where-Object {$_.Name}
                            $Session:HKCRValues = $StaticInfo.HKCRValues
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCRChildKeys = $StaticInfo.HKCRChildKeys | Where-Object {$_.Name}
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCRValues = $StaticInfo.HKCRValues

                            Sync-UDElement -Id "HKCRChildItemsUDGrid"
                            Sync-UDElement -Id "NewHKCRRootDirTB"
                            Sync-UDElement -Id "CurrentHKCRRootDirTB"
                        }

                        New-UDButton -Text "Parent Directory" -OnClick {
                            $RootDirSlashCheck = $Session:HKCRChildKeys[0].Path -split "HKEY_CLASSES_ROOT\\"
                            $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKCR:"} else {"HKCR:\"}
                            $FullPathToExplorePrep = $Session:HKCRChildKeys[0].Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                            $FullPathToExplore = if ($($($FullPathToExplorePrep | Split-Path -Parent) | Split-Path -Parent) -eq "") {
                                $FullPathToExplorePrep | Split-Path -Parent
                            }
                            else {
                                $($FullPathToExplorePrep | Split-Path -Parent) | Split-Path -Parent
                            }

                            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                Invoke-Expression $using:GetRegistrySubKeysFunc
                                Invoke-Expression $using:GetRegistryValuesFunc

                                New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT

                                $HKCRChildKeys = Get-RegistrySubKeys -path "HKCR:\" -ErrorAction SilentlyContinue
                                $HKCRValues = Get-RegistryValues -path "HKCR:\" -ErrorAction SilentlyContinue

                                [pscustomobject]@{
                                    HKCRChildKeys   = $HKCRChildKeys
                                    HKCRValues      = $HKCRValues
                                }
                            } -ArgumentList $FullPathToExplore
                            $Session:HKCRChildKeys = $StaticInfo.HKCRChildKeys | Where-Object {$_.Name}
                            $Session:HKCRValues = $StaticInfo.HKCRValues
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCRChildKeys = $StaticInfo.HKCRChildKeys | Where-Object {$_.Name}
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCRValues = $StaticInfo.HKCRValues

                            Sync-UDElement -Id "HKCRChildItemsUDGrid"
                            Sync-UDElement -Id "NewHKCRRootDirTB"
                            Sync-UDElement -Id "CurrentHKCRRootDirTB"
                        }
                    }
                    New-UDColumn -Size 3 -Endpoint {}
                }
                New-UDRow -Endpoint {
                    New-UDColumn -Size 12 -Endpoint {
                        $RootRegistryProperties = @("Name","Path","Type","Data","ChildCount","Explore")
                        $RootRegistryUDGridSplatParams = @{
                            Id              = "HKCRChildItemsUDGrid"
                            Headers         = $RootRegistryProperties
                            Properties      = $RootRegistryProperties
                            PageSize        = 20
                        }
                        New-UDGrid @RootRegistryUDGridSplatParams -Endpoint {
                            $PUDRSSyncHT = $global:PUDRSSyncHT

                            $RHostIP = $($PUDRSSyncHT.RemoteHostList | Where-Object {$_.HostName -eq $RemoteHost}).IPAddressList[0]

                            $($Session:HKCRChildKeys + $Session:HKCRValues) | foreach {
                                if ($_.Name) {
                                    if ($_.Path) {
                                        $RootDirSlashCheck = $_.Path -split "HKEY_CLASSES_ROOT\\"
                                        $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKCR:"} else {"HKCR:\"}
                                        $PathUpdatedFormat = $_.Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                                    }

                                    #elseif ($_.ChildCount -eq 0 -and $($PathUpdatedFormat -split "\\").Count -gt 2) {'Empty'}
                                    [pscustomobject]@{
                                        Name            = $_.Name
                                        Path            = if ($_.Path) {$PathUpdatedFormat} else {$null}
                                        Type            = if ($_.Type) {$_.Type.ToString()} else {"Key"}
                                        Data            = if ($_.Data) {$_.Data -join ", "} else {$null}
                                        ChildCount      = if ($_.ChildCount) {$_.ChildCount} else {$null}
                                        Explore         = if (!$_.Path) {'-'} else {
                                            New-UDButton -Text "Explore" -OnClick {
                                                #$NewRootDirTextBox = Get-UDElement -Id "NewRootDirTB"
                                                $FullPathToExplore = $PathUpdatedFormat

                                                $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                                                $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                                                $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                                    Invoke-Expression $using:GetRegistrySubKeysFunc
                                                    Invoke-Expression $using:GetRegistryValuesFunc

                                                    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT

                                                    $HKCRChildKeys = Get-RegistrySubKeys -path "HKCR:\" -ErrorAction SilentlyContinue
                                                    $HKCRValues = Get-RegistryValues -path "HKCR:\" -ErrorAction SilentlyContinue

                                                    [pscustomobject]@{
                                                        HKCRChildKeys   = $HKCRChildKeys
                                                        HKCRValues      = $HKCRValues
                                                    }
                                                } -ArgumentList $FullPathToExplore
                                                $Session:HKCRChildKeys = $StaticInfo.HKCRChildKeys | Where-Object {$_.Name}
                                                $Session:HKCRValues = $StaticInfo.HKCRValues
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCRChildKeys = $StaticInfo.HKCRChildKeys | Where-Object {$_.Name}
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCRValues = $StaticInfo.HKCRValues

                                                Sync-UDElement -Id "HKCRChildItemsUDGrid"
                                                Sync-UDElement -Id "NewHKCRRootDirTB"
                                                Sync-UDElement -Id "CurrentHKCRRootDirTB"
                                            }
                                        }
                                    }
                                }
                            } | Out-UDGridData
                        }
                    }
                }
            }
        }

        New-UDCollapsible -Items {
            New-UDCollapsibleItem -Title "HKEY_USERS" -Icon laptop -Endpoint {
                New-UDRow -Endpoint {
                    New-UDColumn -Size 3 -Endpoint {}
                    New-UDColumn -Size 6 -Endpoint {
                        New-UDElement -Id "CurrentHKURootDirTB" -Tag div -EndPoint {
                            $RootDirSlashCheck = $Session:HKUChildKeys[0].Path -split "HKEY_USERS\\"
                            $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKU:"} else {"HKU:\"}
                            $CurrentDirectory = $Session:HKUChildKeys[0].Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                            New-UDHeading -Text "Current Directory: $($CurrentDirectory | Split-Path -Parent)" -Size 5
                        }
                        New-UDElement -Id "NewHKURootDirTB" -Tag div -EndPoint {
                            New-UDTextbox -Id "NewHKURootDirTBProper" -Label "New Directory"
                        }
                        New-UDButton -Text "Explore" -OnClick {
                            $NewRootDirTextBox = Get-UDElement -Id "NewHKURootDirTBProper"
                            $FullPathToExplore = $NewRootDirTextBox.Attributes['value']

                            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                Invoke-Expression $using:GetRegistrySubKeysFunc
                                Invoke-Expression $using:GetRegistryValuesFunc

                                New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS

                                $HKUChildKeys = Get-RegistrySubKeys -path "HKU:\" -ErrorAction SilentlyContinue
                                $HKUValues = Get-RegistryValues -path "HKU:\" -ErrorAction SilentlyContinue

                                [pscustomobject]@{
                                    HKUChildKeys   = $HKUChildKeys
                                    HKUValues      = $HKUValues
                                }
                            } -ArgumentList $FullPathToExplore
                            $Session:HKUChildKeys = $StaticInfo.HKUChildKeys | Where-Object {$_.Name}
                            $Session:HKUValues = $StaticInfo.HKUValues
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKUChildKeys = $StaticInfo.HKUChildKeys | Where-Object {$_.Name}
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKUValues = $StaticInfo.HKUValues

                            Sync-UDElement -Id "HKUChildItemsUDGrid"
                            Sync-UDElement -Id "NewHKURootDirTB"
                            Sync-UDElement -Id "CurrentHKURootDirTB"
                        }

                        New-UDButton -Text "Parent Directory" -OnClick {
                            $RootDirSlashCheck = $Session:HKUChildKeys[0].Path -split "HKEY_USERS\\"
                            $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKU:"} else {"HKU:\"}
                            $FullPathToExplorePrep = $Session:HKUChildKeys[0].Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                            $FullPathToExplore = if ($($($FullPathToExplorePrep | Split-Path -Parent) | Split-Path -Parent) -eq "") {
                                $FullPathToExplorePrep | Split-Path -Parent
                            }
                            else {
                                $($FullPathToExplorePrep | Split-Path -Parent) | Split-Path -Parent
                            }

                            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                Invoke-Expression $using:GetRegistrySubKeysFunc
                                Invoke-Expression $using:GetRegistryValuesFunc

                                New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS

                                $HKUChildKeys = Get-RegistrySubKeys -path "HKU:\" -ErrorAction SilentlyContinue
                                $HKUValues = Get-RegistryValues -path "HKU:\" -ErrorAction SilentlyContinue

                                [pscustomobject]@{
                                    HKUChildKeys   = $HKUChildKeys
                                    HKUValues      = $HKUValues
                                }
                            } -ArgumentList $FullPathToExplore
                            $Session:HKUChildKeys = $StaticInfo.HKUChildKeys | Where-Object {$_.Name}
                            $Session:HKUValues = $StaticInfo.HKUValues
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKUChildKeys = $StaticInfo.HKUChildKeys | Where-Object {$_.Name}
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKUValues = $StaticInfo.HKUValues

                            Sync-UDElement -Id "HKUChildItemsUDGrid"
                            Sync-UDElement -Id "NewHKURootDirTB"
                            Sync-UDElement -Id "CurrentHKURootDirTB"
                        }
                    }
                    New-UDColumn -Size 3 -Endpoint {}
                }
                New-UDRow -Endpoint {
                    New-UDColumn -Size 12 -Endpoint {
                        $RootRegistryProperties = @("Name","Path","Type","Data","ChildCount","Explore")
                        $RootRegistryUDGridSplatParams = @{
                            Id              = "HKUChildItemsUDGrid"
                            Headers         = $RootRegistryProperties
                            Properties      = $RootRegistryProperties
                            PageSize        = 20
                        }
                        New-UDGrid @RootRegistryUDGridSplatParams -Endpoint {
                            $PUDRSSyncHT = $global:PUDRSSyncHT

                            $RHostIP = $($PUDRSSyncHT.RemoteHostList | Where-Object {$_.HostName -eq $RemoteHost}).IPAddressList[0]

                            $($Session:HKUChildKeys + $Session:HKUValues) | foreach {
                                if ($_.Name) {
                                    if ($_.Path) {
                                        $RootDirSlashCheck = $_.Path -split "HKEY_USERS\\"
                                        $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKU:"} else {"HKU:\"}
                                        $PathUpdatedFormat = $_.Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                                    }

                                    #elseif ($_.ChildCount -eq 0 -and $($PathUpdatedFormat -split "\\").Count -gt 2) {'Empty'}
                                    [pscustomobject]@{
                                        Name            = $_.Name
                                        Path            = if ($_.Path) {$PathUpdatedFormat} else {$null}
                                        Type            = if ($_.Type) {$_.Type.ToString()} else {"Key"}
                                        Data            = if ($_.Data) {$_.Data -join ", "} else {$null}
                                        ChildCount      = if ($_.ChildCount) {$_.ChildCount} else {$null}
                                        Explore         = if (!$_.Path) {'-'} else {
                                            New-UDButton -Text "Explore" -OnClick {
                                                #$NewRootDirTextBox = Get-UDElement -Id "NewRootDirTB"
                                                $FullPathToExplore = $PathUpdatedFormat

                                                $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                                                $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                                                $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                                    Invoke-Expression $using:GetRegistrySubKeysFunc
                                                    Invoke-Expression $using:GetRegistryValuesFunc

                                                    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS

                                                    $HKUChildKeys = Get-RegistrySubKeys -path "HKU:\" -ErrorAction SilentlyContinue
                                                    $HKUValues = Get-RegistryValues -path "HKU:\" -ErrorAction SilentlyContinue

                                                    [pscustomobject]@{
                                                        HKUChildKeys   = $HKUChildKeys
                                                        HKUValues      = $HKUValues
                                                    }
                                                } -ArgumentList $FullPathToExplore
                                                $Session:HKUChildKeys = $StaticInfo.HKUChildKeys | Where-Object {$_.Name}
                                                $Session:HKUValues = $StaticInfo.HKUValues
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKUChildKeys = $StaticInfo.HKUChildKeys | Where-Object {$_.Name}
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKUValues = $StaticInfo.HKUValues

                                                Sync-UDElement -Id "HKUChildItemsUDGrid"
                                                Sync-UDElement -Id "NewHKURootDirTB"
                                                Sync-UDElement -Id "CurrentHKURootDirTB"
                                            }
                                        }
                                    }
                                }
                            } | Out-UDGridData
                        }
                    }
                }
            }
        }

        New-UDCollapsible -Items {
            New-UDCollapsibleItem -Title "HKEY_CURRENT_CONFIG" -Icon laptop -Endpoint {
                New-UDRow -Endpoint {
                    New-UDColumn -Size 3 -Endpoint {}
                    New-UDColumn -Size 6 -Endpoint {
                        New-UDElement -Id "CurrentHKCCRootDirTB" -Tag div -EndPoint {
                            $RootDirSlashCheck = $Session:HKCCChildKeys[0].Path -split "HKEY_CURRENT_CONFIG\\"
                            $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKCC:"} else {"HKCC:\"}
                            $CurrentDirectory = $Session:HKCCChildKeys[0].Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                            New-UDHeading -Text "Current Directory: $($CurrentDirectory | Split-Path -Parent)" -Size 5
                        }
                        New-UDElement -Id "NewHKCCRootDirTB" -Tag div -EndPoint {
                            New-UDTextbox -Id "NewHKCCRootDirTBProper" -Label "New Directory"
                        }
                        New-UDButton -Text "Explore" -OnClick {
                            $NewRootDirTextBox = Get-UDElement -Id "NewHKCCRootDirTBProper"
                            $FullPathToExplore = $NewRootDirTextBox.Attributes['value']

                            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                Invoke-Expression $using:GetRegistrySubKeysFunc
                                Invoke-Expression $using:GetRegistryValuesFunc

                                New-PSDrive -Name HKCC -PSProvider Registry -Root HKEY_CURRENT_CONFIG

                                $HKCCChildKeys = Get-RegistrySubKeys -path "HKCC:\" -ErrorAction SilentlyContinue
                                $HKCCValues = Get-RegistryValues -path "HKCC:\" -ErrorAction SilentlyContinue

                                [pscustomobject]@{
                                    HKCCChildKeys   = $HKCCChildKeys
                                    HKCCValues      = $HKCCValues
                                }
                            } -ArgumentList $FullPathToExplore
                            $Session:HKCCChildKeys = $StaticInfo.HKCCChildKeys | Where-Object {$_.Name}
                            $Session:HKCCValues = $StaticInfo.HKCCValues
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCCChildKeys = $StaticInfo.HKCCChildKeys | Where-Object {$_.Name}
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCCValues = $StaticInfo.HKCCValues

                            Sync-UDElement -Id "HKCCChildItemsUDGrid"
                            Sync-UDElement -Id "NewHKCCRootDirTB"
                            Sync-UDElement -Id "CurrentHKCCRootDirTB"
                        }

                        New-UDButton -Text "Parent Directory" -OnClick {
                            $RootDirSlashCheck = $Session:HKCCChildKeys[0].Path -split "HKEY_CURRENT_CONFIG\\"
                            $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKCC:"} else {"HKCC:\"}
                            $FullPathToExplorePrep = $Session:HKCCChildKeys[0].Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                            $FullPathToExplore = if ($($($FullPathToExplorePrep | Split-Path -Parent) | Split-Path -Parent) -eq "") {
                                $FullPathToExplorePrep | Split-Path -Parent
                            }
                            else {
                                $($FullPathToExplorePrep | Split-Path -Parent) | Split-Path -Parent
                            }

                            $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                            $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                Invoke-Expression $using:GetRegistrySubKeysFunc
                                Invoke-Expression $using:GetRegistryValuesFunc

                                New-PSDrive -Name HKCC -PSProvider Registry -Root HKEY_CURRENT_CONFIG

                                $HKCCChildKeys = Get-RegistrySubKeys -path "HKCC:\" -ErrorAction SilentlyContinue
                                $HKCCValues = Get-RegistryValues -path "HKCC:\" -ErrorAction SilentlyContinue

                                [pscustomobject]@{
                                    HKCCChildKeys   = $HKCCChildKeys
                                    HKCCValues      = $HKCCValues
                                }
                            } -ArgumentList $FullPathToExplore
                            $Session:HKCCChildKeys = $StaticInfo.HKCCChildKeys | Where-Object {$_.Name}
                            $Session:HKCCValues = $StaticInfo.HKCCValues
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCCChildKeys = $StaticInfo.HKCCChildKeys | Where-Object {$_.Name}
                            $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCCValues = $StaticInfo.HKCCValues

                            Sync-UDElement -Id "HKCCChildItemsUDGrid"
                            Sync-UDElement -Id "NewHKCCRootDirTB"
                            Sync-UDElement -Id "CurrentHKCCRootDirTB"
                        }
                    }
                    New-UDColumn -Size 3 -Endpoint {}
                }
                New-UDRow -Endpoint {
                    New-UDColumn -Size 12 -Endpoint {
                        $RootRegistryProperties = @("Name","Path","Type","Data","ChildCount","Explore")
                        $RootRegistryUDGridSplatParams = @{
                            Id              = "HKCCChildItemsUDGrid"
                            Headers         = $RootRegistryProperties
                            Properties      = $RootRegistryProperties
                            PageSize        = 20
                        }
                        New-UDGrid @RootRegistryUDGridSplatParams -Endpoint {
                            $PUDRSSyncHT = $global:PUDRSSyncHT

                            $RHostIP = $($PUDRSSyncHT.RemoteHostList | Where-Object {$_.HostName -eq $RemoteHost}).IPAddressList[0]

                            $($Session:HKCCChildKeys + $Session:HKCCValues) | foreach {
                                if ($_.Name) {
                                    if ($_.Path) {
                                        $RootDirSlashCheck = $_.Path -split "HKEY_CURRENT_CONFIG\\"
                                        $ReplaceString = if ($RootDirSlashCheck[-1][0] -eq "\") {"HKCC:"} else {"HKCC:\"}
                                        $PathUpdatedFormat = $_.Path -replace "Microsoft.PowerShell.Core\\Registry::.*?\\",$ReplaceString
                                    }

                                    #elseif ($_.ChildCount -eq 0 -and $($PathUpdatedFormat -split "\\").Count -gt 2) {'Empty'}
                                    [pscustomobject]@{
                                        Name            = $_.Name
                                        Path            = if ($_.Path) {$PathUpdatedFormat} else {$null}
                                        Type            = if ($_.Type) {$_.Type.ToString()} else {"Key"}
                                        Data            = if ($_.Data) {$_.Data -join ", "} else {$null}
                                        ChildCount      = if ($_.ChildCount) {$_.ChildCount} else {$null}
                                        Explore         = if (!$_.Path) {'-'} else {
                                            New-UDButton -Text "Explore" -OnClick {
                                                #$NewRootDirTextBox = Get-UDElement -Id "NewRootDirTB"
                                                $FullPathToExplore = $PathUpdatedFormat

                                                $GetRegistrySubKeysFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistrySubKeys" -and $_ -notmatch "function Get-PUDAdminCenter"}
                                                $GetRegistryValuesFunc = $Cache:ThisModuleFunctionsStringArray | Where-Object {$_ -match "function Get-RegistryValues" -and $_ -notmatch "function Get-PUDAdminCenter"}
                                                $NewPathInfo = Invoke-Command -ComputerName $RHostIP -Credential $Session:CredentialHT.$RemoteHost.PSRemotingCreds -ScriptBlock {
                                                    Invoke-Expression $using:GetRegistrySubKeysFunc
                                                    Invoke-Expression $using:GetRegistryValuesFunc

                                                    New-PSDrive -Name HKCC -PSProvider Registry -Root HKEY_CURRENT_CONFIG

                                                    $HKCCChildKeys = Get-RegistrySubKeys -path "HKCC:\" -ErrorAction SilentlyContinue
                                                    $HKCCValues = Get-RegistryValues -path "HKCC:\" -ErrorAction SilentlyContinue

                                                    [pscustomobject]@{
                                                        HKCCChildKeys   = $HKCCChildKeys
                                                        HKCCValues      = $HKCCValues
                                                    }
                                                } -ArgumentList $FullPathToExplore
                                                $Session:HKCCChildKeys = $StaticInfo.HKCCChildKeys | Where-Object {$_.Name}
                                                $Session:HKCCValues = $StaticInfo.HKCCValues
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCCChildKeys = $StaticInfo.HKCCChildKeys | Where-Object {$_.Name}
                                                $PUDRSSyncHT."$RemoteHost`Info".Registry.HKCCValues = $StaticInfo.HKCCValues

                                                Sync-UDElement -Id "HKCCChildItemsUDGrid"
                                                Sync-UDElement -Id "NewHKCCRootDirTB"
                                                Sync-UDElement -Id "CurrentHKCCRootDirTB"
                                            }
                                        }
                                    }
                                }
                            } | Out-UDGridData
                        }
                    }
                }
            }
        }

        # Live Data Element Example

        # Remove the Loading  Indicator
        $null = $Session:RegistryPageLoadingTracker.Add("FinishedLoading")

        #endregion >> Controls
    }
}
$Page = New-UDPage -Url "/Registry/:RemoteHost" -Endpoint $RegistryPageContent
$null = $Pages.Add($Page)
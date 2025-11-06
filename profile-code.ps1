# ===== Configuracao Global =====
# Garante TLS 1.2 para downloads do PowerShell Gallery no Windows PowerShell 5.1
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# Garante ExecutionPolicy
try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue } catch {}

# ===== Configuracao de Codificacao UTF-8 para PowerShell 5.1 =====
# Forca UTF-8 no PowerShell 5.1 para resolver problemas de caracteres especiais
try {
    $isPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7
    
    if (-not $isPowerShell7) {
        # PowerShell 5.1: Configura codificacao UTF-8
        
        # 1. Define a codificacao de saida e entrada do console
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding = [System.Text.Encoding]::UTF8
        
        # 2. Define a codificacao padrao para cmdlets do PowerShell
        $OutputEncoding = [System.Text.Encoding]::UTF8
        
        # 3. Altera o codepage do console para UTF-8 (65001)
        # Isso e importante para que o console Windows exiba corretamente UTF-8
        try {
            $null = [Console]::OutputEncoding
            chcp 65001 | Out-Null
        }
        catch {
            # Se chcp falhar, tenta via cmd.exe
            try {
                cmd /c "chcp 65001 >nul 2>&1"
            }
            catch {
                # Ignora erros silenciosamente
            }
        }
        
        # 4. Configura o encoding padrao para cmdlets que trabalham com arquivos
        $PSDefaultParameterValues['*:Encoding'] = 'utf8'
        
        # 5. Configura encoding para cmdlets especificos
        $PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
        $PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
        $PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
        
        # 6. Forca a cultura para suportar UTF-8 melhor (opcional)
        try {
            $culture = [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = $culture
        }
        catch {
            # Ignora erros de cultura
        }
    }
    else {
        # PowerShell 7+: UTF-8 ja e padrao, mas garante configuracao explicita
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        $PSDefaultParameterValues['*:Encoding'] = 'utf8'
    }
}
catch {
    # Ignora erros de codificacao silenciosamente para nao quebrar o perfil
    # Se houver problemas, o script continuara funcionando sem UTF-8 forcado
}

# ===== Sistema de Logging =====
$script:showLogs = $false  # So mostra logs detalhados ao instalar ou em erros
$script:totalItems = 10
$script:currentItem = 0
$script:installedItems = 0

function Show-Progress {
    param(
        [string] $Activity = "Verificando e instalando ferramentas",
        [string] $Status,
        [int] $PercentComplete
    )
    
    # Calcula o tamanho da barra (30 caracteres)
    $barWidth = 30
    $filled = [int][math]::Floor($PercentComplete / 100 * $barWidth)
    $empty = [int]($barWidth - $filled)
    
    # Detecta versao do PowerShell e usa caracteres apropriados
    $isPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7
    
    # Cria a barra visual com caracteres compativeis
    if ($isPowerShell7) {
        # PowerShell 7: usa caracteres Unicode (blocos cheios)
        $filledChar = [string][char]0x2588  # █ (bloco cheio)
        $emptyChar = [string][char]0x2591   # ░ (bloco vazio)
    }
    else {
        # PowerShell 5.1: usa caracteres ASCII
        $filledChar = '#'  # ou '=' para visual diferente
        $emptyChar = '-'   # ou '.' para visual diferente
    }
    
    $bar = $filledChar * $filled + $emptyChar * $empty
    
    # Formata a mensagem com cor roxa (#9d3599)
    $escape = [char]27
    $purpleCode = "$escape[38;2;157;53;153m"
    $resetCode = "$escape[0m"
    
    # Escreve na mesma linha (usando carriage return)
    $statusMsg = "`r$purpleCode[$bar] $PercentComplete% - $Status$resetCode"
    Write-Host $statusMsg -NoNewline
}

# ===== Funcao Helper: Get-ScoopCommand =====
function Get-ScoopCommand {
    # Tenta obter o comando scoop do PATH
    $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
    if ($scoopCmd) {
        return $scoopCmd
    }
    
    # Se nao estiver no PATH, tenta usar o caminho direto
    $scoopShimPath = Join-Path $HOME 'scoop\shims\scoop.ps1'
    if (Test-Path $scoopShimPath) {
        return $scoopShimPath
    }
    
    $scoopAppPath = Join-Path $HOME 'scoop\apps\scoop\current\bin\scoop.ps1'
    if (Test-Path $scoopAppPath) {
        return $scoopAppPath
    }
    
    return $null
}

# ===== Funcao Helper: Ensure-Scoop =====
function Ensure-Scoop {
    $scoopInstalled = $false
    if ($env:SCOOP) { $scoopInstalled = $true }
    $scoopShim = Join-Path $HOME 'scoop\shims\scoop.ps1'
    $scoopApp = Join-Path $HOME 'scoop\apps\scoop\current\bin\scoop.ps1'
    if ((Test-Path $scoopShim) -or (Test-Path $scoopApp)) { $scoopInstalled = $true }
    if (Get-Command scoop -ErrorAction SilentlyContinue) { $scoopInstalled = $true }

    if (-not $scoopInstalled) {
        try {
            iwr -useb get.scoop.sh | iex
            
            # Aguarda um momento para o PATH ser atualizado
            Start-Sleep -Seconds 2
            
            # Atualiza PATH para a sessao atual
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
            
            # Adiciona o caminho do scoop ao PATH se necessario
            $scoopShimPath = Join-Path $HOME 'scoop\shims'
            if (Test-Path $scoopShimPath) {
                $env:Path = $env:Path + ';' + $scoopShimPath
            }
            
            if (Get-Command scoop -ErrorAction SilentlyContinue) {
                $script:installedItems++
                $scoopInstalled = $true
            }
            else {
                # Verifica se o scoop foi instalado mesmo que nao esteja no PATH
                if ((Test-Path $scoopShim) -or (Test-Path $scoopApp)) {
                    $script:installedItems++
                    $scoopInstalled = $true
                }
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            $errorPrefix = 'LOG - Erro ao instalar Scoop: '
            Write-Host $errorPrefix -NoNewline -ForegroundColor Red
            Write-Host $errorMsg -ForegroundColor Red
        }
    }
    return $scoopInstalled
}

# ===== Funcao: Sincronizar Perfis do PowerShell (DEFINIDA PRIMEIRO) =====
function Sync-PowerShellProfiles {
    try {
        $currentProfilePath = $PROFILE.CurrentUserCurrentHost
        
        if (-not (Test-Path $currentProfilePath)) {
            return $false
        }
        
        $documentsPath = [Environment]::GetFolderPath('MyDocuments')
        $currentProfileContent = Get-Content -Path $currentProfilePath -Raw -ErrorAction Stop
        
        # Windows PowerShell 5.1 - Perfil padrao
        $pwsh51ProfilePath = Join-Path -Path $documentsPath -ChildPath 'WindowsPowerShell'
        $pwsh51ProfilePath = Join-Path -Path $pwsh51ProfilePath -ChildPath 'Microsoft.PowerShell_profile.ps1'
        if ($currentProfilePath -ne $pwsh51ProfilePath) {
            $targetDir = Split-Path -Path $pwsh51ProfilePath -Parent
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            if (Test-Path $pwsh51ProfilePath) {
                $existingContent = Get-Content -Path $pwsh51ProfilePath -Raw -ErrorAction SilentlyContinue
                if ($existingContent -ne $currentProfileContent) {
                    Set-Content -Path $pwsh51ProfilePath -Value $currentProfileContent -Force -ErrorAction Stop
                }
            }
            else {
                Set-Content -Path $pwsh51ProfilePath -Value $currentProfileContent -Force -ErrorAction Stop
            }
        }
        
        # PowerShell 7+ - Perfil padrao
        $pwsh7ProfilePath = Join-Path -Path $documentsPath -ChildPath 'PowerShell'
        $pwsh7ProfilePath = Join-Path -Path $pwsh7ProfilePath -ChildPath 'Microsoft.PowerShell_profile.ps1'
        if ($currentProfilePath -ne $pwsh7ProfilePath) {
            $targetDir = Split-Path -Path $pwsh7ProfilePath -Parent
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            if (Test-Path $pwsh7ProfilePath) {
                $existingContent = Get-Content -Path $pwsh7ProfilePath -Raw -ErrorAction SilentlyContinue
                if ($existingContent -ne $currentProfileContent) {
                    Set-Content -Path $pwsh7ProfilePath -Value $currentProfileContent -Force -ErrorAction Stop
                }
            }
            else {
                Set-Content -Path $pwsh7ProfilePath -Value $currentProfileContent -Force -ErrorAction Stop
            }
        }
        
        return $true
    }
    catch {
        # Ignora erros silenciosamente para nao interromper o carregamento
        return $false
    }
}

# ===== SINCRONIZACAO INICIAL (ANTES DE TUDO) =====
# IMPORTANTE: Sincroniza o perfil atual com todos os outros perfis ANTES de executar qualquer coisa
# Isso garante que um perfil limpo sempre sobrescreva perfis antigos com logs e erros de sintaxe
try {
    $null = Sync-PowerShellProfiles
}
catch {
    # Ignora erros silenciosamente
}

# ===== 1. Git =====
function Ensure-Git {
    $script:currentItem++
    Show-Progress -Status "Verificando Git..." -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    
    if (Get-Command git -ErrorAction SilentlyContinue) {
        return $true
    }

    $statusMsg = "Instalando Git..."
    Show-Progress -Status $statusMsg -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    try {
        Ensure-Scoop
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            scoop install git *> $null
            if (Get-Command git -ErrorAction SilentlyContinue) {
                $script:installedItems++
                # Atualiza PATH para a sessao atual
                $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
                return $true
            }
        }
        else {
            Write-Host 'LOG - Scoop nao disponivel. Instale Git manualmente.' -ForegroundColor Red
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao instalar Git: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
    return $false
}

# ===== Funcao Helper: Copiar Profile para PowerShell 7 =====
function Copy-ProfileToPowerShell7 {
    param([string]$CurrentProfilePath)
    
    try {
        # Determina o caminho do profile do PowerShell 7
        # O profile do PowerShell 7 fica em: Documents\PowerShell\Microsoft.PowerShell_profile.ps1
        $documentsPath = [Environment]::GetFolderPath('MyDocuments')
        $pwshProfileDir = Join-Path -Path $documentsPath -ChildPath 'PowerShell'
        
        if (-not (Test-Path $pwshProfileDir)) {
            New-Item -ItemType Directory -Path $pwshProfileDir -Force | Out-Null
        }
        
        $pwshProfilePath = Join-Path -Path $pwshProfileDir -ChildPath 'Microsoft.PowerShell_profile.ps1'
        
        # Copia o script atual para o profile do PowerShell 7
        if (Test-Path $CurrentProfilePath) {
            Copy-Item -Path $CurrentProfilePath -Destination $pwshProfilePath -Force -ErrorAction SilentlyContinue
            return $true
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao copiar profile para PowerShell 7: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
    return $false
}

# ===== Funcao Helper: Obter Nome da Fonte Fira Code Nerd Font =====
function Get-FiraCodeNerdFontName {
    <#
    .SYNOPSIS
    Encontra o nome exato da fonte Fira Code Nerd Font instalada no sistema usando a API do Windows.
    #>
    
    try {
        # Lista de possiveis nomes da fonte (em ordem de prioridade - mais comuns primeiro)
        $fontNames = @(
            "FiraCode Nerd Font",
            "Fira Code NF",
            "FiraCode NF",
            "Fira Code Nerd Font",
            "FiraCodeNerdFont",
            "Fira Code Nerd Font Mono"
        )
        
        # Tenta usar a API do Windows para listar fontes instaladas
        try {
            Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
            try {
                $fontFamilies = [Windows.Media.Fonts]::SystemFontFamilies
                
                if ($fontFamilies) {
                    # Procura pela fonte Fira Code Nerd Font instalada
                    foreach ($fontName in $fontNames) {
                        $foundFont = $fontFamilies | Where-Object { 
                            $_.Source -like "*$fontName*" -or 
                            $_.Source -like "*FiraCode*" -or
                            $_.Source -like "*Fira*Code*NF*"
                        } | Select-Object -First 1
                        
                        if ($foundFont) {
                            # Retorna o nome da fonte encontrada
                            $fontFamilyName = $foundFont.Source
                            # Tenta usar o nome mais proximo da lista
                            foreach ($name in $fontNames) {
                                if ($fontFamilyName -like "*$name*") {
                                    return $name
                                }
                            }
                            # Se nao encontrou correspondencia exata, usa o primeiro da lista
                            return $fontNames[0]
                        }
                    }
                }
            }
            catch {
                # Se a chamada do metodo falhar, continua com outros metodos
            }
        }
        catch {
            # Se a API falhar, continua com outros metodos
        }
        
        # Verifica se esta instalada via Scoop (mais comum)
        $scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
        $fontPath = Join-Path $scoopRoot "apps\FiraCode-NF"
        if (Test-Path $fontPath) {
            # FiraCode-NF do Scoop geralmente se registra como "FiraCode Nerd Font"
            return $fontNames[0]
        }
        
        # Verifica arquivos de fonte instalados no sistema
        $fontFiles = Get-ChildItem -Path "$env:WINDIR\Fonts" -ErrorAction SilentlyContinue | 
            Where-Object { 
                ($_.Name -like "*Fira*Code*" -or $_.Name -like "*FiraCode*") -and
                ($_.Name -like "*NF*" -or $_.Name -like "*Nerd*")
            } |
            Select-Object -First 1
        
        if ($fontFiles) {
            return $fontNames[0]
        }
        
        # Se nao encontrou, retorna o nome mais comum (sera aplicado mesmo que a fonte nao esteja instalada)
        return $fontNames[0]
    }
    catch {
        # Retorna o nome padrao mais comum em caso de erro
        return 'FiraCode Nerd Font'
    }
}

# ===== Funcao Helper: Configurar PowerShell 7 como Padrao nas IDEs =====
function Set-PowerShell7AsDefault {
    param([string]$PwshPath)
    
    if (-not $PwshPath) { return }
    
    try {
        # Configura Windows Terminal
        $wtPath1 = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Packages'
        $wtPath1 = Join-Path -Path $wtPath1 -ChildPath 'Microsoft.WindowsTerminal_8wekyb3d8bbwe'
        $wtPath1 = Join-Path -Path $wtPath1 -ChildPath 'LocalState'
        $wtPath1 = Join-Path -Path $wtPath1 -ChildPath 'settings.json'
        
        $wtPath2 = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft'
        $wtPath2 = Join-Path -Path $wtPath2 -ChildPath 'Windows Terminal'
        $wtPath2 = Join-Path -Path $wtPath2 -ChildPath 'settings.json'
        
        $wtSettingsPaths = @($wtPath1, $wtPath2)
        
        foreach ($wtSettingsPath in $wtSettingsPaths) {
            if (Test-Path $wtSettingsPath) {
                try {
                    # Faz backup do settings.json antes de modificar
                    $dateFormat = Get-Date -Format 'yyyyMMdd_HHmmss'
                    $backupPath = $wtSettingsPath + '.backup.' + $dateFormat
                    Copy-Item -Path $wtSettingsPath -Destination $backupPath -Force -ErrorAction SilentlyContinue
                    
                    $wtContent = Get-Content $wtSettingsPath -Raw -ErrorAction Stop
                    $wtSettings = $wtContent | ConvertFrom-Json -ErrorAction Stop
                    
                    # Garante que profiles.list existe
                    if (-not $wtSettings.profiles) {
                        $wtSettings | Add-Member -MemberType NoteProperty -Name 'profiles' -Value (New-Object PSObject) -Force
                    }
                    if (-not $wtSettings.profiles.list) {
                        $wtSettings.profiles | Add-Member -MemberType NoteProperty -Name 'list' -Value @() -Force
                    }
                    
                    $profiles = $wtSettings.profiles.list
                    if (-not $profiles) { $profiles = @() }
                    
                    # Procura por perfil PowerShell 7 existente
                    $pwshProfile = $profiles | Where-Object { 
                        ($_.commandline -and $_.commandline -like '*pwsh*') -or
                        ($_.source -and $_.source -eq 'PowerShell') -or
                        ($_.name -and $_.name -like '*PowerShell*7*')
                    } | Select-Object -First 1
                    
                    # Se nao encontrou, cria um novo perfil
                    if (-not $pwshProfile) {
                        $newGuid = [System.Guid]::NewGuid()
                        $newGuidString = $newGuid.ToString()
                        # Windows Terminal requer GUIDs no formato {guid} com chaves
                        $newGuidFormatted = "{$newGuidString}"
                        
                        # Cria um objeto PowerShell para o novo perfil
                        $pwshProfileObj = New-Object PSObject
                        # Usa o GUID como string com chaves (Windows Terminal espera string no formato {guid})
                        $pwshProfileObj | Add-Member -MemberType NoteProperty -Name 'guid' -Value $newGuidFormatted -Force
                        $pwshProfileObj | Add-Member -MemberType NoteProperty -Name 'name' -Value 'PowerShell 7' -Force
                        $pwshProfileObj | Add-Member -MemberType NoteProperty -Name 'commandline' -Value "`"$PwshPath`"" -Force
                        $pwshProfileObj | Add-Member -MemberType NoteProperty -Name 'source' -Value 'PowerShell' -Force
                        $pwshProfileObj | Add-Member -MemberType NoteProperty -Name 'icon' -Value 'ms-appx:///ProfileIcons/{61c54bbd-c2c6-5271-96e7-009a87ff44bf}.png' -Force
                        $pwshProfileObj | Add-Member -MemberType NoteProperty -Name 'hidden' -Value $false -Force
                        # Configura o diretorio inicial para o home do usuario
                        $pwshProfileObj | Add-Member -MemberType NoteProperty -Name 'startingDirectory' -Value '%USERPROFILE%' -Force
                        
                        # Adiciona o novo perfil a lista EXISTENTE (nao substitui)
                        $profilesList = [System.Collections.ArrayList]::new()
                        if ($profiles) {
                            $profiles | ForEach-Object { [void]$profilesList.Add($_) }
                        }
                        [void]$profilesList.Add($pwshProfileObj)
                        $wtSettings.profiles.list = $profilesList.ToArray()
                        
                        $pwshProfile = $pwshProfileObj
                    }
                    
                    # Define como padrao apenas se encontrou ou criou o perfil
                    if ($pwshProfile -and $pwshProfile.guid) {
                        $wtSettings.defaultProfile = $pwshProfile.guid
                        
                        # Configura a fonte Fira Code Nerd Font
                        $fontName = Get-FiraCodeNerdFontName
                        
                        # Configura nos defaults (aplica a todos os perfis por padrao)
                        if (-not $wtSettings.profiles.defaults) {
                            $wtSettings.profiles | Add-Member -MemberType NoteProperty -Name 'defaults' -Value (New-Object PSObject) -Force
                        }
                        if (-not $wtSettings.profiles.defaults.font) {
                            $wtSettings.profiles.defaults | Add-Member -MemberType NoteProperty -Name 'font' -Value (New-Object PSObject) -Force
                        }
                        $wtSettings.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name 'face' -Value $fontName -Force
                        
                        # Tambem aplica a fonte no perfil PowerShell 7 especificamente
                        if ($pwshProfile) {
                            if (-not $pwshProfile.font) {
                                $pwshProfile | Add-Member -MemberType NoteProperty -Name 'font' -Value (New-Object PSObject) -Force
                            }
                            $pwshProfile.font | Add-Member -MemberType NoteProperty -Name 'face' -Value $fontName -Force
                            # Configura o diretorio inicial para o home do usuario (se nao estiver configurado)
                            if (-not $pwshProfile.startingDirectory) {
                                $pwshProfile | Add-Member -MemberType NoteProperty -Name 'startingDirectory' -Value '%USERPROFILE%' -Force
                            }
                        }
                        
                        # Aplica a fonte em todos os perfis da lista que nao tem fonte configurada
                        if ($wtSettings.profiles.list) {
                            foreach ($profile in $wtSettings.profiles.list) {
                                if (-not $profile.font) {
                                    $profile | Add-Member -MemberType NoteProperty -Name 'font' -Value (New-Object PSObject) -Force
                                }
                                # So aplica se nao tiver fonte configurada (para nao sobrescrever configuracoes customizadas)
                                if (-not $profile.font.face) {
                                    $profile.font | Add-Member -MemberType NoteProperty -Name 'face' -Value $fontName -Force
                                }
                            }
                        }
                        
                        # Converte para JSON preservando o formato correto
                        try {
                            $jsonContent = $wtSettings | ConvertTo-Json -Depth 20 -Compress:$false
                            # Valida o JSON antes de salvar
                            $null = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                            # Salva o JSON formatado corretamente
                            $jsonContent | Set-Content $wtSettingsPath -Encoding UTF8 -ErrorAction Stop
                        }
                        catch {
                            $errorMsg = $_.Exception.Message
                            $errorPrefix = 'LOG - Erro ao salvar configuracoes do Windows Terminal: '
                            Write-Host $errorPrefix -NoNewline -ForegroundColor Red
                            Write-Host $errorMsg -ForegroundColor Red
                            # Restaura o backup em caso de erro
                            if (Test-Path $backupPath) {
                                Copy-Item -Path $backupPath -Destination $wtSettingsPath -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
                catch {
                    $errorMsg = $_.Exception.Message
                    $errorPrefix = 'LOG - Erro ao configurar Windows Terminal: '
                    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
                    Write-Host $errorMsg -ForegroundColor Red
                    # Tenta restaurar o backup em caso de erro critico
                    if ($backupPath -and (Test-Path $backupPath)) {
                        Copy-Item -Path $backupPath -Destination $wtSettingsPath -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        
        # Funcao helper para atualizar settings.json do VS Code/Cursor
        function Update-IDEJsonSettings {
            param(
                [string]$SettingsPath,
                [string]$PwshPath
            )
            
            try {
                $settingsObj = $null
                
                # Le configuracoes existentes
                if (Test-Path $SettingsPath) {
                    $existingContent = Get-Content $SettingsPath -Raw -ErrorAction SilentlyContinue
                    if ($existingContent) {
                        $settingsObj = $existingContent | ConvertFrom-Json -ErrorAction SilentlyContinue
                    }
                }
                
                # Se nao tinha configuracoes, cria objeto vazio
                if (-not $settingsObj) {
                    $settingsObj = New-Object PSObject
                }
                
                # Cria estrutura aninhada se nao existir
                if (-not $settingsObj.terminal) {
                    $settingsObj | Add-Member -MemberType NoteProperty -Name 'terminal' -Value (New-Object PSObject) -Force
                }
                if (-not $settingsObj.terminal.integrated) {
                    $settingsObj.terminal | Add-Member -MemberType NoteProperty -Name 'integrated' -Value (New-Object PSObject) -Force
                }
                if (-not $settingsObj.terminal.integrated.defaultProfile) {
                    $settingsObj.terminal.integrated | Add-Member -MemberType NoteProperty -Name 'defaultProfile' -Value (New-Object PSObject) -Force
                }
                if (-not $settingsObj.terminal.integrated.profiles) {
                    $settingsObj.terminal.integrated | Add-Member -MemberType NoteProperty -Name 'profiles' -Value (New-Object PSObject) -Force
                }
                if (-not $settingsObj.terminal.integrated.profiles.windows) {
                    $settingsObj.terminal.integrated.profiles | Add-Member -MemberType NoteProperty -Name 'windows' -Value (New-Object PSObject) -Force
                }
                
                # Define PowerShell 7 como padrao
                $settingsObj.terminal.integrated.defaultProfile | Add-Member -MemberType NoteProperty -Name 'windows' -Value 'PowerShell' -Force
                
                # Configura o perfil do PowerShell 7
                $pwshProfile = New-Object PSObject
                $pwshProfile | Add-Member -MemberType NoteProperty -Name 'source' -Value 'PowerShell' -Force
                $pwshProfile | Add-Member -MemberType NoteProperty -Name 'path' -Value $PwshPath -Force
                $settingsObj.terminal.integrated.profiles.windows | Add-Member -MemberType NoteProperty -Name 'PowerShell' -Value $pwshProfile -Force
                
                # Configura a fonte Fira Code Nerd Font
                $fontName = Get-FiraCodeNerdFontName
                $settingsObj.terminal.integrated | Add-Member -MemberType NoteProperty -Name 'fontFamily' -Value $fontName -Force
                
                # Converte de volta para JSON preservando outras configuracoes
                $jsonContent = $settingsObj | ConvertTo-Json -Depth 20 -Compress:$false
                $jsonContent | Set-Content $SettingsPath -ErrorAction SilentlyContinue
                return $true
            }
            catch {
                return $false
            }
        }
        
        # Configura VS Code (settings.json)
        $vscodePath1 = Join-Path -Path $env:APPDATA -ChildPath 'Code'
        $vscodePath1 = Join-Path -Path $vscodePath1 -ChildPath 'User'
        $vscodePath1 = Join-Path -Path $vscodePath1 -ChildPath 'settings.json'
        
        $vscodePath2 = Join-Path -Path $env:APPDATA -ChildPath 'Code - Insiders'
        $vscodePath2 = Join-Path -Path $vscodePath2 -ChildPath 'User'
        $vscodePath2 = Join-Path -Path $vscodePath2 -ChildPath 'settings.json'
        
        $vscodeSettingsPaths = @($vscodePath1, $vscodePath2)
        
        foreach ($vscodePath in $vscodeSettingsPaths) {
            $vscodeDir = Split-Path -Path $vscodePath -Parent
            if (Test-Path $vscodeDir) {
                $null = Update-IDEJsonSettings -SettingsPath $vscodePath -PwshPath $PwshPath
            }
        }
        
        # Configura Cursor (mesmo formato do VS Code)
        $cursorSettingsPath = Join-Path -Path $env:APPDATA -ChildPath 'Cursor'
        $cursorSettingsPath = Join-Path -Path $cursorSettingsPath -ChildPath 'User'
        $cursorSettingsPath = Join-Path -Path $cursorSettingsPath -ChildPath 'settings.json'
        $cursorDir = Split-Path -Path $cursorSettingsPath -Parent
        if (Test-Path $cursorDir) {
            $null = Update-IDEJsonSettings -SettingsPath $cursorSettingsPath -PwshPath $PwshPath
        }
        
        # Visual Studio - configura via registry
        try {
            $vsRegPath = 'HKCU:\Software\Microsoft\VisualStudio'
            $pattern = '*ToolsOptions\Environment\Terminal*'
            $vsRegPaths = Get-ChildItem -Path $vsRegPath -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSPath -like $pattern }
            
            foreach ($vsRegPathItem in $vsRegPaths) {
                $propName = 'DefaultTerminal'
                Set-ItemProperty -Path $vsRegPathItem.PSPath -Name $propName -Value $PwshPath -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Ignora erros
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao configurar PowerShell 7 como padrao: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
}

# ===== 2. PowerShell 7+ (instalacao e definicao como terminal padrao) =====
function Ensure-PowerShell7 {
    $script:currentItem++
    Show-Progress -Status "Verificando PowerShell 7..." -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    
    # Se ja esta no PowerShell 7, configura tudo e copia o profile se necessario
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Copia o profile atual para garantir que esta sincronizado
        try {
            $currentProfilePath = $PROFILE.CurrentUserCurrentHost
            if (Test-Path $currentProfilePath) {
                # Nao precisa copiar para si mesmo, mas garante que esta configurado
            }
        }
        catch {}
        
        # Configura PowerShell 7 como padrao nas IDEs
        $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if ($pwshPath) {
            Set-PowerShell7AsDefault -PwshPath $pwshPath
        }
        
        return $true
    }

    # Se esta no PowerShell 5.1, verifica se ja migrou
    $migrationFlagPath = Join-Path $env:TEMP 'pwsh-migration-flag.txt'
    $alreadyMigrated = Test-Path $migrationFlagPath
    
    if ($alreadyMigrated) {
        # Ja migrou antes, apenas retorna (nao abre novo terminal)
        return $true
    }

    # Primeira vez - precisa instalar e configurar
    $statusMsg = "PowerShell 5.1 detectado. Configurando PowerShell 7..."
    Show-Progress -Status $statusMsg -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    try {
        $scoopInstalled = Ensure-Scoop
        
        # Atualiza PATH novamente para garantir que scoop esteja disponivel
        if ($scoopInstalled) {
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
            $scoopShimPath = Join-Path $HOME 'scoop\shims'
            if (Test-Path $scoopShimPath) {
                $env:Path = $env:Path + ';' + $scoopShimPath
            }
        }
        
        $pwshInstalled = $false
        $pwshPath = $null
        
        # Verifica se pwsh ja esta instalado
        $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwshCmd) {
            $pwshPath = $pwshCmd.Source
            $pwshInstalled = $true
        }
        
        # Instala pwsh via Scoop se nao existir
        if (-not $pwshInstalled) {
            $scoopCmd = Get-ScoopCommand
            if ($scoopCmd) {
                $statusMsg = "Instalando PowerShell 7 via Scoop..."
                Show-Progress -Status $statusMsg -PercentComplete (($script:currentItem / $script:totalItems) * 100)
                if ($scoopCmd -is [string]) {
                    & $scoopCmd install pwsh *> $null
                }
                else {
                    scoop install pwsh *> $null
                }
                $script:installedItems++
                
                # Aguarda um momento para o PATH ser atualizado
                Start-Sleep -Seconds 3
                $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
                
                # Verifica novamente
                $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
                if ($pwshCmd) {
                    $pwshPath = $pwshCmd.Source
                    $pwshInstalled = $true
                }
            }
            else {
                Write-Host 'LOG - Scoop nao disponivel. Instale PowerShell 7 manualmente.' -ForegroundColor Red
            }
        }

        # Se pwsh esta disponivel, configura tudo
        if ($pwshInstalled -and $pwshPath) {
            $statusMsg = "Configurando ambiente PowerShell 7..."
            Show-Progress -Status $statusMsg -PercentComplete (($script:currentItem / $script:totalItems) * 100)
            
            # Copia o profile atual para o PowerShell 7
            $currentProfilePath = $PROFILE.CurrentUserCurrentHost
            if (Test-Path $currentProfilePath) {
                Copy-ProfileToPowerShell7 -CurrentProfilePath $currentProfilePath
            }
            
            # Configura como padrao nas IDEs
            Set-PowerShell7AsDefault -PwshPath $pwshPath
            
            # Marca como migrado
            "Migrado em $(Get-Date)" | Set-Content $migrationFlagPath -ErrorAction SilentlyContinue
        }
        
        return $true
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao instalar PowerShell 7: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
}

# ===== 3. NVM (Node Version Manager) =====
function Ensure-NVM {
    $script:currentItem++
    Show-Progress -Status "Verificando NVM..." -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    
    # Verifica NVM para Windows (nvm-windows)
    # Caminhos padrao de instalacao
    $nvmPath = "$env:ProgramFiles\nvm\nvm.exe"
    $nvmPathAlt = "$env:LOCALAPPDATA\nvm\nvm.exe"
    
    # Verifica pasta do Scoop (onde o NVM pode estar instalado via scoop)
    $scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
    $nvmScoopPath = Join-Path $scoopRoot "apps\nvm\nvm.exe"
    $nvmScoopPathAlt = Join-Path $scoopRoot "apps\nvm\current\nvm.exe"
    
    $hasNvmPath = Test-Path $nvmPath
    $hasNvmPathAlt = Test-Path $nvmPathAlt
    $hasNvmScoop = Test-Path $nvmScoopPath
    $hasNvmScoopAlt = Test-Path $nvmScoopPathAlt
    $hasNvmCmd = Get-Command nvm -ErrorAction SilentlyContinue
    
    if ($hasNvmPath -or $hasNvmPathAlt -or $hasNvmScoop -or $hasNvmScoopAlt -or $hasNvmCmd) {
        # Carrega NVM no ambiente atual (tenta em ordem de prioridade)
        if ($hasNvmPath) {
            & $nvmPath | Out-Null
        }
        elseif ($hasNvmPathAlt) {
            & $nvmPathAlt | Out-Null
        }
        elseif ($hasNvmScoop) {
            & $nvmScoopPath | Out-Null
        }
        elseif ($hasNvmScoopAlt) {
            & $nvmScoopPathAlt | Out-Null
        }
        return $true
    }

    $statusMsg = "Instalando NVM..."
    Show-Progress -Status $statusMsg -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    try {
        Ensure-Scoop
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            # Adiciona bucket extras se necessario
            $bucketList = & scoop bucket list 2>$null
            $buckets = $bucketList | ForEach-Object { 
                if ($_ -is [string]) { $_.Trim() } 
                else { $_.ToString().Trim() } 
            }
            if ($buckets -notcontains 'extras') { scoop bucket add extras *> $null }
            
            scoop install nvm *> $null
            
            # Configura NVM - verifica em todas as localizacoes possiveis
            $scoopRootCheck = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
            $nvmCheckPaths = @(
                "$env:LOCALAPPDATA\nvm\nvm.exe",
                "$env:ProgramFiles\nvm\nvm.exe",
                (Join-Path $scoopRootCheck "apps\nvm\nvm.exe"),
                (Join-Path $scoopRootCheck "apps\nvm\current\nvm.exe")
            )
            
            $nvmExe = $nvmCheckPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            
            if ($nvmExe) {
                $script:installedItems++
                # Carrega NVM
                & $nvmExe | Out-Null
                return $true
            }
        }
        else {
            Write-Host 'LOG - Scoop nao disponivel. Instale NVM manualmente.' -ForegroundColor Red
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao instalar NVM: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
    return $false
}

# ===== 4. Node.js LTS via NVM =====
function Ensure-NodeLTS {
    $script:currentItem++
    Show-Progress -Status "Verificando Node.js..." -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    
    # Verifica se Node esta instalado
    if (Get-Command node -ErrorAction SilentlyContinue) {
        return $true
    }

    $statusMsg = "Instalando Node.js LTS via NVM..."
    Show-Progress -Status $statusMsg -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    try {
        # Tenta encontrar e usar NVM (incluindo pasta do Scoop)
        $scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
        $nvmPaths = @(
            "$env:LOCALAPPDATA\nvm\nvm.exe",
            "$env:ProgramFiles\nvm\nvm.exe",
            (Join-Path $scoopRoot "apps\nvm\nvm.exe"),
            (Join-Path $scoopRoot "apps\nvm\current\nvm.exe")
        )
        
        $nvmExe = $nvmPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        
        if ($nvmExe) {
            # Usa NVM para instalar versao LTS
            & $nvmExe install lts *> $null
            & $nvmExe use lts *> $null
            
            # Atualiza PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
            
            if (Get-Command node -ErrorAction SilentlyContinue) {
                $script:installedItems++
                return $true
            }
            else {
                $script:installedItems++
                return $true
            }
        }
        else {
            Write-Host 'LOG - NVM nao encontrado. Instale NVM primeiro.' -ForegroundColor Red
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao instalar Node.js: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
    return $false
}

# ===== 5. Yarn =====
function Ensure-Yarn {
    $script:currentItem++
    Show-Progress -Status "Verificando Yarn..." -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    
    if (Get-Command yarn -ErrorAction SilentlyContinue) {
        return $true
    }

    $statusMsg = "Instalando Yarn..."
    Show-Progress -Status $statusMsg -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    try {
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            npm install -g yarn *> $null
            
            # Atualiza PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
            
            if (Get-Command yarn -ErrorAction SilentlyContinue) {
                $script:installedItems++
                return $true
            }
            else {
                $script:installedItems++
                return $true
            }
        }
        else {
            Write-Host 'LOG - npm nao disponivel. Instale Node.js primeiro.' -ForegroundColor Red
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao instalar Yarn: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
    return $false
}

# ===== 6. Oh My Posh (auto-instalacao e init) =====
function Ensure-OhMyPosh {
    $script:currentItem++
    Show-Progress -Status "Verificando Oh My Posh..." -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    
    $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (-not $ompCmd) {
        $statusMsg = "Instalando Oh My Posh..."
        Show-Progress -Status $statusMsg -PercentComplete (($script:currentItem / $script:totalItems) * 100)
        try {
            Ensure-Scoop
            if (Get-Command scoop -ErrorAction SilentlyContinue) {
                scoop install oh-my-posh *> $null
                $script:installedItems++
            }
            else {
                Write-Host 'LOG - Scoop nao disponivel. Instale Oh My Posh manualmente.' -ForegroundColor Red
                return $false
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            $errorPrefix = 'LOG - Erro ao instalar Oh My Posh: '
            Write-Host $errorPrefix -NoNewline -ForegroundColor Red
            Write-Host $errorMsg -ForegroundColor Red
            return $false
        }
    }

    # Garante o tema amro localmente (baixa se necessario) e inicializa com ele
    if (-not $env:POSH_THEMES_PATH) {
        $env:POSH_THEMES_PATH = Join-Path $HOME ".poshthemes"
    }
    if (-not (Test-Path $env:POSH_THEMES_PATH)) { 
        New-Item -ItemType Directory -Path $env:POSH_THEMES_PATH -Force | Out-Null 
    }
    
    $themePath = Join-Path $env:POSH_THEMES_PATH 'amro.omp.json'
    if (-not (Test-Path $themePath)) {
        try {
            $raw = 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/amro.omp.json'
            Invoke-WebRequest -UseBasicParsing -Uri $raw -OutFile $themePath -ErrorAction SilentlyContinue
        }
        catch {
            $errorMsg = $_.Exception.Message
            $errorPrefix = 'LOG - Erro ao baixar tema: '
            Write-Host $errorPrefix -NoNewline -ForegroundColor Red
            Write-Host $errorMsg -ForegroundColor Red
        }
    }
    
    try {
        oh-my-posh init pwsh --config $themePath | Invoke-Expression
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao inicializar Oh My Posh: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
    return $true
}

# ===== 7. Oh My Posh Fonts (Fira Code Nerd Fonts) =====
function Ensure-NerdFontsViaScoop {
    $script:currentItem++
    Show-Progress -Status "Verificando Nerd Fonts..." -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    
    $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
    if (-not $scoopCmd) { 
        return $true
    }
    
    try {
        # Verifica se a fonte ja esta instalada verificando o diretorio do scoop (evita executar scoop list)
        $scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
        $fontPath = Join-Path $scoopRoot "apps\FiraCode-NF"
        $hasFont = Test-Path $fontPath
        
        if ($hasFont) {
            return $true
        }
        
        # Adiciona buckets uteis somente se faltarem
        $bucketRoot = Join-Path $scoopRoot "buckets"
        $buckets = @()
        if (Test-Path $bucketRoot) {
            $buckets = Get-ChildItem -Path $bucketRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        }
        
        if ($buckets -notcontains 'extras') { 
            scoop bucket add extras *> $null 
        }
        if ($buckets -notcontains 'nerd-fonts') { 
            scoop bucket add nerd-fonts *> $null 
        }
        
        # Verifica novamente antes de instalar (usando diretorio em vez de scoop list)
        $hasFontCheck = Test-Path $fontPath
        
        if (-not $hasFontCheck) {
            $statusMsg = "Instalando Fira Code Nerd Font..."
            Show-Progress -Status $statusMsg -PercentComplete (($script:currentItem / $script:totalItems) * 100)
            scoop install FiraCode-NF *> $null
            $script:installedItems++
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao verificar/instalar Nerd Fonts: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
    return $true
}

# ===== 8. PowerShell Modules (PSGallery, Terminal-Icons, PSReadLine) =====
function Ensure-PowerShellModules {
    $script:currentItem++
    Show-Progress -Status "Verificando modulos PowerShell..." -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    # Garante provedor NuGet e confianca no PSGallery (no escopo do usuario)
    try {
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
        }
    }
    catch {}
    
    try {
        $src = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
        if ($src -and $src.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }
    }
    catch {}

    function Install-And-ImportModule {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [string] $MinimumVersion
        )
        $hasModule = Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue
        if (-not $hasModule) {
            try {
                $params = @{ Name = $Name; Scope = 'CurrentUser'; Force = $true; Repository = 'PSGallery'; AllowClobber = $true }
                if ($MinimumVersion) { $params.MinimumVersion = $MinimumVersion }
                Install-Module @params -ErrorAction SilentlyContinue
            }
            catch {
                $errorMsg = $_.Exception.Message
                $errorPrefix = 'LOG - Erro ao instalar modulo '
                Write-Host $errorPrefix -NoNewline -ForegroundColor Red
                Write-Host $Name -NoNewline -ForegroundColor Red
                Write-Host ' : ' -NoNewline -ForegroundColor Red
                Write-Host $errorMsg -ForegroundColor Red
            }
        }
        try { 
            Import-Module -Name $Name -ErrorAction SilentlyContinue
        }
        catch {}
    }

    # Terminal-Icons (requer fonte Nerd Fonts)
    Install-And-ImportModule -Name 'Terminal-Icons'

    # PSReadLine (melhorias de edicao, predicao e historico)
    if ($host.Name -eq 'ConsoleHost') {
        $psrlAvailable = Get-Module -ListAvailable -Name PSReadLine -ErrorAction SilentlyContinue
        if (-not $psrlAvailable) {
            try {
                Install-Module -Name PSReadLine -AllowClobber -Force -Scope CurrentUser -Repository PSGallery -ErrorAction SilentlyContinue
            }
            catch {
                $errorMsg = $_.Exception.Message
                $errorPrefix = 'LOG - Erro ao instalar PSReadLine: '
                Write-Host $errorPrefix -NoNewline -ForegroundColor Red
                Write-Host $errorMsg -ForegroundColor Red
            }
        }
        try { 
            Import-Module PSReadLine -ErrorAction SilentlyContinue
        }
        catch {}
    }

    # posh-git (complementos de Git: autocomplete e informacoes de status)
    Install-And-ImportModule -Name 'posh-git'
    return $true
}

# ===== 9. Ajustes do PSReadLine =====
function Configure-PSReadLine {
    $script:currentItem++
    Show-Progress -Status "Configurando PSReadLine..." -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    
    if (Get-Module PSReadLine) {
        try {
            # Configura Tab para MenuComplete (compativel com todas as versoes)
            Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete -ErrorAction SilentlyContinue
            
            # PredictionSource so existe no PSReadLine 2.0.0 ou superior
            # Verifica a versao do modulo antes de usar o parametro
            $psReadLineModule = Get-Module PSReadLine
            if ($psReadLineModule -and $psReadLineModule.Version -ge [version]"2.0.0") {
                try {
                    Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
                }
                catch {
                    # Se falhar, ignora silenciosamente (versao pode nao suportar)
                }
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            $errorPrefix = 'LOG - Erro ao configurar PSReadLine: '
            Write-Host $errorPrefix -NoNewline -ForegroundColor Red
            Write-Host $errorMsg -ForegroundColor Red
        }
    }
}

# ===== 10. Claude Code =====
function Ensure-ClaudeCode {
    $script:currentItem++
    Show-Progress -Status "Verificando Claude Code..." -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    # Verifica se Claude Code esta instalado em varios locais possiveis
    $claudePaths = @(
        "$env:LOCALAPPDATA\Programs\Claude Code\Claude Code.exe",
        "$env:ProgramFiles\Claude Code\Claude Code.exe",
        "$env:ProgramFiles(x86)\Claude Code\Claude Code.exe",
        "$env:USERPROFILE\AppData\Local\Programs\Claude Code\Claude Code.exe",
        "$env:USERPROFILE\AppData\Local\Claude Code\Claude Code.exe",
        "C:\Program Files\nodejs\claude.exe",
        "C:\Program Files\nodejs\Claude Code.exe",
        "C:\Program Files\nodejs\ClaudeCode.exe",
        "C:\Program Files\nodejs\claude-code.exe"
    )
    
    # Verifica cada caminho
    $claudeInstalled = $false
    $foundPath = $null
    foreach ($path in $claudePaths) {
        if (Test-Path $path) {
            $claudeInstalled = $true
            $foundPath = $path
            break
        }
    }
    
    # Se nao encontrou, tenta buscar arquivos "Claude*" na pasta nodejs e subpastas
    if (-not $claudeInstalled) {
        try {
            $nodejsPath = "C:\Program Files\nodejs"
            if (Test-Path $nodejsPath) {
                # Busca na raiz da pasta nodejs por "claude.exe" ou arquivos com "Claude" no nome
                $claudeExe = Get-ChildItem -Path $nodejsPath -Filter "claude.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($claudeExe) {
                    $claudeInstalled = $true
                    $foundPath = $claudeExe.FullName
                }
                else {
                    # Busca por qualquer arquivo com "Claude" no nome
                    $claudeFiles = Get-ChildItem -Path $nodejsPath -Filter "*Claude*" -ErrorAction SilentlyContinue
                    if ($claudeFiles) {
                        $claudeExe = $claudeFiles | Where-Object { $_.Extension -eq ".exe" } | Select-Object -First 1
                        if ($claudeExe) {
                            $claudeInstalled = $true
                            $foundPath = $claudeExe.FullName
                        }
                    }
                }
                
                # Se nao encontrou, busca recursivamente em subpastas (apenas 1 nivel para nao ser muito lento)
                if (-not $claudeInstalled) {
                    $subdirs = Get-ChildItem -Path $nodejsPath -Directory -ErrorAction SilentlyContinue
                    foreach ($subdir in $subdirs) {
                        $claudeExe = Get-ChildItem -Path $subdir.FullName -Filter "claude.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($claudeExe) {
                            $claudeInstalled = $true
                            $foundPath = $claudeExe.FullName
                            break
                        }
                        else {
                            $claudeFiles = Get-ChildItem -Path $subdir.FullName -Filter "*Claude*" -ErrorAction SilentlyContinue
                            if ($claudeFiles) {
                                $claudeExe = $claudeFiles | Where-Object { $_.Extension -eq ".exe" } | Select-Object -First 1
                                if ($claudeExe) {
                                    $claudeInstalled = $true
                                    $foundPath = $claudeExe.FullName
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        catch {}
    }
    
    # Se nao encontrou pelos caminhos comuns, tenta buscar nos processos em execucao
    if (-not $claudeInstalled) {
        try {
            $claudeProcess = Get-Process -Name "*Claude*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($claudeProcess) {
                $claudeInstalled = $true
                $foundPath = $claudeProcess.Path
            }
        }
        catch {}
    }
    
    # Verifica se os comandos estao disponiveis
    $hasCmd1 = $false
    $hasCmd2 = $false
    $hasCmd3 = $false
    try {
        $cmd = Get-Command "claude" -ErrorAction SilentlyContinue
        if ($cmd) {
            $hasCmd3 = $true
            $foundPath = $cmd.Source
        }
    }
    catch {}
    try {
        $cmd = Get-Command "claude-code" -ErrorAction SilentlyContinue
        if ($cmd) {
            $hasCmd1 = $true
            if (-not $foundPath) { $foundPath = $cmd.Source }
        }
    }
    catch {}
    try {
        $cmd = Get-Command "claudecode" -ErrorAction SilentlyContinue
        if ($cmd) {
            $hasCmd2 = $true
            if (-not $foundPath) { $foundPath = $cmd.Source }
        }
    }
    catch {}
    
    if ($claudeInstalled -or $hasCmd1 -or $hasCmd2 -or $hasCmd3) {
        return $true
    }

    $statusMsg = "Instalando Claude Code..."
    Show-Progress -Status $statusMsg -PercentComplete (($script:currentItem / $script:totalItems) * 100)
    try {
        Ensure-Scoop
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            # Adiciona bucket extras se necessario
            $bucketList = & scoop bucket list 2>$null
            $buckets = $bucketList | ForEach-Object { 
                if ($_ -is [string]) { $_.Trim() } 
                else { $_.ToString().Trim() } 
            }
            if ($buckets -notcontains 'extras') { scoop bucket add extras *> $null }
            
            scoop install claude-code *> $null
            
            # Verifica novamente apos instalacao
            $installedPath = Test-Path "C:\Program Files\nodejs\claude.exe"
            if (-not $installedPath) {
                $installedPath = Test-Path "$env:LOCALAPPDATA\Programs\Claude Code\Claude Code.exe"
            }
            $hasCmd1After = $false
            $hasCmd2After = $false
            $hasCmd3After = $false
            try {
                $cmd = Get-Command "claude" -ErrorAction SilentlyContinue
                if ($cmd) { $hasCmd3After = $true }
            }
            catch {}
            try {
                $cmd = Get-Command "claude-code" -ErrorAction SilentlyContinue
                if ($cmd) { $hasCmd1After = $true }
            }
            catch {}
            try {
                $cmd = Get-Command "claudecode" -ErrorAction SilentlyContinue
                if ($cmd) { $hasCmd2After = $true }
            }
            catch {}
            
            if ($installedPath -or $hasCmd1After -or $hasCmd2After -or $hasCmd3After) {
                $script:installedItems++
                return $true
            }
        }
        else {
            Write-Host 'LOG - Scoop nao disponivel. Baixe Claude Code em: https://claude.ai/code' -ForegroundColor Red
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao instalar Claude Code: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
    return $false
}

# ===== Comando manual para atualizar o PSReadLine =====
function Update-PSReadLineSafe {
    try { Remove-Module PSReadLine -ErrorAction SilentlyContinue } catch {}
    try { Install-Module -Name PSReadLine -AllowClobber -Force -Scope CurrentUser -Repository PSGallery } catch {}
    try { Import-Module PSReadLine -Force } catch {}
}

# ===== Funcao para obter informacoes completas de rede =====
function Get-MyIP {
    Write-Host '===============================================================' -ForegroundColor Cyan
    Write-Host '           INFORMACOES DE REDE' -ForegroundColor Cyan
    Write-Host '===============================================================' -ForegroundColor Cyan
    
    # IP Global (Publico)
    Write-Host '[*] IP Global (Publico):' -ForegroundColor Yellow -NoNewline
    try {
        $publicIP = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop).Content.Trim()
        Write-Host (' ' + $publicIP) -ForegroundColor Green
    }
    catch {
        try {
            $publicIP = (Invoke-WebRequest -Uri "https://icanhazip.com" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop).Content.Trim()
            Write-Host (' ' + $publicIP) -ForegroundColor Green
        }
        catch {
            Write-Host ' Nao disponivel' -ForegroundColor Red
            $publicIP = $null
        }
    }
    
    Write-Host ''
    
    # Informacoes de adaptadores de rede
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object InterfaceIndex
        
        foreach ($adapter in $adapters) {
            $adapterName = $adapter.Name
            $interfaceIndex = $adapter.InterfaceIndex
            
            Write-Host ('[*] Adaptador: ' + $adapterName) -ForegroundColor Magenta
            Write-Host ('   Interface Index: ' + $interfaceIndex) -ForegroundColor Gray
            
            # IPv4
            $ipv4 = Get-NetIPAddress -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "169.254.*" }
            if ($ipv4) {
                Write-Host '   IPv4: ' -NoNewline -ForegroundColor Cyan
                Write-Host $ipv4.IPAddress -ForegroundColor Green -NoNewline
                Write-Host ' / ' -NoNewline -ForegroundColor Gray
                Write-Host $ipv4.PrefixLength -ForegroundColor Gray
                Write-Host '   Mascara: ' -NoNewline -ForegroundColor Cyan
                try {
                    $prefixLength = $ipv4.PrefixLength
                    $maskBits = [Math]::Pow(2, 32) - [Math]::Pow(2, 32 - $prefixLength)
                    $maskBytes = [BitConverter]::GetBytes([UInt32]$maskBits)
                    [Array]::Reverse($maskBytes)
                    $mask = [System.Net.IPAddress]::new($maskBytes)
                    Write-Host $mask.ToString() -ForegroundColor Green
                }
                catch {
                    Write-Host '/' -NoNewline -ForegroundColor Green
                    Write-Host $prefixLength -ForegroundColor Green
                }
            }
            
            # IPv6
            $ipv6 = Get-NetIPAddress -InterfaceIndex $interfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "fe80:*" -and $_.IPAddress -notlike "::1" }
            if ($ipv6) {
                Write-Host '   IPv6: ' -NoNewline -ForegroundColor Cyan
                Write-Host $ipv6.IPAddress -ForegroundColor Green -NoNewline
                Write-Host ' / ' -NoNewline -ForegroundColor Gray
                Write-Host $ipv6.PrefixLength -ForegroundColor Gray
            }
            
            # Gateway padrao
            $gateway = Get-NetRoute -InterfaceIndex $interfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($gateway) {
                Write-Host '   Gateway: ' -NoNewline -ForegroundColor Cyan
                Write-Host $gateway.NextHop -ForegroundColor Green
            }
            
            # DNS Servers
            $dns = Get-DnsClientServerAddress -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($dns -and $dns.ServerAddresses) {
                Write-Host '   DNS: ' -NoNewline -ForegroundColor Cyan
                Write-Host ($dns.ServerAddresses -join ", ") -ForegroundColor Green
            }
            
            # MAC Address
            $macAddress = $adapter.MacAddress
            if ($macAddress) {
                Write-Host '   MAC: ' -NoNewline -ForegroundColor Cyan
                Write-Host $macAddress -ForegroundColor Green
            }
            
            # Status e velocidade
            Write-Host '   Status: ' -NoNewline -ForegroundColor Cyan
            Write-Host $adapter.Status -ForegroundColor Green -NoNewline
            if ($adapter.LinkSpeed) {
                Write-Host (' (' + $adapter.LinkSpeed + ')') -ForegroundColor Gray
            }
            else {
                Write-Host ''
            }
            
            Write-Host ''
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Host '   Erro ao obter informacoes de adaptadores: ' -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
    
    Write-Host '===============================================================' -ForegroundColor Cyan
    
    # Retorna objeto com informacoes
    return @{
        PublicIP = $publicIP
        Adapters = $adapters
    }
}

# Cria alias "ip" para a funcao Get-MyIP
Set-Alias -Name ip -Value Get-MyIP -Scope Global

# ===== Funcoes de Processos e Portas =====
function Find-ProcessByPort { 
    param([Parameter(Mandatory)][int]$port)
    try {
        $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($connections) {
            $processIds = $connections | Select-Object -ExpandProperty OwningProcess -Unique
            $processes = $processIds | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }
            
            if ($processes) {
                Write-Host ('Processos encontrados na porta ' + $port + ' :') -ForegroundColor Cyan
                $processes | Format-Table Id, ProcessName, Path, @{Label = "CPU"; Expression = { $_.CPU } }, @{Label = "Memory (MB)"; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 2) } } -AutoSize
                return $processes
            }
            else {
                Write-Host ('Nenhum processo encontrado na porta ' + $port) -ForegroundColor Red
                return $null
            }
        }
        else {
            Write-Host ('Nenhum processo encontrado na porta ' + $port) -ForegroundColor Red
            return $null
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Host 'Erro ao buscar processo na porta ' -NoNewline -ForegroundColor Red
        Write-Host $port -NoNewline -ForegroundColor Red
        Write-Host ' : ' -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
        return $null
    }
}

function Kill-ProcessByPort { 
    param([Parameter(Mandatory)][int]$port)
    try {
        $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($connections) {
            $processIds = $connections | Select-Object -ExpandProperty OwningProcess -Unique
            $processes = $processIds | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }
            
            if ($processes) {
                Write-Host ('Finalizando processos na porta ' + $port + ' :') -ForegroundColor Yellow
                $processes | ForEach-Object {
                    Write-Host ('  - ' + $_.ProcessName + ' (PID: ' + $_.Id + ')') -ForegroundColor Gray
                    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                }
                Write-Host 'Processos finalizados com sucesso!' -ForegroundColor Green
                return $true
            }
            else {
                Write-Host ('Nenhum processo encontrado na porta ' + $port) -ForegroundColor Red
                return $false
            }
        }
        else {
            Write-Host ('Nenhum processo encontrado na porta ' + $port) -ForegroundColor Red
            return $false
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Host 'Erro ao finalizar processo na porta ' -NoNewline -ForegroundColor Red
        Write-Host $port -NoNewline -ForegroundColor Red
        Write-Host ' : ' -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
        return $false
    }
}

Set-Alias -Name fport -Value Find-ProcessByPort -Scope Global
Set-Alias -Name kport -Value Kill-ProcessByPort -Scope Global

# ===== Funcao de Sistema e Hardware =====
function Get-SystemInfo {
    Write-Host '===============================================================' -ForegroundColor Cyan
    Write-Host '           INFORMACOES DO SISTEMA' -ForegroundColor Cyan
    Write-Host '===============================================================' -ForegroundColor Cyan
    
    # Sistema Operacional
    Write-Host '[*] Sistema Operacional:' -ForegroundColor Yellow
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host '   OS: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($env:OS + ' - ' + $os.Caption + ' ' + $os.OSArchitecture) -ForegroundColor Green
    Write-Host '   Versao: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($os.Version) -ForegroundColor Green
    Write-Host '   Build: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($os.BuildNumber) -ForegroundColor Green
    Write-Host ''
    
    # PowerShell
    Write-Host '[*] PowerShell:' -ForegroundColor Yellow
    Write-Host '   Versao: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($PSVersionTable.PSVersion) -ForegroundColor Green
    Write-Host '   Edicao: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($PSVersionTable.PSEdition) -ForegroundColor Green
    Write-Host ''
    
    # Usuario
    Write-Host '[*] Usuario:' -ForegroundColor Yellow
    Write-Host '   Nome: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($env:USERNAME) -ForegroundColor Green
    Write-Host '   Dominio: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($env:USERDOMAIN) -ForegroundColor Green
    Write-Host '   Computador: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($env:COMPUTERNAME) -ForegroundColor Green
    Write-Host ''
    
    # Hardware
    Write-Host '[*] Hardware:' -ForegroundColor Yellow
    $computer = Get-CimInstance Win32_ComputerSystem
    Write-Host '   Fabricante: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($computer.Manufacturer) -ForegroundColor Green
    Write-Host '   Modelo: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($computer.Model) -ForegroundColor Green
    Write-Host '   Processador: ' -NoNewline -ForegroundColor Cyan
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    Write-Host ($processor.Name) -ForegroundColor Green
    Write-Host '   Nucleos Fisicos: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($processor.NumberOfCores) -ForegroundColor Green
    Write-Host '   Nucleos Logicos: ' -NoNewline -ForegroundColor Cyan
    Write-Host ($processor.NumberOfLogicalProcessors) -ForegroundColor Green
    Write-Host ''
    
    # Memoria
    Write-Host '[*] Memoria:' -ForegroundColor Yellow
    $totalRAM = $computer.TotalPhysicalMemory / 1GB
    $osMem = Get-CimInstance Win32_OperatingSystem
    $freeRAM = $osMem.FreePhysicalMemory / 1MB
    $usedRAM = $totalRAM - $freeRAM
    $percentUsed = [math]::Round(($usedRAM / $totalRAM) * 100, 2)
    
    Write-Host '   Total: ' -NoNewline -ForegroundColor Cyan
    Write-Host ([math]::Round($totalRAM, 2).ToString() + ' GB') -ForegroundColor Green
    Write-Host '   Usada: ' -NoNewline -ForegroundColor Cyan
    $percent = [char]37
    $ramMsg = [math]::Round($usedRAM, 2).ToString() + ' GB (' + $percentUsed.ToString() + $percent + ')'
    Write-Host $ramMsg -ForegroundColor $(if ($percentUsed -gt 80) { 'Red' } elseif ($percentUsed -gt 60) { 'Yellow' } else { 'Green' })
    Write-Host '   Livre: ' -NoNewline -ForegroundColor Cyan
    Write-Host ([math]::Round($freeRAM, 2).ToString() + ' GB') -ForegroundColor Green
    Write-Host ''
    
    # Disco
    Write-Host '[*] Disco:' -ForegroundColor Yellow
    $drives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    foreach ($drive in $drives) {
        $totalSpace = $drive.Size / 1GB
        $freeSpace = $drive.FreeSpace / 1GB
        $usedSpace = $totalSpace - $freeSpace
        $percentUsed = [math]::Round(($usedSpace / $totalSpace) * 100, 2)
        
        Write-Host ('   ' + $drive.DeviceID + ' ') -NoNewline -ForegroundColor Cyan
        Write-Host 'Total: ' -NoNewline -ForegroundColor Gray
        Write-Host ([math]::Round($totalSpace, 2).ToString() + ' GB') -NoNewline -ForegroundColor Green
        Write-Host ' | Usado: ' -NoNewline -ForegroundColor Gray
        $percent = [char]37
        $diskMsg = [math]::Round($usedSpace, 2).ToString() + ' GB (' + $percentUsed.ToString() + $percent + ')'
        Write-Host $diskMsg -NoNewline -ForegroundColor $(if ($percentUsed -gt 80) { 'Red' } elseif ($percentUsed -gt 60) { 'Yellow' } else { 'Green' })
        Write-Host ' | Livre: ' -NoNewline -ForegroundColor Gray
        Write-Host ([math]::Round($freeSpace, 2).ToString() + ' GB') -ForegroundColor Green
    }
    
    Write-Host ('===============================================================') -ForegroundColor Cyan
}

Set-Alias -Name sysinfo -Value Get-SystemInfo -Scope Global

# ===== Funcao para listar todos os aliases personalizados =====
function Show-MyAliases {
    Write-Host ('===============================================================') -ForegroundColor Cyan
    Write-Host ('           ALIASES PERSONALIZADOS') -ForegroundColor Cyan
    Write-Host ('===============================================================') -ForegroundColor Cyan
    
    # Lista de aliases personalizados com descricoes
    $aliases = @(
        @{ Alias = "ip"; Description = "Mostra informacoes completas de rede (IP global, IPv4, IPv6, Gateway, DNS, MAC)" },
        @{ Alias = "sysinfo"; Description = "Mostra informacoes detalhadas do sistema e hardware" },
        @{ Alias = "fport"; Description = "Encontra processos usando uma porta especifica (ex: fport 3000)" },
        @{ Alias = "kport"; Description = "Finaliza processos usando uma porta especifica (ex: kport 3000)" },
        @{ Alias = "cpwd"; Description = "Copia o caminho atual do terminal para o clipboard do Windows" },
        @{ Alias = "cpath"; Description = "Copia o caminho atual do terminal para o clipboard do Windows" },
        @{ Alias = "helpa"; Description = "Lista todos os aliases personalizados disponiveis" }
    )
    
    Write-Host ('[*] Aliases Disponiveis:') -ForegroundColor Yellow
    
    foreach ($aliasInfo in $aliases) {
        Write-Host '   ' -NoNewline
        Write-Host $aliasInfo.Alias -ForegroundColor Green -NoNewline
        Write-Host ' -> ' -ForegroundColor Gray -NoNewline
        Write-Host $aliasInfo.Description -ForegroundColor Cyan
    }
    
    Write-Host ('===============================================================') -ForegroundColor Cyan
    
    # Mostra todos os aliases do escopo global que sao funcoes personalizadas
    Write-Host ('Funcoes Personalizadas Disponiveis:') -ForegroundColor Yellow
    
    $functions = Get-ChildItem Function: | Where-Object { 
        $_.Name -like 'Get-My*' -or 
        $_.Name -like 'Get-System*' -or 
        $_.Name -like 'Find-Process*' -or 
        $_.Name -like 'Kill-Process*' -or
        $_.Name -like 'Show-My*'
    } | Sort-Object Name
    
    if ($functions) {
        foreach ($func in $functions) {
            $aliasName = (Get-Alias | Where-Object { $_.Definition -eq $func.Name }).Name
            if ($aliasName) {
                Write-Host '   ' -NoNewline
                Write-Host $aliasName -ForegroundColor Green -NoNewline
                Write-Host ' -> ' -ForegroundColor Gray -NoNewline
                Write-Host $func.Name -ForegroundColor Cyan
            }
        }
    }
    
    Write-Host ''
}

Set-Alias -Name helpa -Value Show-MyAliases -Scope Global

# ===== Funcao para copiar caminho atual para o clipboard =====
function Copy-Path {
    $currentPath = (Get-Location).Path
    try {
        Set-Clipboard -Value $currentPath
        Write-Host 'Caminho copiado para o clipboard: ' -NoNewline -ForegroundColor Green
        Write-Host $currentPath -ForegroundColor Cyan
    }
    catch {
        # Fallback para clip.exe se Set-Clipboard nao funcionar
        try {
            $currentPath | clip.exe
            Write-Host 'Caminho copiado para o clipboard: ' -NoNewline -ForegroundColor Green
            Write-Host $currentPath -ForegroundColor Cyan
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Host 'Erro ao copiar caminho para o clipboard: ' -NoNewline -ForegroundColor Red
            Write-Host $errorMsg -ForegroundColor Red
        }
    }
}

# Alias curto para Copy-Path
Set-Alias -Name cpwd -Value Copy-Path -Scope Global
Set-Alias -Name cpath -Value Copy-Path -Scope Global

# Nota: A funcao Sync-PowerShellProfiles ja foi definida no inicio do arquivo (linha 112)
# Esta secao foi removida para evitar duplicacao

# ===== Funcao: Carregar Perfil do Gist GitHub (FUTURO) =====
function Update-ProfileFromGist {
    <#
    .SYNOPSIS
    Atualiza o perfil do PowerShell a partir de um Gist do GitHub.
    
    .DESCRIPTION
    Esta funcao baixa o perfil mais recente de um Gist do GitHub e aplica em todos os perfis do PowerShell.
    Para usar, descomente a chamada desta funcao no final do script e configure o $GistUrl abaixo.
    
    .PARAMETER GistUrl
    URL do Gist do GitHub (formato: https://gist.github.com/USERNAME/GIST_ID/raw/COMMIT_ID/FILENAME)
    ou URL simples do arquivo raw do Gist.
    
    .EXAMPLE
    Update-ProfileFromGist -GistUrl 'https://gist.githubusercontent.com/usuario/gist-id/raw/arquivo.ps1'
    #>
    
    param(
        [Parameter(Mandatory = $false)]
        [string]$GistUrl = ''
    )
    
    # ===== CONFIGURACAO DO GIST =====
    # Descomente e configure a URL do seu Gist quando estiver pronto:
    # $GistUrl = 'https://gist.githubusercontent.com/USERNAME/GIST_ID/raw/COMMIT_ID/FILENAME.ps1'
    # OU use uma URL mais simples (sem commit ID para sempre pegar a versao mais recente):
    # $GistUrl = 'https://gist.githubusercontent.com/USERNAME/GIST_ID/raw/FILENAME.ps1'
    
    if ([string]::IsNullOrWhiteSpace($GistUrl)) {
        # Se nao configurado, retorna sem fazer nada
        return $false
    }
    
    try {
        # Baixa o conteudo do Gist
        $gistContent = Invoke-WebRequest -Uri $GistUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        
        if ($gistContent.StatusCode -ne 200) {
            $errorPrefix = 'LOG - Erro ao baixar Gist: Status code '
            Write-Host $errorPrefix -NoNewline -ForegroundColor Red
            Write-Host $gistContent.StatusCode -ForegroundColor Red
            return $false
        }
        
        $profileContent = $gistContent.Content
        
        # Verifica se o conteudo e diferente do perfil atual
        $currentProfilePath = $PROFILE.CurrentUserCurrentHost
        $needsUpdate = $true
        
        if (Test-Path $currentProfilePath) {
            $currentContent = Get-Content -Path $currentProfilePath -Raw -ErrorAction SilentlyContinue
            if ($currentContent -eq $profileContent) {
                $needsUpdate = $false
            }
        }
        
        if ($needsUpdate) {
            # Atualiza o perfil atual
            Set-Content -Path $currentProfilePath -Value $profileContent -Force -ErrorAction Stop
            
            # Sincroniza com todos os outros perfis
            Sync-PowerShellProfiles
            
            # Recarrega o perfil atual
            . $currentProfilePath
            
            return $true
        }
        
        return $true
    }
    catch {
        $errorMsg = $_.Exception.Message
        $errorPrefix = 'LOG - Erro ao atualizar perfil do Gist: '
        Write-Host $errorPrefix -NoNewline -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
        return $false
    }
}

# ===== Execucao Principal =====
# Executa todas as verificacoes e instalacoes com barra de progresso (descarta retornos para nao exibir True)
try { 
    $null = Ensure-Git 
} 
catch { 
    $errMsg = $_.Exception.Message
    $errorPrefix = 'LOG - Erro ao verificar Git: '
    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
    Write-Host $errMsg -ForegroundColor Red 
}
try { 
    $null = Ensure-PowerShell7 
} 
catch { 
    $errMsg = $_.Exception.Message
    $errorPrefix = 'LOG - Erro ao verificar PowerShell: '
    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
    Write-Host $errMsg -ForegroundColor Red 
}
try { 
    $null = Ensure-NVM 
} 
catch { 
    $errMsg = $_.Exception.Message
    $errorPrefix = 'LOG - Erro ao verificar NVM: '
    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
    Write-Host $errMsg -ForegroundColor Red 
}
try { 
    $null = Ensure-NodeLTS 
} 
catch { 
    $errMsg = $_.Exception.Message
    $errorPrefix = 'LOG - Erro ao verificar Node.js: '
    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
    Write-Host $errMsg -ForegroundColor Red 
}
try { 
    $null = Ensure-Yarn 
} 
catch { 
    $errMsg = $_.Exception.Message
    $errorPrefix = 'LOG - Erro ao verificar Yarn: '
    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
    Write-Host $errMsg -ForegroundColor Red 
}
try { 
    $null = Ensure-OhMyPosh 
} 
catch { 
    $errMsg = $_.Exception.Message
    $errorPrefix = 'LOG - Erro ao verificar Oh My Posh: '
    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
    Write-Host $errMsg -ForegroundColor Red 
}
try { 
    $null = Ensure-NerdFontsViaScoop 
} 
catch { 
    $errMsg = $_.Exception.Message
    $errorPrefix = 'LOG - Erro ao verificar Nerd Fonts: '
    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
    Write-Host $errMsg -ForegroundColor Red 
}
try { 
    $null = Ensure-PowerShellModules 
} 
catch { 
    $errMsg = $_.Exception.Message
    $errorPrefix = 'LOG - Erro ao verificar modulos PowerShell: '
    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
    Write-Host $errMsg -ForegroundColor Red 
}
try { 
    $null = Configure-PSReadLine 
} 
catch { 
    $errMsg = $_.Exception.Message
    $errorPrefix = 'LOG - Erro ao configurar PSReadLine: '
    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
    Write-Host $errMsg -ForegroundColor Red 
}
try { 
    $null = Ensure-ClaudeCode 
} 
catch { 
    #$errMsg = $_.Exception.Message
    $errorPrefix = 'LOG - Erro ao verificar Claude Code: '
    Write-Host $errorPrefix -NoNewline -ForegroundColor Red
    #Write-Host $errMsg -ForegroundColor Red 
}

# Remove a barra de progresso (escreve linha em branco para limpar)
            Write-Host ''

# ===== Sincronizacao de Perfis =====
# Sincroniza o perfil atual com todos os outros perfis do PowerShell
try {
    $null = Sync-PowerShellProfiles
}
catch {

}

# ===== Opcao Futura: Carregar do Gist GitHub =====
# Quando estiver pronto, descomente e configure a URL do seu Gist:
# Use a funcao Update-ProfileFromGist com o parametro -GistUrl





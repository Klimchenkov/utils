#!/bin/bash
# Скрипт для выпуска клиентских сертификатов + создание готовых установщиков
# для macOS (пользователи из MAC_USERS) и Windows (все остальные)
# + автоматическая упаковка в ZIP
# Версия: финальная с поддержкой Opera GX и корректной записью реестра (string[])

set -e

CA_DIR="/etc/ssl/ca"
CA_KEY="$CA_DIR/ca.key"
CA_CRT="$CA_DIR/ca.crt"
ISSUED_DIR="$CA_DIR/issued"
DIST_DIR="$CA_DIR/dist"          # папка для готовых дистрибутивов
DAYS_VALID=365

# Проверка наличия файлов CA
if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_CRT" ]; then
    echo "Ошибка: файлы CA не найдены в $CA_DIR"
    exit 1
fi

mkdir -p "$ISSUED_DIR" "$DIST_DIR"

# Список ВСЕХ пользователей (для генерации сертификатов)
USERS=(
    # Добавьте пользователей
)

# Список пользователей, для которых нужен macOS-установщик
MAC_USERS=(
    # Добавьте пользователей MAC
)

# Автоматически определяем пользователей для Windows (все, кроме MAC_USERS)
WINDOWS_USERS=()
for USER in "${USERS[@]}"; do
    if [[ ! " ${MAC_USERS[@]} " =~ " ${USER} " ]]; then
        WINDOWS_USERS+=("$USER")
    fi
done

# Общие поля сертификата
COUNTRY="RU"
STATE="Moscow"
LOCALITY="Moscow"
ORGANIZATION="ORG"
ORG_UNIT="ADMIN"

# Функция создания установочной папки для macOS
create_macos_installer() {
    local USER=$1
    local PASSWORD=$2
    local USER_DIR="$ISSUED_DIR/$USER"
    local INSTALLER_DIR="$DIST_DIR/$USER"

    mkdir -p "$INSTALLER_DIR"

    cp "$CA_CRT" "$INSTALLER_DIR/ca.crt"
    cp "$USER_DIR/$USER.p12" "$INSTALLER_DIR/user.p12"

    cat > "$INSTALLER_DIR/install.command" <<EOF
#!/bin/bash
# Автоматическая установка сертификатов для доступа к защищённому сайту

cd "\$(dirname "\$0")"

echo "Установка сертификатов для пользователя $USER"
echo "------------------------------------------------"

# Удаляем старые версии сертификатов (чтобы избежать путаницы)
echo "Удаление старых сертификатов..."
security delete-certificate -c "$USER" ~/Library/Keychains/login.keychain-db 2>/dev/null
security delete-certificate -c "$USER" /Library/Keychains/System.keychain 2>/dev/null
sudo security delete-certificate -c "ADMIN" /Library/Keychains/System.keychain 2>/dev/null

# Добавляем корневой CA в доверенные (системная связка)
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt
if [ \$? -ne 0 ]; then
    echo "Ошибка при добавлении CA. Возможно, отменено пользователем."
    exit 1
fi

# Импортируем клиентский сертификат в системную связку с разрешением для Safari и Chrome
sudo security import user.p12 -k /Library/Keychains/System.keychain -P '$PASSWORD' -A -T /Applications/Safari.app -T /Applications/Google\ Chrome.app
if [ \$? -ne 0 ]; then
    echo "Ошибка при импорте .p12. Проверьте пароль."
    exit 1
fi

echo "Готово! Теперь вы можете открыть сайт https://analytics.асм-авто.рф"
echo "Если браузер запросит выбор сертификата, выберите '$USER'."
EOF

    chmod +x "$INSTALLER_DIR/install.command"

    cat > "$INSTALLER_DIR/README.txt" <<EOF
Инструкция по установке:

1. Распакуйте эту папку (если она в архиве).
2. Дважды кликните на файл install.command.
3. Система запросит пароль администратора (ваш пароль от Mac) – введите его.
4. Готово! Теперь сайт https://analytics.асм-авто.рф откроется без проблем в Safari и Chrome.

Примечание: пароль от .p12 уже встроен в скрипт, вводить его не нужно.
EOF

    echo "Создан установщик для $USER в $INSTALLER_DIR"
}

# Функция создания установочной папки для Windows (исправленная, с переходом в папку скрипта и корректным типом реестра)
create_windows_installer() {
    local USER=$1
    local PASSWORD=$2
    local USER_DIR="$ISSUED_DIR/$USER"
    local INSTALLER_DIR="$DIST_DIR/windows_$USER"

    mkdir -p "$INSTALLER_DIR"

    cp "$CA_CRT" "$INSTALLER_DIR/ca.crt"
    cp "$USER_DIR/$USER.p12" "$INSTALLER_DIR/user.p12"

    # Экранируем пароль для вставки в PowerShell (одинарные кавычки удваиваем)
    PASSWORD_ESCAPED=$(echo "$PASSWORD" | sed "s/'/''/g")

    # Создаём временный файл с шаблоном, используя маркеры __USER__ и __PASSWORD__
    cat > "$INSTALLER_DIR/install.ps1.template" <<'EOF'
# install.ps1 - Установка клиентского сертификата для браузеров на Windows
# Сгенерировано для пользователя __USER__

param(
    [string]$P12File = "user.p12",
    [string]$CACrt = "ca.crt",
    [string]$CertPassword = '__PASSWORD__',
    [string]$SitePattern = "https://analytics.xn----7sbbi1cpqm.xn--p1ai"
)

# Переходим в папку, где находится скрипт (чтобы файлы находились независимо от текущей директории)
Set-Location -Path $PSScriptRoot

# Функция для вывода сообщения и ожидания нажатия
function Show-MessageAndWait {
    param([string]$Message, [string]$ForegroundColor = "Yellow")
    Write-Host ""
    Write-Host $Message -ForegroundColor $ForegroundColor
    Write-Host "Нажмите Enter для выхода..." -ForegroundColor Cyan
    Read-Host
}

# Основной блок с обработкой ошибок
try {
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "Установка сертификата для пользователя __USER__" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    # Проверка наличия файлов
    Write-Host "🔍 Проверка файлов..." -ForegroundColor Yellow
    if (-not (Test-Path $P12File)) {
        throw "❌ Файл $P12File не найден в текущей папке."
    }
    if (-not (Test-Path $CACrt)) {
        throw "❌ Файл $CACrt не найден в текущей папке."
    }
    Write-Host "✅ Все файлы найдены" -ForegroundColor Green

    # 1. Импортируем корневой CA в хранилище доверенных корневых центров (CurrentUser)
    Write-Host ""
    Write-Host "📦 Шаг 1: Импорт корневого CA в доверенные..." -ForegroundColor Yellow
    try {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $cert.Import($CACrt)
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList "Root", "CurrentUser"
        $store.Open("ReadWrite")
        $store.Add($cert)
        $store.Close()
        Write-Host "✅ Корневой CA успешно добавлен в хранилище доверенных корневых центров" -ForegroundColor Green
    }
    catch {
        throw "❌ Ошибка при импорте CA: $_"
    }

    # 2. Импортируем клиентский сертификат .p12 в личное хранилище (CurrentUser)
    Write-Host ""
    Write-Host "📦 Шаг 2: Импорт клиентского сертификата..." -ForegroundColor Yellow
    try {
        $clientCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $clientCert.Import($P12File, $CertPassword, "DefaultKeySet")
        $myStore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList "My", "CurrentUser"
        $myStore.Open("ReadWrite")
        $myStore.Add($clientCert)
        $myStore.Close()
        Write-Host "✅ Клиентский сертификат успешно импортирован" -ForegroundColor Green
        Write-Host "   Отпечаток (Thumbprint): $($clientCert.Thumbprint)" -ForegroundColor Gray
    }
    catch {
        throw "❌ Ошибка при импорте клиентского сертификата. Проверьте пароль.\n$_"
    }

    # 3. Настройка браузеров для автоматического выбора сертификата (политика AutoSelectCertificateForUrls)
    Write-Host ""
    Write-Host "⚙️  Шаг 3: Настройка браузеров для автоматического выбора сертификата..." -ForegroundColor Yellow

    # Получаем CN издателя из сертификата CA
    $issuerName = $cert.Subject
    $issuerCN = "ADMIN"  # значение по умолчанию
    if ($issuerName -match "CN=([^,]+)") {
        $issuerCN = $matches[1].Trim()
        Write-Host "   Издатель (CA): $issuerCN" -ForegroundColor Gray
    }

    $policyJson = @"
{
    "pattern": "$SitePattern",
    "filter": {
        "ISSUER": {
            "CN": "$issuerCN"
        }
    }
}
"@

    # 3.1 Настройка для Chrome
    Write-Host "   ▶️ Настройка Chrome..." -ForegroundColor Gray
    $regPathChrome = "HKCU:\Software\Policies\Google\Chrome"
    $regValueName = "AutoSelectCertificateForUrls"

    if (-not (Test-Path $regPathChrome)) {
        New-Item -Path $regPathChrome -Force | Out-Null
        Write-Host "      Создан путь реестра для Chrome" -ForegroundColor Gray
    }

    $existingValue = Get-ItemProperty -Path $regPathChrome -Name $regValueName -ErrorAction SilentlyContinue
    if ($existingValue) {
        $currentArray = $existingValue.$regValueName
        $newArray = [string[]]($currentArray + @($policyJson))
        Set-ItemProperty -Path $regPathChrome -Name $regValueName -Value $newArray
        Write-Host "      Добавлена новая политика к существующим" -ForegroundColor Gray
    } else {
        Set-ItemProperty -Path $regPathChrome -Name $regValueName -Value ([string[]]@($policyJson))
        Write-Host "      Установлена новая политика" -ForegroundColor Gray
    }
    Write-Host "   ✅ Политика Chrome настроена" -ForegroundColor Green

    # 3.2 Настройка для Opera (обычная)
    Write-Host "   ▶️ Настройка Opera..." -ForegroundColor Gray
    $regPathOpera = "HKCU:\Software\Policies\Opera Software\Opera Stable"
    if (-not (Test-Path $regPathOpera)) {
        New-Item -Path $regPathOpera -Force | Out-Null
        Write-Host "      Создан путь реестра для Opera" -ForegroundColor Gray
    }
    Set-ItemProperty -Path $regPathOpera -Name $regValueName -Value ([string[]]@($policyJson))
    Write-Host "   ✅ Политика Opera настроена" -ForegroundColor Green

    # 3.3 Настройка для Opera GX
    Write-Host "   ▶️ Настройка Opera GX..." -ForegroundColor Gray
    $regPathOperaGX = "HKCU:\Software\Policies\Opera Software\Opera GX Stable"
    if (-not (Test-Path $regPathOperaGX)) {
        New-Item -Path $regPathOperaGX -Force | Out-Null
        Write-Host "      Создан путь реестра для Opera GX" -ForegroundColor Gray
    }
    Set-ItemProperty -Path $regPathOperaGX -Name $regValueName -Value ([string[]]@($policyJson))
    Write-Host "   ✅ Политика Opera GX настроена" -ForegroundColor Green

    Write-Host ""
    Write-Host "✅ Все браузеры настроены. Сертификат с издателем '$issuerCN' будет автоматически выбираться для $SitePattern" -ForegroundColor Green

    # 4. Открываем страницу политик Chrome для проверки
    Write-Host ""
    Write-Host "🌐 Шаг 4: Открываем страницу политик Chrome для проверки..." -ForegroundColor Yellow
    try {
        Start-Process "chrome://policy"
        Write-Host "✅ Страница политик открыта в Chrome" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️ Не удалось открыть Chrome автоматически. Откройте вручную: chrome://policy" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "✅ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!" -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "👉 Теперь вы можете открыть сайт: $SitePattern/admin/login/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Если сайт не открывается автоматически:" -ForegroundColor Yellow
    Write-Host "1. Проверьте, что Chrome применил политику (chrome://policy)" -ForegroundColor Yellow
    Write-Host "2. Перезапустите браузер полностью (Chrome, Opera, Opera GX)" -ForegroundColor Yellow
    Write-Host "3. При первом входе может появиться окно выбора сертификата - выберите свой" -ForegroundColor Yellow
}
catch {
    Write-Host ""
    Write-Host "❌ ПРОИЗОШЛА ОШИБКА:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    # Всегда ждём нажатия перед выходом
    Write-Host ""
    Write-Host "Нажмите Enter для выхода..." -ForegroundColor Cyan
    Read-Host
}
EOF

    # Подставляем маркеры с помощью sed (разделитель #, чтобы избежать конфликтов с / в путях)
    sed -e "s#__USER__#$USER#g" -e "s#__PASSWORD__#$PASSWORD_ESCAPED#g" \
        "$INSTALLER_DIR/install.ps1.template" > "$INSTALLER_DIR/install.ps1.tmp"

    # Добавляем UTF-8 BOM в начало файла (чтобы PowerShell правильно читал русские буквы)
    printf '\xEF\xBB\xBF' > "$INSTALLER_DIR/install.ps1"
    cat "$INSTALLER_DIR/install.ps1.tmp" >> "$INSTALLER_DIR/install.ps1"
    rm "$INSTALLER_DIR/install.ps1.template" "$INSTALLER_DIR/install.ps1.tmp"

    # Создаём батник для удобного запуска (обходит политику выполнения и всегда работает из своей папки)
    cat > "$INSTALLER_DIR/install.bat" <<EOF
@echo off
cd /d "%~dp0"
echo Запуск установщика сертификатов...
echo Если появится запрос разрешения, нажмите "Да" или "Выполнить".
echo.

powershell -ExecutionPolicy Bypass -File "install.ps1"

echo.
echo Скрипт завершён. Нажмите любую клавишу для выхода...
pause > nul
EOF

    # Создаём README для Windows
    cat > "$INSTALLER_DIR/README.txt" <<EOF
ИНСТРУКЦИЯ ПО УСТАНОВКЕ (Windows)

📁 В этой папке находятся все необходимые файлы.

🚀 Самый простой способ установки:
   Дважды кликните на файл "install.bat" (синий значок).
   Следуйте инструкциям на экране.

🛠️ Если хотите запустить скрипт PowerShell напрямую:
   - Нажмите правой кнопкой мыши на "install.ps1"
   - Выберите "Выполнить с помощью PowerShell"
   - При предупреждении о политике выполнения нажмите "Да"

После установки:
1. Перезапустите браузеры, которые вы используете (Chrome, Opera, Opera GX).
2. Откройте сайт: https://analytics.xn----7sbbi1cpqm.xn--p1ai/admin/login/

🔐 Пароль от сертификата уже встроен в скрипт, вводить его не нужно.

🌐 Скрипт автоматически настраивает Chrome, Opera и Opera GX.
   Если вы используете другие браузеры (например, Firefox), потребуется ручная настройка.

❗ При возникновении ошибок окно не закроется автоматически — вы увидите сообщение и сможете сделать скриншот.
EOF

    echo "Создан Windows-установщик для $USER в $INSTALLER_DIR"
}

# Основной цикл по всем пользователям
for USER in "${USERS[@]}"; do
    echo "========================================="
    echo "Генерация сертификата для пользователя: $USER"
    echo "========================================="

    # Запрос пароля для .p12 (непустой)
    while true; do
        read -s -p "Введите пароль для PKCS#12 контейнера (не пустой): " PASSWORD
        echo
        read -s -p "Подтвердите пароль: " PASSWORD_CONFIRM
        echo
        if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
            echo "Пароли не совпадают. Попробуйте снова."
        elif [ -z "$PASSWORD" ]; then
            echo "Пароль не может быть пустым (для macOS требуется непустой пароль)."
        else
            break
        fi
    done

    USER_DIR="$ISSUED_DIR/$USER"
    mkdir -p "$USER_DIR"
    cd "$USER_DIR"

    # 1. Генерация приватного ключа пользователя
    openssl genrsa -out "$USER.key" 2048

    # 2. Создание запроса на подпись (CSR)
    openssl req -new -key "$USER.key" -out "$USER.csr" -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORG_UNIT/CN=$USER"

    # 3. Подпись сертификата нашим CA (с extendedKeyUsage для клиентской аутентификации)
    openssl x509 -req -in "$USER.csr" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial -out "$USER.crt" -days "$DAYS_VALID" -sha256 -extfile <(echo "extendedKeyUsage=clientAuth")

    # 4. Создание PKCS#12-файла, совместимого с macOS и Windows
    openssl pkcs12 -export \
        -out "$USER.p12" \
        -inkey "$USER.key" \
        -in "$USER.crt" \
        -certfile "$CA_CRT" \
        -passout pass:"$PASSWORD" \
        -keypbe PBE-SHA1-3DES \
        -certpbe PBE-SHA1-3DES \
        -macalg sha1

    echo "Сертификат для $USER создан в $USER_DIR"
    echo "  - Приватный ключ: $USER.key"
    echo "  - Сертификат: $USER.crt"
    echo "  - PKCS#12 для браузера: $USER.p12 (пароль задан)"
    echo

    # Создаём установщик в зависимости от типа пользователя
    if [[ " ${MAC_USERS[@]} " =~ " ${USER} " ]]; then
        create_macos_installer "$USER" "$PASSWORD"
    else
        create_windows_installer "$USER" "$PASSWORD"
    fi
done

echo "Готово. Все сертификаты созданы."
echo "Установочные папки находятся в $DIST_DIR"

# Упаковываем macOS-установщики
cd "$DIST_DIR"
for USER in "${MAC_USERS[@]}"; do
    if [ -d "$USER" ]; then
        echo "Упаковка macOS-установщика для $USER в ZIP..."
        zip -r "${USER}.zip" "$USER"
        echo "Создан архив: ${USER}.zip"
    else
        echo "Предупреждение: папка для macOS $USER не найдена, пропускаем."
    fi
done

# Упаковываем Windows-установщики
for USER in "${WINDOWS_USERS[@]}"; do
    if [ -d "windows_$USER" ]; then
        echo "Упаковка Windows-установщика для $USER в ZIP..."
        zip -r "windows_${USER}.zip" "windows_$USER"
        echo "Создан архив: windows_${USER}.zip"
    else
        echo "Предупреждение: папка для Windows $USER не найдена, пропускаем."
    fi
done

echo ""
echo "Готово. ZIP-архивы для пользователей:"
ls -la "$DIST_DIR"/*.zip 2>/dev/null || echo "Архивы не созданы."
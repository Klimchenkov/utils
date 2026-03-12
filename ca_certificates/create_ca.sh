#!/bin/bash
# Скрипт для создания нового корневого Центра сертификации (CA)
# Запускать от root

set -e  # остановиться при любой ошибке

# Конфигурация
CA_DIR="/etc/ssl/ca"
CA_KEY="$CA_DIR/ca.key"
CA_CRT="$CA_DIR/ca.crt"
DAYS_VALID=3650  # 10 лет

# Поля сертификата (можно изменить под свои нужды)
COUNTRY="RU"
STATE="Moscow"
LOCALITY="Moscow"
ORGANIZATION="ASM"
ORG_UNIT="ADMIN"
COMMON_NAME="ADMIN"  # для корневого CA обычно используется осмысленное имя

# Функция для запроса пароля
ask_passphrase() {
    while true; do
        read -s -p "Введите пароль для ключа CA (не пустой): " PASSPHRASE
        echo
        read -s -p "Подтвердите пароль: " PASSPHRASE_CONFIRM
        echo
        if [ "$PASSPHRASE" != "$PASSPHRASE_CONFIRM" ]; then
            echo "Пароли не совпадают. Попробуйте снова."
        elif [ -z "$PASSPHRASE" ]; then
            echo "Пароль не может быть пустым."
        else
            break
        fi
    done
}

# Проверка, не существует ли уже CA
if [ -f "$CA_KEY" ] || [ -f "$CA_CRT" ]; then
    echo "Ошибка: файлы CA уже существуют в $CA_DIR. Удалите их вручную, если хотите пересоздать."
    exit 1
fi

# Создаём директорию
mkdir -p "$CA_DIR"
cd "$CA_DIR"

# Запрашиваем пароль
ask_passphrase

echo "Генерация ключа CA..."
# Генерируем ключ с AES-256 шифрованием (защищён паролем)
openssl genrsa -aes256 -out "$CA_KEY" -passout pass:"$PASSPHRASE" 4096

echo "Генерация самоподписанного сертификата CA..."
# Создаём сертификат (10 лет)
openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days "$DAYS_VALID" \
    -out "$CA_CRT" -passin pass:"$PASSPHRASE" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORG_UNIT/CN=$COMMON_NAME"

# Устанавливаем правильные права (ключ только для чтения root)
chmod 600 "$CA_KEY"
chmod 644 "$CA_CRT"

# Создаём папку для выданных сертификатов (опционально)
mkdir -p "$CA_DIR/issued"

# Вывод отпечатков для проверки
echo ""
echo "✅ Корневой CA успешно создан в $CA_DIR"
echo "   Приватный ключ: $CA_KEY (защищён паролем)"
echo "   Сертификат: $CA_CRT"
echo ""
echo "Отпечаток (SHA256):"
openssl x509 -in "$CA_CRT" -fingerprint -sha256 -noout
echo "Отпечаток (SHA1):"
openssl x509 -in "$CA_CRT" -fingerprint -sha1 -noout
echo ""
echo "Срок действия: $(openssl x509 -in "$CA_CRT" -enddate -noout | cut -d= -f2)"
echo ""
echo "⚠️  Важно: храните пароль от ключа в надёжном месте. Без него вы не сможете выпускать новые сертификаты."
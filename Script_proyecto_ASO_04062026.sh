#!/bin/bash

set -e

crear_cuenta() {
    local cuenta="$1"
    local clave="$2"

    useradd \
        --create-home \
        --home-dir "/home/$cuenta" \
        --shell /bin/bash \
        "$cuenta"

    echo "${cuenta}:${clave}" | chpasswd
}

preparar_directorios() {
    local cuenta="$1"

    install -d "/home/$cuenta/public_html"

    chown -R "$cuenta:$cuenta" "/home/$cuenta"
    chmod 755 "/home/$cuenta"
}

registrar_bd() {
    local cuenta="$1"
    local clave="$2"
    local esquema="${cuenta}_hosting"

    mariadb <<SQL
CREATE DATABASE IF NOT EXISTS ${esquema};
CREATE USER IF NOT EXISTS '${cuenta}'@'localhost' IDENTIFIED BY '${clave}';
GRANT ALL PRIVILEGES ON ${esquema}.* TO '${cuenta}'@'localhost';
FLUSH PRIVILEGES;
SQL

    echo "$esquema"
}

generar_inicio() {
    local cuenta="$1"
    local clave="$2"
    local esquema="$3"

    cat > "/home/$cuenta/public_html/index.php" <<HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Servicio Activo</title>
</head>
<body>

<h1>Hosting Configurado</h1>

<p>Su entorno ha sido generado correctamente.</p>

<ul>
<li><b>Usuario:</b> $cuenta</li>
<li><b>Clave:</b> $clave</li>
<li><b>Base de datos:</b> $esquema</li>
<li><b>Dominio:</b> http://$cuenta.com</li>
</ul>

</body>
</html>
HTML

    chown "$cuenta:$cuenta" "/home/$cuenta/public_html/index.php"
}

configurar_nginx() {
    local cuenta="$1"

    local archivo="/etc/nginx/sites-available/${cuenta}.com"

    cat > "$archivo" <<NGINX
server {
    listen 80;

    server_name ${cuenta}.com;

    root /home/${cuenta}/public_html;

    index index.php index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }
}
NGINX

    ln -sf "$archivo" "/etc/nginx/sites-enabled/${cuenta}.com"

    nginx -t >/dev/null 2>&1
    systemctl reload nginx
}

echo "=== REGISTRO DE NUEVO CLIENTE ==="

read -rp "Nombre de usuario: " CLIENTE
read -rsp "Contraseña: " CLAVE
echo

if getent passwd "$CLIENTE" >/dev/null; then
    echo "La cuenta ya existe."
    exit 1
fi

crear_cuenta "$CLIENTE" "$CLAVE"

preparar_directorios "$CLIENTE"

BD_CREADA=$(registrar_bd "$CLIENTE" "$CLAVE")

generar_inicio "$CLIENTE" "$CLAVE" "$BD_CREADA"

configurar_nginx "$CLIENTE"

echo
echo "Cliente creado exitosamente"
echo "Usuario : $CLIENTE"
echo "BD      : $BD_CREADA"
echo "URL     : http://$CLIENTE.com"
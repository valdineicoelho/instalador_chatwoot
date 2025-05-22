#!/bin/bash

echo "=== INSTALADOR CHATWOOT DOCKER ==="

# Solicitar domínio
read -p "Digite o domínio completo (ex: chatwoot.suporteuniplus.com.br): " DOMINIO

# Criar swap se necessário
if [ "$(free | grep Swap | awk '{print $2}')" == "0" ]; then
  echo "Criando swap de 2GB..."
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Atualizar sistema e instalar dependências
apt update && apt install -y docker.io docker-compose nginx certbot python3-certbot-nginx openssl git

# Diretório de instalação
mkdir -p /opt/chatwoot
cd /opt/chatwoot

# Criar docker-compose.yml
cat > docker-compose.yml <<EOF
version: "3.8"

services:
  chatwoot:
    image: chatwoot/chatwoot:latest
    container_name: chatwoot
    env_file: .env
    ports:
      - "3000:3000"
    depends_on:
      - postgres
      - redis
    restart: always

  postgres:
    image: postgres:14
    container_name: chatwoot_postgres
    environment:
      POSTGRES_DB: chatwoot
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - pgdata:/var/lib/postgresql/data
    restart: always

  redis:
    image: redis:7
    container_name: chatwoot_redis
    volumes:
      - redisdata:/data
    restart: always

volumes:
  pgdata:
  redisdata:
EOF

# Gerar SECRET_KEY_BASE
SECRET_KEY=$(openssl rand -hex 64)

# Criar .env
cat > .env <<EOF
RAILS_ENV=production
SECRET_KEY_BASE=$SECRET_KEY
FRONTEND_URL=https://$DOMINIO
INSTALLATION_ENV=docker

POSTGRES_HOST=postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DATABASE=chatwoot

REDIS_URL=redis://redis:6379
EOF

# Criar configuração Nginx
cat > /etc/nginx/sites-available/chatwoot <<EOF
server {
    listen 80;
    server_name $DOMINIO;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Ativar site no Nginx
ln -s /etc/nginx/sites-available/chatwoot /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# Obter certificado SSL
certbot --nginx -d $DOMINIO --non-interactive --agree-tos -m admin@$DOMINIO

# Subir Chatwoot
docker-compose up -d

echo "=================================="
echo "✅ Chatwoot disponível em: https://$DOMINIO"
echo "Crie sua conta de administrador ao acessar pela primeira vez."

#!/bin/bash

# === CONFIGURÁVEIS ===
DOMAIN="chatwoot.suporteuniplus.com.br"
ADMIN_EMAIL="admin@suporte.com.br"
ADMIN_PASSWORD="123456"

echo "🚀 Atualizando pacotes..."
sudo apt update && sudo apt upgrade -y

echo "📦 Instalando dependências..."
sudo apt install -y git curl docker.io docker-compose nginx certbot python3-certbot-nginx

echo "📁 Clonando Chatwoot..."
git clone https://github.com/chatwoot/chatwoot.git /opt/chatwoot
cd /opt/chatwoot

echo "⚙️ Copiando .env padrão..."
cp .env.example .env

echo "📝 Atualizando .env..."
sed -i "s|FRONTEND_URL=.*|FRONTEND_URL=https://$DOMAIN|" .env
echo "FORCE_SSL=true" >> .env

echo "📝 Criando docker-compose.override.yml..."
cat <<EOF > docker-compose.override.yml
version: '3'
services:
  rails:
    environment:
      - RAILS_ENV=production
      - FRONTEND_URL=https://$DOMAIN
      - FORCE_SSL=true
EOF

echo "🐳 Construindo containers..."
docker-compose build

echo "🔼 Subindo containers..."
docker-compose up -d

echo "🌐 Configurando NGINX..."
cat <<EOF | sudo tee /etc/nginx/sites-available/chatwoot
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/chatwoot /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx

echo "🔒 Instalando certificado SSL com Certbot..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL

echo "⏳ Aguardando containers iniciarem..."
sleep 20

echo "👤 Criando usuário admin..."
docker exec -i chatwoot-rails-1 bash <<EOF
bundle exec rails db:chatwoot_prepare
bundle exec rails runner "user = User.create!(email: '$ADMIN_EMAIL', password: '$ADMIN_PASSWORD', password_confirmation: '$ADMIN_PASSWORD', account: Account.first, confirmed_at: Time.now); user.add_role :administrator"
EOF

echo ""
echo "✅ Chatwoot instalado com sucesso!"
echo "🔗 Acesse: https://$DOMAIN"
echo "📧 Login: $ADMIN_EMAIL"
echo "🔐 Senha: $ADMIN_PASSWORD"

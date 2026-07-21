# Production deploy на single-node k3s (ручной, через SSH)

Инструкция рассчитана на чистый Ubuntu VPS (рекомендуемый минимум: 2 vCPU, 4 GiB RAM, 40+ GiB SSD), один namespace `chatdetective`, ingress-nginx, cert-manager с Let's Encrypt и образы из GHCR.

**Модель деплоя:** все `kubectl`/`helm` команды выполняются на VPS. Kubernetes API (порт 6443) в интернет не публикуется. GitHub Actions публикует Docker-образы; **selective deploy** (один microservice за раз) описан в [DEPLOY-CI.md](./DEPLOY-CI.md). Полный перекат release — `./scripts/deploy.sh` на VPS или workflow_dispatch с `full_deploy=true`.

Секретный values-файл существует в единственном экземпляре на VPS с mode `600` и никогда не попадает в git.

## 0. Что нужно подготовить заранее (внешние gates)

- Домен и доступ к DNS (A/AAAA запись на IP VPS).
- Production Telegram bot token от @BotFather (с включённым Business Mode).
- Опубликованные юридические документы (см. `ProjectDocs/legal`): пользовательское соглашение, политика обработки ПДн, согласие на обработку ПДн — проверенные юристом, с публичными URL. **Без них публичный запуск невозможен**: бот блокирует главное меню до принятия документов, а Helm откажется рендерить прод-профиль с пустыми `legal.*`.
- GitHub PAT с `read:packages` для pull приватных образов из GHCR.
- SSH-доступ root (или sudo) на VPS.

## 1. Bootstrap Ubuntu

```bash
apt-get update && apt-get upgrade -y
apt-get install -y curl git ufw
timedatectl set-timezone UTC
```

## 2. DNS и firewall

1. Создайте DNS `A`/`AAAA` запись, например `bot.example.com`, на публичный IP VPS.
2. Откройте только 22/80/443. Порт 6443 наружу не открывается вообще:

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

## 3. Установка k3s (без Traefik)

Для nginx ingress отключаем встроенный Traefik, чтобы в кластере был один ingress controller:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
kubectl get storageclass   # должен быть local-path
```

`local-path` используется PVC для Postgres, RabbitMQ и chat-export-service.

Установите Helm:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## 4. Namespace

```bash
kubectl create namespace chatdetective
kubectl label namespace chatdetective app.kubernetes.io/name=chatdetective
```

## 5. ingress-nginx

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.ingressClassResource.name=nginx \
  --set controller.ingressClass=nginx
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

Для single-node k3s встроенный ServiceLB выдаст внешний IP ноды.

## 6. cert-manager и Let's Encrypt

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

cat <<'YAML' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: admin@example.com   # ЗАМЕНИТЬ на реальный контакт
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
YAML
```

Для первых экспериментов замените `server` на staging endpoint `https://acme-staging-v02.api.letsencrypt.org/directory`, чтобы не упереться в лимиты Let's Encrypt.

## 7. GHCR pull secret

```bash
kubectl -n chatdetective create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=<GITHUB_USERNAME> \
  --docker-password=<PAT_WITH_read:packages>
```

## 8. Checkout репозитория и секретные values

```bash
mkdir -p /root/chatdetective
git clone https://github.com/ChatDetectiveORG/k8s-cluster.git /root/k8s-cluster
cd /root/k8s-cluster/helm/chatdetective-dev
```

### 8.1 Секреты (только на VPS, mode 600)

```bash
install -m 600 values-k3s-secrets.example.yaml /root/chatdetective/values-k3s-secrets.yaml
vim /root/chatdetective/values-k3s-secrets.yaml
```

Заполните все `CHANGE_ME`:

- `runtime.masterKey` — ровно 16/24/32 байта: `openssl rand -base64 24 | head -c 32`. **Потеря ключа = потеря всех зашифрованных данных. Сохраните копию в надёжном офлайн-хранилище.**
- `postgresql.auth.password`, `rabbitmq.auth.password` — `openssl rand -hex 24`.
- `telegram.botToken`, `telegram.botUsername`.
- `telegram.publicUrl` — `https://<домен>/bot$(openssl rand -hex 24)` (неугадываемый путь).
- `telegram.webhookSecret` — `openssl rand -hex 32`. Telegram присылает его в заголовке `X-Telegram-Bot-Api-Secret-Token`; api-gateway отклоняет запросы без него.
- `legal.*` — реальные URL опубликованных документов и их версия.
- `api-gateway.ingress.host` / `tls.hosts` — ваш домен.

### 8.2 Пиннинг образов

Каждый сервис собирается своим GitHub Actions workflow и публикует `ghcr.io/chatdetectiveorg/<service>:<commit-sha>` (и `latest`). В прод деплоим только по commit SHA:

```bash
install -m 644 values-k3s-images.example.yaml /root/chatdetective/values-k3s-images.yaml
vim /root/chatdetective/values-k3s-images.yaml   # заменить нули на реальные SHA каждого сервиса
```

Прод-рендер намеренно падает при `tag: latest` (см. `templates/production-guards.yaml`).

## 9. Деплой

```bash
cd /root/k8s-cluster
./scripts/deploy.sh
```

Скрипт: проверяет наличие и права секретного файла, наличие `ghcr-pull-secret`, собирает Helm dependencies, прогоняет рендер (на этом шаге срабатывают production guards: пустые секреты, placeholder domain/legal URL, `latest`-теги и event-loop ≠ 1 replica валят деплой до каких-либо изменений в кластере), затем выполняет `helm upgrade --install --atomic` и ждёт rollout всех Deployment.

Обновление версии = обновить SHA в `/root/chatdetective/values-k3s-images.yaml` и снова запустить `./scripts/deploy.sh`.

## 10. Smoke-проверки после деплоя

TLS и ingress:

```bash
kubectl -n chatdetective get ingress,certificate
curl -I https://<домен>/healthz          # 200 от api-gateway
```

Webhook зарегистрирован и аутентифицирован:

```bash
curl "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
# url совпадает с telegram.publicUrl, last_error_message пуст

# запрос без секретного заголовка должен получить 401:
curl -o /dev/null -s -w "%{http_code}\n" -X POST "https://<домен>/bot<секретный-путь>" -d '{}'
```

Функциональный прогон в Telegram:

1. `/start` — бот показывает ссылки на документы и кнопку «Принимаю условия»; после нажатия открывается главное меню (повторный `/start` больше не просит согласие).
2. Подключите бота в профиле (Business connection) и проверьте уведомление об edit/delete.
3. Купите уровень за 1 XTR, проверьте зачисление.
4. Экспорт чата за 1 XTR.

## 11. Бэкапы и восстановление

Ежедневный бэкап с retention 14 дней:

```bash
/root/k8s-cluster/scripts/backup-postgres.sh
crontab -e
# 30 3 * * * /root/k8s-cluster/scripts/backup-postgres.sh >> /var/log/chatdetective-backup.log 2>&1
```

Восстановление (интерактивное подтверждение, DROP всех таблиц):

```bash
/root/k8s-cluster/scripts/restore-postgres.sh /root/chatdetective/backups/chatdetective-<дата>.sql.gz
```

Бэкапы содержат зашифрованные пользовательские данные; для их чтения нужен `MASTER_KEY`. Храните офлайн-копии и бэкапов, и ключа.

## 12. Rollback

```bash
helm -n chatdetective history chatdetective
helm -n chatdetective rollback chatdetective <REVISION>
```

Если откат затрагивает схему БД — сначала восстановите совместимый бэкап (раздел 11), затем откатывайте релиз.

## 13. Схема БД и миграции

Сервисы создают таблицы при старте через `CreateTable IfNotExists` (bootstrap). Для первого деплоя на пустую БД этого достаточно. **До первого изменения схемы в проде обязательно внедрить версионированные миграции** (например, golang-migrate): `CreateTable IfNotExists` не изменяет существующие таблицы, поэтому любое изменение моделей после запуска без миграций приведёт к расхождению схемы.

## 14. Эксплуатация

```bash
kubectl -n chatdetective get pods
kubectl -n chatdetective top pods
kubectl -n chatdetective get events --sort-by=.lastTimestamp
kubectl -n chatdetective logs deploy/chatdetective-api-gateway --tail=100
```

На 4 GiB RAM главный риск — RabbitMQ. При `OOMKilled` сначала смотрите `kubectl top pods`, затем снижайте нагрузку или лимиты остальных сервисов.

## Legacy

Файлы `<service>/.docker/docker-compose.prod.yml` — устаревший, неподдерживаемый способ запуска. Единственный поддерживаемый production-путь — k3s + Helm по этой инструкции.

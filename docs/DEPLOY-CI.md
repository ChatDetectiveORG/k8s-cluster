# Selective production deploy (CI → VPS)

Уровень 3: после push в `main` сервис собирает Docker-образ, пушит в GHCR и шлёт `repository_dispatch` в `ChatDetectiveORG/k8s-cluster`. На VPS обновляется **только один** microservice (тег в `values-k3s-images.yaml` + `helm upgrade` + rollout). Версии сервисов могут расходиться.

Первый деплой — **полный**, вручную на VPS (`./scripts/deploy.sh`). Selective deploy только патчит уже существующий `values-k3s-images.yaml`.

## Схема

```mermaid
sequenceDiagram
  participant S as service repo (push main)
  participant GHCR as GHCR
  participant K8S as k8s-cluster workflow
  participant VPS as VPS (SSH)
  participant TG as Telegram ops

  S->>GHCR: build + push :sha
  S->>K8S: repository_dispatch image-published
  K8S->>TG: deploy queued
  K8S->>VPS: SSH git pull
  VPS->>VPS: patch-image-tag.sh
  VPS->>VPS: deploy-service.sh (one service)
  VPS->>VPS: smoke-prod.sh
  K8S->>TG: success / failure
```

## Маппинг сервисов

| GitHub repo | GHCR package | Helm key (`HELM_SERVICE`) | Deployment |
|-------------|--------------|---------------------------|------------|
| api-gateway | api-gateway | api-gateway | chatdetective-api-gateway |
| command-handler | command-handler | command-handler | chatdetective-command-handler |
| messgae-sender | message-sender | message-sender | chatdetective-message-sender |
| event-loop | event-loop | event-loop | chatdetective-event-loop |
| payment-service | payment-service | payment-service | chatdetective-payment-service |
| chat-export-service | chat-export-service | chat-export-service | chatdetective-chat-export-service |
| business-events-new-handler | business-events-new-handler | business-events-new | chatdetective-business-events-new |
| business-events-edited-handler | business-events-edited-handler | business-events-edited | chatdetective-business-events-edited |

## GitHub Secrets

### В каждом из 8 service repos

Settings → Secrets and variables → Actions → **New repository secret**

| Secret | Описание |
|--------|----------|
| `K8S_CLUSTER_DISPATCH_TOKEN` | PAT с правом вызвать `repository_dispatch` на `ChatDetectiveORG/k8s-cluster` |

**Classic PAT:** scope `repo` (достаточно доступа к `k8s-cluster`).

**Fine-grained PAT:** Repository access → только `k8s-cluster`; Permissions → **Contents: Read**, **Metadata: Read**, **Actions: Read and write** (или Admin, если Actions write недоступен отдельно).

Один и тот же токен можно положить во все 8 репозиториев.

Уже существующие секреты (не трогаем):

| Secret | Назначение |
|--------|------------|
| `REPO_READ_TOKEN` | (опционально) checkout `shared` / cross-repo deps |

### В репозитории `k8s-cluster`

Settings → Secrets and variables → Actions:

| Secret | Пример | Описание |
|--------|--------|----------|
| `VPS_HOST` | `203.0.113.10` | IP или hostname VPS |
| `VPS_SSH_USER` | `root` | SSH-пользователь |
| `VPS_SSH_KEY` | `-----BEGIN OPENSSH PRIVATE KEY-----…` | Приватный ключ (PEM/OpenSSH), публичная часть в `~/.ssh/authorized_keys` на VPS |
| `PROD_HOST` | `bot.example.com` | Host из ingress/TLS для smoke `curl /healthz` |
| `TELEGRAM_OPS_BOT_TOKEN` | `123456:ABC…` | Токен ops-бота |
| `TELEGRAM_OPS_CHAT_ID` | `-1001234567890` | Chat ID ops-чата |

Telegram-секреты опциональны: без них деплой работает, уведомления пропускаются.

## На VPS (не GitHub Secrets)

Эти файлы и объекты k8s **не коммитятся** — см. [k3s-production-deploy.md](./k3s-production-deploy.md).

| Путь / объект | Назначение |
|---------------|------------|
| `/root/chatdetective/values-k3s-secrets.yaml` (mode `600`) | runtime secrets, TLS host, legal URLs |
| `/root/chatdetective/values-k3s-images.yaml` | pinned image tags (selective deploy патчит один ключ) |
| `/root/k8s-cluster` | git clone репозитория k8s-cluster |
| Secret `ghcr-pull-secret` в namespace `chatdetective` | pull образов из GHCR (Classic PAT `read:packages`) |

SSH-ключ для CI: на VPS должен быть доступ `git pull` в `/root/k8s-cluster` (deploy key или HTTPS с read-only token в `git remote`).

## Workflow

### Автоматически (push в main сервиса)

1. `Build and Push Image` — тесты, сборка, push `ghcr.io/chatdetectiveorg/<package>:<sha>`
2. `Trigger selective production deploy` — dispatch в k8s-cluster
3. `Production selective deploy` — SSH на VPS:
   - `git pull`
   - `patch-image-tag.sh <service> <sha>`
   - `deploy-service.sh <service>`
   - `smoke-prod.sh`

### Вручную из GitHub (k8s-cluster → Actions)

Workflow **Production selective deploy** → **Run workflow**:

- **Selective:** `service` = helm key (например `payment-service`), `sha` = 40-char commit, `full_deploy` = false
- **Full:** `full_deploy` = true (перекатывает весь release через `./scripts/deploy.sh`)

Concurrency: один deploy за раз (`production-deploy`).

## Проверка после настройки секретов

1. Push пустого commit в один service repo (или `workflow_dispatch` build).
2. Убедиться, что dispatch прошёл: Actions в `k8s-cluster` → run **Production selective deploy**.
3. На VPS: `kubectl -n chatdetective get pods` — обновился один deployment.
4. В ops-чате Telegram — цепочка уведомлений (если секреты заданы).

## Troubleshooting

| Симптом | Чcause |
|---------|--------|
| `403` на dispatch из service repo | Неверный или недостаточный `K8S_CLUSTER_DISPATCH_TOKEN` |
| SSH fail в k8s-cluster workflow | `VPS_HOST` / `VPS_SSH_KEY` / firewall |
| `ImagePullBackOff` после selective deploy | `ghcr-pull-secret` или тег ещё не в GHCR |
| `values-k3s-images.yaml not found` | Сначала полный `./scripts/deploy.sh` или `fetch-image-tags.sh` |
| Smoke HTTP skip | Задайте `PROD_HOST` в secrets k8s-cluster |

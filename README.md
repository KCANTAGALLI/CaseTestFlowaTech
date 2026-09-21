# Status API — container (ECS) + servidor Linux (EC2)

Aplicação .NET 8 mínima com endpoint `GET /api/status` retornando `Healthy`.
O mesmo binário sobe de dois jeitos: container no ECS Fargate e serviço systemd num EC2 Linux.
Tudo na região `sa-east-1`, com IaC em Terraform e CI/CD no Bitbucket Pipelines.

---

## O que foi entregue

| Requisito | Como foi atendido |
|-----------|-------------------|
| Publique no ECR | Repositório ECR + push no pipeline |
| Container gerenciado (Fargate) | ECS Fargate em subnet privada, porta 5000 |
| Auto-scale | Target tracking (CPU 60% / memória 70%) |
| Métricas + dashboard | CloudWatch Dashboard (ECS, EC2, ALB, rede) |
| Alarmes + notificação | Alarmes CloudWatch → SNS (e-mail) |
| Lambda start/stop app container | EventBridge Scheduler 09:00 / 18:00 (America/Sao_Paulo) |
| WAF OWASP Top 10 | WAFv2 no ALB (CRS + KnownBadInputs + SQLi + rate limit) |
| Artefato Linux | `dotnet publish` + tar no pipeline |
| EC2 Linux privado | Amazon Linux 2023, sem IP público |
| 2 usuários locais | `deployxfer` (artefato) e `apprunner` (execução) |
| Transferência via pipeline | Upload S3 + SSM Run Command |
| systemd via pipeline | Unit `status-api.service` gravada no deploy |
| Cron start/stop serviço | `/etc/cron.d/status-api` (09:00 / 18:00) |
| Lambda start/stop EC2 | Mesmo horário via Scheduler |
| Só IP privado + ALB público | Tasks e EC2 privados; ALB nas subnets públicas |
| Bloqueio de acesso | SG do ALB restrito por `allowed_cidrs` |

---

## Arquitetura (visão rápida)

```
Internet (CIDRs liberados)
        |
   [ AWS WAF ]
        |
   [ ALB público ]
    |:80          |:8080
  TG ECS        TG EC2
    |             |
 subnet privada  subnet privada
  ECS Fargate     EC2 + systemd
  (ECR image)     (artefato .tar.gz via S3)
```

- ECS responde em `http://<alb-dns>/api/status`
- EC2 responde em `http://<alb-dns>:8080/api/status`
- Nenhum dos dois tem IP público. Saída de internet (patch, pull de imagem, SSM) passa pelo NAT.

---

## Estrutura do repositório

```
├── src/StatusApi/          # API .NET 8
├── terraform/              # IaC (VPC, ECR, ECS, EC2, ALB, WAF, Lambda, monitoring)
├── scripts/                # build artefato, deploy ECS e deploy EC2
├── lambda/                 # start/stop ECS e EC2
├── docs/                   # política IAM sugerida pro usuário do pipeline
├── Dockerfile
└── bitbucket-pipelines.yml
```

---

## Aplicação

Rota principal:

```
GET /api/status  →  200 "Healthy"
```

Roda sempre na porta **5000** (Kestrel), tanto no container quanto no systemd.

Para rodar local:

```bash
cd src/StatusApi
dotnet run
curl http://localhost:5000/api/status
```

---

## Pré-requisitos

1. Conta AWS com permissão pra criar VPC, ECS, EC2, IAM, etc. (região `sa-east-1`)
2. Conta Bitbucket Cloud com Pipelines habilitado
3. Terraform >= 1.5 e AWS CLI localmente (só pro bootstrap da infra)
4. Um e-mail pra confirmar a inscrição do SNS (alarmes)

> Credenciais AWS **não** ficam no repositório. Use variáveis do Bitbucket / perfil local.

---

## Subindo a infraestrutura

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edite allowed_cidrs (IP do avaliador) e alarm_email
terraform init
terraform plan
terraform apply
```

Anote os outputs:

- `alb_dns_name`
- `ecr_repository_url`
- `ecs_cluster_name` / `ecs_service_name`
- `ec2_instance_id`
- `deploy_bucket`

**Importante:** na primeira aplicação o service ECS sobe com `desired_count = 0` (ainda não há imagem no ECR). O primeiro pipeline faz push + deploy e sobe para 1 task. O `min_capacity` do auto scaling também é 0 — senão o scale-in impediria o Lambda de stop das 18h.

---

## Bitbucket Pipelines

### Variáveis do repositório

Configure em **Repository settings → Pipelines → Repository variables**:

| Variável | Exemplo | Secured? |
|----------|---------|----------|
| `AWS_ACCESS_KEY_ID` | AKIA... | sim |
| `AWS_SECRET_ACCESS_KEY` | *** | sim |
| `AWS_DEFAULT_REGION` | `sa-east-1` | não |
| `AWS_ACCOUNT_ID` | `383574722107` | não |
| `ECR_REPOSITORY_URI` | output `ecr_repository_url` | não |
| `ECS_CLUSTER` | output `ecs_cluster_name` | não |
| `ECS_SERVICE` | output `ecs_service_name` | não |
| `DEPLOY_BUCKET` | output `deploy_bucket` | não |
| `EC2_INSTANCE_ID` | output `ec2_instance_id` | não |

Há um exemplo de policy em `docs/pipeline-iam-policy.json` pra um usuário IAM dedicado ao CI.

### O que o pipeline faz (branch `main`)

1. **Build container e push ECR** — tag com o short SHA + `latest`
2. **Deploy ECS** — registra nova task definition e força deployment; espera `services-stable`
3. **Build artefato Linux** — `dotnet publish` + `tar.gz`
4. **Deploy EC2** — sobe o artefato no S3 e instala via SSM (systemd + cron)

Pipelines manuais (`custom`):

- `infra-plan` / `infra-apply`
- `deploy-only-ecs` / `deploy-only-ec2`

---

## Serviços AWS utilizados

| Serviço | Uso |
|---------|-----|
| VPC / Subnets / NAT / IGW | Rede isolada; app só com IP privado |
| Security Groups | Bloqueio de acesso; ALB só dos CIDRs liberados |
| ECR | Registry das imagens |
| ECS Fargate | Runtime do container |
| Application Auto Scaling | Scale out/in por CPU e memória |
| ALB | Entrada pública (80 → ECS, 8080 → EC2) |
| WAFv2 | Proteção OWASP (managed rule groups) |
| EC2 + SSM | Servidor Linux + deploy sem SSH obrigatório |
| S3 | Staging do artefato Linux |
| Lambda + EventBridge Scheduler | Liga/desliga ECS e EC2 (09:00–18:00) |
| CloudWatch Metrics / Dashboards / Alarms | Observabilidade |
| SNS | Notificação dos alarmes |
| IAM | Roles de execução (ECS, EC2, Lambda, Scheduler) |

---

## Segurança / bloqueio de acesso

- Tasks ECS e a instância EC2 **não** recebem IP público.
- Security group do ALB só libera 80/8080 para os CIDRs em `allowed_cidrs`.
- SG do ECS/EC2 só aceita a porta 5000 originando do SG do ALB.
- WAF na frente do ALB com regras gerenciadas alinhadas ao OWASP Top 10 + rate limit.
- IMDS v2 obrigatório na EC2 (`http_tokens = required`).

Troque `allowed_cidrs` no `terraform.tfvars` para o IP de quem vai validar (ex.: `["203.0.113.10/32"]`). Deixar `0.0.0.0/0` é só pra smoke test.

---

## Start / stop (09:00 e 18:00)

Dois mecanismos, de propósito:

1. **Lambda + EventBridge Scheduler** (timezone `America/Sao_Paulo`)
   - ECS: `desiredCount` 1 ou 0
   - EC2: `StartInstances` / `StopInstances`
2. **Cron no servidor** (`/etc/cron.d/status-api`)
   - `systemctl start|stop status-api` no mesmo horário
   - cobre o caso em que a instância já está ligada e só o serviço precisa pausar

Dias úteis (seg–sex). Ajuste o cron/scheduler se precisar de fim de semana.

---

## Como validar

```bash
# Container (ECS)
curl -s http://<alb-dns>/api/status
# Servidor (EC2)
curl -s http://<alb-dns>:8080/api/status
```

Os dois devem responder `Healthy`.

Dashboard: CloudWatch → Dashboards → `status-api-dev` (ou o nome do seu `project_name`/`environment`).

---

## Melhorias que eu faria em seguida

1. **HTTPS no ALB** com ACM + redirect 80→443 (hoje o case pede só HTTP na 5000/ALB).
2. **Backend remoto do Terraform** (S3 + DynamoDB) e pipeline de `plan` em PR / `apply` só na `main`.
3. **Image tag imutável** no ECS (proibir `latest` em prod) e scan do ECR bloqueando critical.
4. **Blue/green** com CodeDeploy ou dois target groups no ECS.
5. **Bastion / VPN** e tirar SSH interno; manter só SSM.
6. **Budget alarms** e rightsizing (Fargate Spot em não-prod, EC2 `t4g` se migrar pra ARM).
7. **Centralizar logs** da app EC2 no CloudWatch Logs (hoje o foco está em métricas + journald local).
8. **Separar contas** (dev/prod) e restringir ainda mais a policy do usuário de CI.
9. **Testes automatizados** no pipeline (`dotnet test` + smoke `curl` pós-deploy no ALB).
10. **Path rewrite ou host-based routing** se quiser as duas stacks na porta 80 sem usar 8080.

---

## Observações práticas

- O e-mail do SNS precisa ser **confirmado** na caixa de entrada, senão o alarme dispara mas a notificação não chega.
- NAT Gateway tem custo fixo; se for só demo curta, destrua o stack com `terraform destroy` ao terminar.
- Conta Bitbucket gratuita tem limite de minutos de build — os steps de Docker + Terraform são os que mais consomem.

Qualquer dúvida sobre um módulo específico, o ponto de partida é `terraform/main.tf` (orquestra os módulos) e o `bitbucket-pipelines.yml`.

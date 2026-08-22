# Phase 05 — Containers

Status: ✅ Deployed — no fixed public URL (the ALB DNS name changes each
time the stack is recreated; see [Deploy](#deploy-first-time)). A minimal
demo API proving ECS Fargate → ALB → RDS Postgres end to end.

Docs: [Architecture & design decisions](./docs/Architecture.md)

## Architecture

```
GitHub Actions (OIDC) ──docker build/push──▶ ECR
                                                │
Internet ──80──▶ ALB (public subnets) ──────────┼──▶ ECS Fargate task (public subnets)
                  │ SG: 80 from 0.0.0.0/0        │      SG: container port from ALB SG only
                  ▼                              ▼
            Target Group (/health)         RDS PostgreSQL (public subnet, unreachable
                                            from the internet — SG: 5432 from ECS task SG only)
```

No new VPC, no NAT Gateway — reuses the account's existing default VPC and
its public subnets, with security groups doing the isolation NAT/private
subnets would otherwise provide. See
[`docs/Architecture.md`](./docs/Architecture.md) for why, and for exactly
which settings make `terraform destroy` complete in one command.

## Why this design

- **Minimal purpose-built app, not a third Gratitude Journal
  implementation**: `GET /health`, `GET /notes`, `POST /notes` — just
  enough to prove the ECS→RDS path with a real write and read, no
  duplication of Phase 3's already-thorough Cognito auth story.
- **No NAT Gateway**: the single most avoidable recurring cost in a
  typical "ECS in private subnets" tutorial (~$32–35/month, running
  whether or not anyone hits the app). Security groups (ALB→task→RDS,
  each trusting only the one before it) provide the isolation instead.
- **Destroy needed no separate Terraform config** — `deletion_protection
  = false`, `skip_final_snapshot = true` on RDS, and `force_delete = true`
  on the ECR repo are what make `terraform destroy` complete in one
  command instead of hanging on a snapshot prompt or refusing to delete a
  non-empty repo. **Actually tested**: apply → verify real CRUD → destroy
  (18 resources, zero manual cleanup) → apply again.
- **No local Docker in this environment**: the image is built and pushed
  by `deploy-05-containers-image.yml` via GitHub Actions OIDC (the same
  role Phase 3 uses to update Lambda code) rather than assumed to exist
  from a local `docker build`.
- **DB credentials as a plain ECS environment variable, not Secrets
  Manager**: a deliberate scope cut for a demo database with no real data
  at stake — see Architecture.md.

## Deploy (first time)

The Docker image must exist in ECR **before** the ECS service can start
successfully (the task definition references a specific tag):

```bash
# 1. Push the first image (also creates the ECR repo via Terraform first)
cd aws-portfolio-05-containers/infrastructure/terraform
terraform init
terraform apply -target=aws_ecr_repository.app -target=aws_ecr_lifecycle_policy.app

gh workflow run deploy-05-containers-image.yml --repo daoxiao0/aws-portfolio
# wait for it to finish pushing :latest

# 2. Deploy the rest (RDS, ALB, ECS, security groups)
terraform apply
```

```bash
terraform output alb_dns_name
curl http://<alb_dns_name>/health
curl -X POST http://<alb_dns_name>/notes -H "Content-Type: application/json" -d '{"content":"hello"}'
curl http://<alb_dns_name>/notes
```

RDS creation takes ~5 minutes; the ALB itself takes ~3 minutes. Once the
ECS service shows `runningCount: 1` and the ALB target is `healthy`
(`aws elbv2 describe-target-health`), the API is live.

## Teardown (given equal weight to Deploy — this is the point of the phase)

```bash
cd aws-portfolio-05-containers/infrastructure/terraform
terraform destroy
```

This is a genuinely tested path, not an assumption: 18 resources destroy
cleanly with no manual steps (no RDS snapshot prompt, no deletion
protection error, no "ECR repository not empty" error). ECS service
teardown takes ~7 minutes (draining/deregistering from the ALB), RDS
teardown ~4 minutes.

**Re-deploying after a destroy** needs the image-build step again first —
the ECR repo (and any images in it) is gone too:

```bash
terraform apply -target=aws_ecr_repository.app -target=aws_ecr_lifecycle_policy.app
gh workflow run deploy-05-containers-image.yml --repo daoxiao0/aws-portfolio
terraform apply
```

### CloudFormation (reference implementation, not deployed)

Following Phases 1/3/4's precedent,
[`infrastructure/cloudformation/`](./infrastructure/cloudformation/)
mirrors the same architecture across 5 templates (`network.yaml`,
`ecr.yaml`, `rds.yaml`, `alb.yaml`, `ecs.yaml`) — **not deployed**,
`cfn-lint`-clean (one accepted warning: `W1011`, plaintext DB password
parameter — see Architecture.md). Deployment order:

```bash
cd aws-portfolio-05-containers/infrastructure/cloudformation

aws cloudformation deploy --template-file network.yaml --stack-name portfolio-05-network \
  --parameter-overrides VpcId=<default VPC id>

aws cloudformation deploy --template-file ecr.yaml --stack-name portfolio-05-ecr

aws cloudformation deploy --template-file rds.yaml --stack-name portfolio-05-rds \
  --parameter-overrides SubnetIds=<comma-separated subnet ids> \
    RdsSecurityGroupId=<from network.yaml output> DbPassword=<12+ chars>

aws cloudformation deploy --template-file alb.yaml --stack-name portfolio-05-alb \
  --parameter-overrides VpcId=<default VPC id> SubnetIds=<comma-separated subnet ids> \
    AlbSecurityGroupId=<from network.yaml output>

aws cloudformation deploy --template-file ecs.yaml --stack-name portfolio-05-ecs \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides SubnetIds=<comma-separated subnet ids> \
    EcsTaskSecurityGroupId=<from network.yaml output> \
    TargetGroupArn=<from alb.yaml output> EcrRepositoryUrl=<from ecr.yaml output> \
    DbEndpoint=<from rds.yaml output> DbPassword=<same as rds.yaml>
```

## Remaining work

- DB credentials via Secrets Manager / SSM SecureString instead of a plain
  environment variable (see Architecture.md)
- HTTPS on the ALB + a `*.daoxiao.org` record (currently HTTP-only, no
  custom domain)
- Phase 06 (Enterprise DevOps) — not started

## Folder structure

```
aws-portfolio-05-containers/
├── app/
│   ├── main.py            # FastAPI: /health, /notes (GET+POST)
│   ├── requirements.txt
│   └── Dockerfile
├── docs/
│   └── Architecture.md    # design rationale — read this first
├── infrastructure/terraform/
│   ├── providers.tf, variables.tf
│   ├── ecr.tf              # force_delete = true
│   ├── security_groups.tf  # ALB → ECS task → RDS, each trusting only the one before it
│   ├── rds.tf               # deletion_protection = false, skip_final_snapshot = true
│   ├── alb.tf
│   ├── ecs.tf                # cluster, task def, service, task/execution roles
│   └── outputs.tf
└── infrastructure/cloudformation/ # same architecture — reference only, never deployed
    ├── network.yaml, ecr.yaml, rds.yaml, alb.yaml, ecs.yaml
```

---

# Phase 05 — Containers（日本語）

ステータス: ✅ デプロイ済み — 固定の公開URLなし（スタックを再作成する
たびにALBのDNS名が変わる。[デプロイ手順](#デプロイ手順初回)参照）。
ECS Fargate → ALB → RDS Postgresの一連の流れをエンドツーエンドで証明する
最小限のデモAPI。

ドキュメント: [アーキテクチャ・設計判断](./docs/Architecture.md)

## 構成

```
GitHub Actions (OIDC) ──docker build/push──▶ ECR
                                                │
Internet ──80──▶ ALB（公開サブネット）──────────┼──▶ ECS Fargateタスク（公開サブネット）
                  │ SG: 0.0.0.0/0から80番        │      SG: ALBのSGからコンテナポートのみ
                  ▼                              ▼
            ターゲットグループ (/health)    RDS PostgreSQL（公開サブネットだが
                                            インターネットから到達不可——
                                            SG: ECSタスクSGから5432のみ）
```

新規VPCなし・NAT Gatewayなし——既存のデフォルトVPCと公開サブネットを
流用し、NAT/privateサブネットが本来担うはずの隔離をセキュリティ
グループで代替している。理由と、`terraform destroy`が1コマンドで
完走する具体的な設定は[`docs/Architecture.md`](./docs/Architecture.md)参照。

## なぜこの設計か

- **Gratitude Journalの3度目の実装ではなく、最小限の目的特化アプリ**：
  `GET /health`・`GET /notes`・`POST /notes`——ECS→RDSの経路を実際の
  書き込み・読み取りで証明するのに十分な範囲に留め、Phase 3で既に
  十分に実演済みのCognito認証のストーリーを重複させない。
- **NAT Gatewayなし**：典型的な「ECSをprivateサブネットに置く」
  チュートリアルで最も避けやすい経常コスト（月$32〜35、使われていようが
  いまいが発生）。ALB→タスク→RDSの各段が直前だけを信頼するセキュリティ
  グループで隔離を代替している。
- **削除用の別Terraformは不要だった**——RDSの`deletion_protection =
  false`・`skip_final_snapshot = true`、ECRリポジトリの
  `force_delete = true`が、`terraform destroy`をスナップショット確認
  プロンプトや非空リポジトリの削除拒否で止まらせず1コマンドで完走
  させる要。**実際にテスト済み**：apply→実CRUD確認→destroy
  （18リソース・手動クリーンアップ0件）→再apply。
- **この環境にローカルDockerがない**：イメージは`deploy-05-containers-image.yml`
  がGitHub Actions OIDC経由（Phase 3がLambdaコード更新に使うのと同じ
  ロール）でビルド・pushする——ローカル`docker build`の存在を前提に
  していない。
- **DB認証情報はSecrets ManagerでなくECSの平文環境変数**：実データを
  持たないデモ用データベースに対する意図的なスコープ縮小——
  Architecture.md参照。

## デプロイ手順（初回）

ECSサービスが正常起動するには、その**前**にDockerイメージがECRに
存在している必要がある（タスク定義が特定タグを参照するため）：

```bash
# 1. 最初のイメージをpush（先にTerraformでECRリポジトリだけ作成）
cd aws-portfolio-05-containers/infrastructure/terraform
terraform init
terraform apply -target=aws_ecr_repository.app -target=aws_ecr_lifecycle_policy.app

gh workflow run deploy-05-containers-image.yml --repo daoxiao0/aws-portfolio
# :latestのpush完了を待つ

# 2. 残り（RDS・ALB・ECS・セキュリティグループ）をデプロイ
terraform apply
```

```bash
terraform output alb_dns_name
curl http://<alb_dns_name>/health
curl -X POST http://<alb_dns_name>/notes -H "Content-Type: application/json" -d '{"content":"hello"}'
curl http://<alb_dns_name>/notes
```

RDS作成に約5分、ALB自体に約3分かかる。ECSサービスが`runningCount: 1`、
ALBターゲットが`healthy`（`aws elbv2 describe-target-health`）になれば
APIは稼働中。

## 削除手順（Deployと同等の重みで記載——これが本Phaseの主眼）

```bash
cd aws-portfolio-05-containers/infrastructure/terraform
terraform destroy
```

これは想定だけでなく実際にテスト済みの経路：18リソースが手動介入なしで
クリーンに削除される（RDSスナップショット確認なし・削除保護エラー
なし・「ECRリポジトリが空でない」エラーなし）。ECSサービスの解体に
約7分（ALBからの登録解除待ち）、RDSの解体に約4分。

**destroy後の再デプロイ**は、ECRリポジトリ（中のイメージ含む）も
消えているため、イメージビルドから再度必要：

```bash
terraform apply -target=aws_ecr_repository.app -target=aws_ecr_lifecycle_policy.app
gh workflow run deploy-05-containers-image.yml --repo daoxiao0/aws-portfolio
terraform apply
```

### CloudFormation（参照実装・未デプロイ）

Phase 1・3・4の前例に倣い、
[`infrastructure/cloudformation/`](./infrastructure/cloudformation/)に
同じ構成を5テンプレート（`network.yaml`・`ecr.yaml`・`rds.yaml`・
`alb.yaml`・`ecs.yaml`）で用意している——**未デプロイ**・`cfn-lint`
通過済み（許容している警告1件：`W1011`、DBパスワードの平文パラメータ
——Architecture.md参照）。デプロイ順序：

```bash
cd aws-portfolio-05-containers/infrastructure/cloudformation

aws cloudformation deploy --template-file network.yaml --stack-name portfolio-05-network \
  --parameter-overrides VpcId=<デフォルトVPC ID>

aws cloudformation deploy --template-file ecr.yaml --stack-name portfolio-05-ecr

aws cloudformation deploy --template-file rds.yaml --stack-name portfolio-05-rds \
  --parameter-overrides SubnetIds=<サブネットIDカンマ区切り> \
    RdsSecurityGroupId=<network.yamlの出力> DbPassword=<12文字以上>

aws cloudformation deploy --template-file alb.yaml --stack-name portfolio-05-alb \
  --parameter-overrides VpcId=<デフォルトVPC ID> SubnetIds=<サブネットIDカンマ区切り> \
    AlbSecurityGroupId=<network.yamlの出力>

aws cloudformation deploy --template-file ecs.yaml --stack-name portfolio-05-ecs \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides SubnetIds=<サブネットIDカンマ区切り> \
    EcsTaskSecurityGroupId=<network.yamlの出力> \
    TargetGroupArn=<alb.yamlの出力> EcrRepositoryUrl=<ecr.yamlの出力> \
    DbEndpoint=<rds.yamlの出力> DbPassword=<rds.yamlと同じ値>
```

## 残タスク

- DB認証情報をSecrets Manager／SSM SecureStringへ移行（平文環境変数から）
  ——Architecture.md参照
- ALBのHTTPS化＋`*.daoxiao.org`レコード（現状HTTPのみ・カスタム
  ドメインなし）
- Phase 06（エンタープライズDevOps）——未着手

## フォルダ構成

```
aws-portfolio-05-containers/
├── app/
│   ├── main.py             # FastAPI: /health, /notes (GET+POST)
│   ├── requirements.txt
│   └── Dockerfile
├── docs/
│   └── Architecture.md     # 設計の理由——まずこれを読む
├── infrastructure/terraform/
│   ├── providers.tf, variables.tf
│   ├── ecr.tf               # force_delete = true
│   ├── security_groups.tf   # ALB→ECSタスク→RDS、それぞれ直前のみ信頼
│   ├── rds.tf                # deletion_protection = false, skip_final_snapshot = true
│   ├── alb.tf
│   ├── ecs.tf                 # クラスタ・タスク定義・サービス・タスク/実行ロール
│   └── outputs.tf
└── infrastructure/cloudformation/ # 同じ構成 — 参照実装のみ・未デプロイ
    ├── network.yaml, ecr.yaml, rds.yaml, alb.yaml, ecs.yaml
```

# AWS Portfolio — daoxiao

A progressive series of AWS projects demonstrating cloud architecture skills, from static hosting to enterprise-grade DevOps.

Each phase is an independently deployable product. Infrastructure is defined as code using both Terraform and CloudFormation.

---

## Portfolio Roadmap

| Phase | Project | Core Services | Status |
|-------|---------|---------------|--------|
| 01 | [Static Site Hosting](./aws-portfolio-01-static-site/) | S3, CloudFront, IAM, GitHub Actions | ✅ [Live](https://d3ihmqzooh3cn3.cloudfront.net/) |
| 02 | [Custom Domain + HTTPS](./aws-portfolio-02-custom-domain/) | ACM, Route 53 | ✅ [Live](https://gratitude.daoxiao.org/) |
| 03 | [Serverless Application](./aws-portfolio-03-serverless/) | Cognito, API Gateway, Lambda, DynamoDB | ✅ [Live](https://journal.daoxiao.org/) |
| 04 | [Observability](./aws-portfolio-04-observability/) | CloudWatch, X-Ray, SNS | ✅ [Deployed](./aws-portfolio-04-observability/) (no public URL — instruments Phase 3) |
| 05 | [Containers](./aws-portfolio-05-containers/) | ECS Fargate, ALB, RDS | ✅ [Deployed](./aws-portfolio-05-containers/) (no fixed URL — ALB DNS changes on recreate; **destroy between demos**, real cost while running) |
| 06 | [Enterprise DevOps](./aws-portfolio-06-devops/) | CodePipeline, Terraform, GitHub Actions | ✅ [Deployed](./aws-portfolio-06-devops/) (manual-start pipeline — deliberately not auto-triggered, see its Architecture.md) |

---

## Architecture Evolution

```
Phase 01           Phase 02           Phase 03                    Phase 04                              Phase 05                                      Phase 06
S3 + CloudFront → + Route53/ACM   → + Cognito/Lambda/DynamoDB → + CloudWatch/X-Ray/SNS               → + ECS Fargate/ALB/RDS                       → + CodePipeline/CodeBuild
(Static)           (Custom Domain)    (Serverless)                (Observability — instruments Phase 3)   (Containers — standalone demo, no NAT Gateway)  (Enterprise DevOps — deploys Phase 5, manual gate)
```

---

## Repository Structure

```
aws-portfolio/
├── docs/                           # Portfolio-wide documentation
│   └── Cost-Estimation.md         # AWS cost breakdown across all phases
├── aws-portfolio-01-static-site/   # Phase 01
│   └── docs/                      # Phase 01 specific docs
├── aws-portfolio-02-custom-domain/ # Phase 02 — ✅ live
│   └── docs/troubleshooting.md    # DNS clientHold investigation (RDAP-based diagnosis)
├── aws-portfolio-03-serverless/    # Phase 03 — ✅ live
│   ├── docs/                      # Architecture & Frontend-Design rationale
│   ├── infrastructure/terraform/  # Cognito, DynamoDB, Lambda, API Gateway (HTTP API + JWT authorizer), S3+CloudFront+ACM+Route53 — deployed
│   ├── infrastructure/cloudformation/ # same architecture, 9 templates — reference only, never deployed
│   ├── backend/lambda/            # Python 3.12 handlers (create/list/update/delete entry)
│   └── frontend/                  # Login/signup + CRUD UI, deployed to journal.daoxiao.org
├── aws-portfolio-04-observability/ # Phase 04 — ✅ deployed, no public URL (instruments Phase 3)
│   ├── docs/                      # Architecture & design decisions
│   └── infrastructure/terraform/  # 8 CloudWatch alarms, 1 dashboard, 2 SNS topics (cross-region), log retention
├── aws-portfolio-05-containers/    # Phase 05 — ✅ deployed, no fixed URL (destroy between demos — real cost while running)
│   ├── app/                       # Minimal FastAPI demo (health check + RDS-backed notes)
│   ├── docs/                      # Architecture & design decisions
│   └── infrastructure/terraform/  # ECR, security groups, RDS, ALB, ECS Fargate — no VPC/NAT (reuses default VPC)
├── aws-portfolio-06-devops/        # Phase 06 — ✅ deployed, manual-start pipeline (not auto-triggered)
│   ├── buildspec.yml               # CodeBuild: docker build → ECR push → imagedefinitions.json
│   ├── docs/                      # Architecture & design decisions
│   └── infrastructure/terraform/  # CodeConnections, CodeBuild, CodePipeline (Source→Build→Approve→Deploy)
├── infrastructure/github-oidc/     # Shared, portfolio-wide — not a phase
│   └── main.tf                    # The GitHub Actions OIDC IAM role every phase's CI assumes to deploy;
│                                   # scoped per-resource per phase (see IaC Strategy below), lives outside
│                                   # any single phase because all 6 phases' workflows share this one role
└── .github/workflows/
    ├── deploy-01-static-site.yml   # triggers on Phase 01 changes only
    ├── deploy-02-custom-domain.yml # triggers on Phase 02 changes only
    ├── deploy-03-serverless.yml    # triggers on Phase 03 Lambda code changes only
    ├── deploy-03-frontend.yml      # triggers on Phase 03 frontend changes only
    ├── deploy-04-observability.yml # triggers on Phase 04 changes only — CloudFormation reference validation, infra applied locally
    ├── deploy-05-containers.yml    # triggers on Phase 05 infra changes — CloudFormation reference validation
    ├── deploy-05-containers-image.yml # triggers on Phase 05 app changes — builds & pushes the Docker image to ECR via OIDC
    └── deploy-06-devops.yml        # triggers on Phase 06 infra changes — CloudFormation reference validation
```

---

## IaC Strategy

Phase 01 is implemented twice — once with **Terraform** and once with **CloudFormation** — to demonstrate proficiency with both tools. Phase 02 was originally planned the same way, but its CloudFormation path depended on updating Phase 01's CloudFormation stack; once that stack was deleted during Phase 01's Terraform migration, Phase 02 was implemented in Terraform only (using an `import` block to adopt Phase 01's existing CloudFront distribution). The unused CloudFormation templates are kept in `aws-portfolio-02-custom-domain/infrastructure/cloudformation/` for reference — see that phase's README for details. Phase 03 picked the dual-implementation approach back up: 9 CloudFormation templates in `aws-portfolio-03-serverless/infrastructure/cloudformation/` mirror the Terraform-managed live infrastructure (Cognito, DynamoDB, Lambda, API Gateway, S3+CloudFront+ACM+Route53) but are reference-only and never deployed, since deploying them would create duplicate resources alongside the real ones. Phase 04 continues the same pattern (4 more reference templates) and also touches Phase 03's own `lambda.tf`/`lambda.yaml` with a small additive change (X-Ray tracing) in both tools — see [`aws-portfolio-04-observability/docs/Architecture.md`](./aws-portfolio-04-observability/docs/Architecture.md) for why CloudWatch alarms on CloudFront metrics forced a second, `us-east-1`-only SNS topic. Phase 05 keeps the same pattern (5 more reference templates covering network/security groups, ECR, RDS, ALB, and ECS) and is the first phase where the Terraform side was actually torn down and rebuilt as part of writing it — see [`aws-portfolio-05-containers/docs/Architecture.md`](./aws-portfolio-05-containers/docs/Architecture.md) for why `terraform destroy` needed no separate "delete" configuration, just resources designed from the start to have nothing left to object to. Phase 06 adds a fourth reference set (CodeConnections, S3 artifacts, CodeBuild, CodePipeline) and is the first phase whose CI role genuinely holds deploy permissions (`ecs:UpdateService` on Phase 5's service) rather than being structurally blocked from them — see [`aws-portfolio-06-devops/docs/Architecture.md`](./aws-portfolio-06-devops/docs/Architecture.md) for why a manual approval gate, not a withheld permission, is the control in that design.

---

---

# AWS Portfolio — daoxiao（日本語）

AWS のクラウドアーキテクチャスキルを段階的に示すポートフォリオ。静的ホスティングからエンタープライズ DevOps まで、6 フェーズで構成。

各フェーズは独立してデプロイ可能なプロダクトとして設計。インフラは Terraform と CloudFormation の両方でコード化している。

---

## ポートフォリオ ロードマップ

| Phase | プロジェクト | 主要サービス | ステータス |
|-------|------------|------------|----------|
| 01 | [静的サイトホスティング](./aws-portfolio-01-static-site/) | S3, CloudFront, IAM, GitHub Actions | ✅ [公開中](https://d3ihmqzooh3cn3.cloudfront.net/) |
| 02 | [カスタムドメイン + HTTPS](./aws-portfolio-02-custom-domain/) | ACM, Route 53 | ✅ [公開中](https://gratitude.daoxiao.org/) |
| 03 | [サーバーレスアプリ](./aws-portfolio-03-serverless/) | Cognito, API Gateway, Lambda, DynamoDB | ✅ [公開中](https://journal.daoxiao.org/) |
| 04 | [オブザーバビリティ](./aws-portfolio-04-observability/) | CloudWatch, X-Ray, SNS | ✅ [デプロイ済み](./aws-portfolio-04-observability/)（公開URLなし・Phase 3を計装） |
| 05 | [コンテナ](./aws-portfolio-05-containers/) | ECS Fargate, ALB, RDS | ✅ [デプロイ済み](./aws-portfolio-05-containers/)（固定URLなし・再作成でALB DNS変動・**デモの合間はdestroy推奨**、稼働中は実費が発生） |
| 06 | [エンタープライズ DevOps](./aws-portfolio-06-devops/) | CodePipeline, Terraform, GitHub Actions | ✅ [デプロイ済み](./aws-portfolio-06-devops/)（手動起動専用パイプライン——意図的に自動トリガーなし、詳細はArchitecture.md参照） |

---

## アーキテクチャの進化

```
Phase 01           Phase 02               Phase 03                    Phase 04                          Phase 05                                  Phase 06
S3 + CloudFront → + Route53/ACM       → + Cognito/Lambda/DynamoDB → + CloudWatch/X-Ray/SNS           → + ECS Fargate/ALB/RDS                   → + CodePipeline/CodeBuild
（静的配信）        （カスタムドメイン）    （サーバーレス）              （オブザーバビリティ — Phase 3を計装）  （コンテナ — 単体デモ・NAT Gatewayなし）  （エンタープライズDevOps — Phase 5をデプロイ・承認ゲート付き）
```

---

## リポジトリ構造

```
aws-portfolio/
├── docs/                           # ポートフォリオ全体の共通ドキュメント
│   └── Cost-Estimation.md         # 全Phase の AWS コスト試算
├── aws-portfolio-01-static-site/   # Phase 01
│   └── docs/                      # Phase 01 専用ドキュメント
├── aws-portfolio-02-custom-domain/ # Phase 02 — ✅ 公開中
│   └── docs/troubleshooting.md    # DNS clientHold調査記録（RDAPによる診断）
├── aws-portfolio-03-serverless/    # Phase 03 — ✅ 公開中
│   ├── docs/                      # アーキテクチャ・フロントエンド設計の理由
│   ├── infrastructure/terraform/  # Cognito, DynamoDB, Lambda, API Gateway (HTTP API + JWT authorizer), S3+CloudFront+ACM+Route53 — 実際にデプロイ
│   ├── infrastructure/cloudformation/ # 同じ構成を9テンプレートで — 参照実装のみ・未デプロイ
│   ├── backend/lambda/            # Python 3.12 ハンドラー（日記のCRUD）
│   └── frontend/                  # ログイン/サインアップ + CRUD UI（journal.daoxiao.orgで公開中）
├── aws-portfolio-04-observability/ # Phase 04 — ✅ デプロイ済み・公開URLなし（Phase 3を計装）
│   ├── docs/                      # アーキテクチャ・設計判断
│   └── infrastructure/terraform/  # CloudWatch Alarm 8個・Dashboard 1枚・SNSトピック2つ（リージョン分割）・ログ保持設定
├── aws-portfolio-05-containers/    # Phase 05 — ✅ デプロイ済み・固定URLなし（デモの合間はdestroy推奨・稼働中は実費）
│   ├── app/                       # 最小限のFastAPIデモ（ヘルスチェック＋RDS連携notes）
│   ├── docs/                      # アーキテクチャ・設計判断
│   └── infrastructure/terraform/  # ECR・セキュリティグループ・RDS・ALB・ECS Fargate——VPC/NATなし（デフォルトVPCを流用）
├── aws-portfolio-06-devops/         # Phase 06 — ✅ デプロイ済み・手動起動専用パイプライン（自動トリガーなし）
│   ├── buildspec.yml               # CodeBuild: docker build → ECR push → imagedefinitions.json
│   ├── docs/                      # アーキテクチャ・設計判断
│   └── infrastructure/terraform/  # CodeConnections・CodeBuild・CodePipeline（Source→Build→Approve→Deploy）
├── infrastructure/github-oidc/     # 特定のPhaseに属さない、全Phase共通のインフラ
│   └── main.tf                    # 各PhaseのCIがデプロイ時にassumeするGitHub Actions OIDC IAMロール。
│                                   # Phase単位でリソース単位に権限を絞っている（下のIaC戦略参照）。
│                                   # 6つ全Phaseのワークフローがこの1つのロールを共有するため、
│                                   # 特定のPhaseフォルダの外に置いている
└── .github/workflows/
    ├── deploy-01-static-site.yml   # Phase 01 の変更時のみ発火
    ├── deploy-02-custom-domain.yml # Phase 02 の変更時のみ発火
    ├── deploy-03-serverless.yml    # Phase 03 のLambdaコード変更時のみ発火
    ├── deploy-03-frontend.yml      # Phase 03 のフロントエンド変更時のみ発火
    ├── deploy-04-observability.yml # Phase 04 の変更時のみ発火——CloudFormation参照実装の検証のみ、実インフラはローカル適用
    ├── deploy-05-containers.yml    # Phase 05 のインフラ変更時のみ発火——CloudFormation参照実装の検証のみ
    ├── deploy-05-containers-image.yml # Phase 05 のアプリ変更時のみ発火——OIDC経由でDockerイメージをビルド・ECRへpush
    └── deploy-06-devops.yml        # Phase 06 のインフラ変更時のみ発火——CloudFormation参照実装の検証のみ
```

---

## IaC 方針

Phase 01 のインフラは **Terraform** と **CloudFormation** の両方で実装し、両ツールへの習熟を示している。Phase 02 も当初は同様の二重実装を計画していたが、そのCloudFormation経路はPhase 01のCloudFormationスタックを更新する設計だったため、Phase 01がTerraformへ移行しそのスタックが削除された時点で前提が崩れた。そのためPhase 02はTerraformのみで実装し（`import`ブロックでPhase 01の既存CloudFrontディストリビューションを引き継ぐ方式）、未使用のCloudFormationテンプレートは`aws-portfolio-02-custom-domain/infrastructure/cloudformation/`に参考として残している。詳細は当該フェーズのREADMEを参照。Phase 03では二重実装の方針を再開し、`aws-portfolio-03-serverless/infrastructure/cloudformation/`に9本のCloudFormationテンプレートを用意した。Terraformで稼働中の実インフラ（Cognito・DynamoDB・Lambda・API Gateway・S3+CloudFront+ACM+Route53）と同じ構成をCloudFormationでも記述しているが、これらは参照実装のみでデプロイはしない（デプロイすると実リソースと重複するリソースが作成されてしまうため）。Phase 04も同じ方針を継続（参照テンプレート4本追加）し、Phase 03自身の`lambda.tf`/`lambda.yaml`にも両ツールで小さな追加的変更（X-Rayトレーシング）を入れている——CloudWatch AlarmがCloudFrontメトリクスに対して2つ目の`us-east-1`専用SNSトピックを要求した理由は[`aws-portfolio-04-observability/docs/Architecture.md`](./aws-portfolio-04-observability/docs/Architecture.md)参照。Phase 05も同じ方針を継続（ネットワーク/セキュリティグループ・ECR・RDS・ALB・ECSの参照テンプレート5本）し、制作の一環として実際にTerraform側を一度解体・再構築した初めてのPhaseとなった——`terraform destroy`が「削除用」の別設定を必要とせず、最初から destroy に何も文句を言わせない設計にしたリソースだけで完結した理由は[`aws-portfolio-05-containers/docs/Architecture.md`](./aws-portfolio-05-containers/docs/Architecture.md)参照。Phase 06は4組目の参照実装セット（CodeConnections・S3アーティファクト・CodeBuild・CodePipeline）を追加し、CI用ロールが初めて本物のデプロイ権限（Phase 5のサービスへの`ecs:UpdateService`）を持つPhaseとなった——構造的に権限を持たせない代わりに手動承認ゲートを制御手段にした理由は[`aws-portfolio-06-devops/docs/Architecture.md`](./aws-portfolio-06-devops/docs/Architecture.md)参照。

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
| 05 | Containers | ECS Fargate, ALB, RDS | 📋 Planned |
| 06 | Enterprise DevOps | CodePipeline, Terraform, GitHub Actions | 📋 Planned |

---

## Architecture Evolution

```
Phase 01           Phase 02           Phase 03                    Phase 04
S3 + CloudFront → + Route53/ACM   → + Cognito/Lambda/DynamoDB → + CloudWatch/X-Ray/SNS
(Static)           (Custom Domain)    (Serverless)                (Observability — instruments Phase 3)
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
└── .github/workflows/
    ├── deploy-01-static-site.yml   # triggers on Phase 01 changes only
    ├── deploy-02-custom-domain.yml # triggers on Phase 02 changes only
    ├── deploy-03-serverless.yml    # triggers on Phase 03 Lambda code changes only
    ├── deploy-03-frontend.yml      # triggers on Phase 03 frontend changes only
    └── deploy-04-observability.yml # triggers on Phase 04 changes only — CloudFormation reference validation, infra applied locally
```

---

## IaC Strategy

Phase 01 is implemented twice — once with **Terraform** and once with **CloudFormation** — to demonstrate proficiency with both tools. Phase 02 was originally planned the same way, but its CloudFormation path depended on updating Phase 01's CloudFormation stack; once that stack was deleted during Phase 01's Terraform migration, Phase 02 was implemented in Terraform only (using an `import` block to adopt Phase 01's existing CloudFront distribution). The unused CloudFormation templates are kept in `aws-portfolio-02-custom-domain/infrastructure/cloudformation/` for reference — see that phase's README for details. Phase 03 picked the dual-implementation approach back up: 9 CloudFormation templates in `aws-portfolio-03-serverless/infrastructure/cloudformation/` mirror the Terraform-managed live infrastructure (Cognito, DynamoDB, Lambda, API Gateway, S3+CloudFront+ACM+Route53) but are reference-only and never deployed, since deploying them would create duplicate resources alongside the real ones. Phase 04 continues the same pattern (4 more reference templates) and also touches Phase 03's own `lambda.tf`/`lambda.yaml` with a small additive change (X-Ray tracing) in both tools — see [`aws-portfolio-04-observability/docs/Architecture.md`](./aws-portfolio-04-observability/docs/Architecture.md) for why CloudWatch alarms on CloudFront metrics forced a second, `us-east-1`-only SNS topic.

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
| 05 | コンテナ | ECS Fargate, ALB, RDS | 📋 予定 |
| 06 | エンタープライズ DevOps | CodePipeline, Terraform, GitHub Actions | 📋 予定 |

---

## アーキテクチャの進化

```
Phase 01           Phase 02               Phase 03                    Phase 04
S3 + CloudFront → + Route53/ACM       → + Cognito/Lambda/DynamoDB → + CloudWatch/X-Ray/SNS
（静的配信）        （カスタムドメイン）    （サーバーレス）              （オブザーバビリティ — Phase 3を計装）
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
└── .github/workflows/
    ├── deploy-01-static-site.yml   # Phase 01 の変更時のみ発火
    ├── deploy-02-custom-domain.yml # Phase 02 の変更時のみ発火
    ├── deploy-03-serverless.yml    # Phase 03 のLambdaコード変更時のみ発火
    ├── deploy-03-frontend.yml      # Phase 03 のフロントエンド変更時のみ発火
    └── deploy-04-observability.yml # Phase 04 の変更時のみ発火——CloudFormation参照実装の検証のみ、実インフラはローカル適用
```

---

## IaC 方針

Phase 01 のインフラは **Terraform** と **CloudFormation** の両方で実装し、両ツールへの習熟を示している。Phase 02 も当初は同様の二重実装を計画していたが、そのCloudFormation経路はPhase 01のCloudFormationスタックを更新する設計だったため、Phase 01がTerraformへ移行しそのスタックが削除された時点で前提が崩れた。そのためPhase 02はTerraformのみで実装し（`import`ブロックでPhase 01の既存CloudFrontディストリビューションを引き継ぐ方式）、未使用のCloudFormationテンプレートは`aws-portfolio-02-custom-domain/infrastructure/cloudformation/`に参考として残している。詳細は当該フェーズのREADMEを参照。Phase 03では二重実装の方針を再開し、`aws-portfolio-03-serverless/infrastructure/cloudformation/`に9本のCloudFormationテンプレートを用意した。Terraformで稼働中の実インフラ（Cognito・DynamoDB・Lambda・API Gateway・S3+CloudFront+ACM+Route53）と同じ構成をCloudFormationでも記述しているが、これらは参照実装のみでデプロイはしない（デプロイすると実リソースと重複するリソースが作成されてしまうため）。Phase 04も同じ方針を継続（参照テンプレート4本追加）し、Phase 03自身の`lambda.tf`/`lambda.yaml`にも両ツールで小さな追加的変更（X-Rayトレーシング）を入れている——CloudWatch AlarmがCloudFrontメトリクスに対して2つ目の`us-east-1`専用SNSトピックを要求した理由は[`aws-portfolio-04-observability/docs/Architecture.md`](./aws-portfolio-04-observability/docs/Architecture.md)参照。

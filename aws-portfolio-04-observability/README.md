# Phase 04 — Observability

Status: ✅ Deployed — no public URL (this phase watches Phase 3, it doesn't
add a site). [Dashboard link](#dashboard) requires AWS console access.

Docs: [Architecture & design decisions](./docs/Architecture.md)

## What's here

```
Phase 3 (existing)                    Phase 4 (this)
┌─────────────────────┐
│ 4× Lambda            │──tracing_config: Active──▶ X-Ray (segments per invocation)
│ (create/list/update/ │──AWSXRayDaemonWriteAccess─┘
│  delete_entry)        │
│                       │──Errors metric────────────▶ 4× CloudWatch Alarm ──┐
├───────────────────────┤                                                    │
│ API Gateway (HTTP)    │──5xx metric────────────────▶ 1× CloudWatch Alarm ──┤
├───────────────────────┤                                                    ├──▶ SNS (ap-northeast-1) ──▶ email
│ DynamoDB (entries)    │──ThrottledRequests─────────▶ 1× CloudWatch Alarm ──┤
├───────────────────────┤                                                    │
│ CloudFront × 2        │──5xxErrorRate───────────────▶ 2× CloudWatch Alarm ─┴──▶ SNS (us-east-1) ──▶ email
│ (Phase 1 + Phase 3)   │        (metrics only exist in us-east-1)
└───────────────────────┘
         │
         └── all of the above ──▶ 1× CloudWatch Dashboard (mixed-region widgets)
```

See [`docs/Architecture.md`](./docs/Architecture.md) for why two SNS topics
exist, why API Gateway itself doesn't get X-Ray tracing, and the log-group
import gotcha hit during deploy.

## Why this design

- **Nothing new to observe was built** — this phase instruments Phase 3's
  existing Lambda/API Gateway/DynamoDB/CloudFront, it doesn't stand up new
  infrastructure to watch. Two of Phase 3's own Terraform files
  (`lambda.tf`) get two small additive edits (tracing config, X-Ray IAM
  policy) rather than trying to bolt X-Ray on from a separate state.
- **Per-function Lambda error alarms, not one aggregated alarm**: an error
  in `delete_entry` and one in `list_entries` are different bugs and should
  page distinctly.
- **CloudFront alarms/SNS topic live in `us-east-1`, not `ap-northeast-1`**:
  not a style choice — CloudWatch requires an alarm's SNS action to be in
  the alarm's own Region, and CloudFront only publishes metrics in
  `us-east-1`.
- **`treat_missing_data = "notBreaching"` on every alarm**: at
  portfolio-scale traffic, a quiet period with zero requests is normal, not
  an incident.
- **No `aws-xray-sdk` in the Lambda code**: would add this project's first
  third-party Python dependency and a packaging step that doesn't exist yet
  (see Architecture.md). Lambda's built-in active tracing still produces a
  real per-invocation segment without it — deliberate scope cut, not an
  oversight.

## Deploy (first time)

```bash
# 1. Enable tracing on Phase 3's existing Lambdas (2-line addition per function)
cd aws-portfolio-03-serverless/infrastructure/terraform
terraform plan
terraform apply

# 2. Import the 4 Lambda log groups Phase 3 already created, then apply Phase 4
cd ../../aws-portfolio-04-observability/infrastructure/terraform
terraform init
for fn in create-entry list-entries update-entry delete-entry; do
  terraform import "aws_cloudwatch_log_group.phase3_lambda[\"aws-portfolio-03-serverless-$fn\"]" \
    "/aws/lambda/aws-portfolio-03-serverless-$fn"
done
terraform plan
terraform apply
```

After `apply`, confirm the SNS email subscriptions: AWS sends a confirmation
link to the address in `var.alert_email` for **both** topics (one per
region) — until each is clicked, that topic's alarms won't actually notify
anyone.

## Dashboard

```bash
terraform output dashboard_url
```

Opens a CloudWatch dashboard with 10 widgets: Lambda invocations/errors/
duration (all 4 functions), API Gateway count/4xx/5xx/latency, DynamoDB
consumed capacity/throttling, and CloudFront requests/5xx rate for both
distributions.

### CloudFormation (reference implementation, not deployed)

Following Phases 1 and 3's precedent,
[`infrastructure/cloudformation/`](./infrastructure/cloudformation/) mirrors
the same architecture in CloudFormation. **Not deployed** — applying these
would create duplicate alarms/dashboard/topics alongside the real
Terraform-managed ones. All 4 templates (`sns.yaml`, `alarms.yaml`,
`cloudfront-alarms.yaml`, `dashboard.yaml`) pass
`cfn-lint`, as does the corresponding 2-line addition to Phase 3's
`infrastructure/cloudformation/lambda.yaml`. `cloudfront-alarms.yaml` owns
its own SNS topic for the same cross-region reason described above — it is
**not** a parameter of `sns.yaml`.

```bash
cd aws-portfolio-04-observability/infrastructure/cloudformation

aws cloudformation deploy --template-file sns.yaml --stack-name portfolio-04-sns
aws cloudformation deploy --template-file alarms.yaml --stack-name portfolio-04-alarms \
  --parameter-overrides AlertsTopicArn=<from sns.yaml output>
aws cloudformation deploy --template-file cloudfront-alarms.yaml --stack-name portfolio-04-cloudfront-alarms \
  --region us-east-1
aws cloudformation deploy --template-file dashboard.yaml --stack-name portfolio-04-dashboard
```

## Remaining work

- DynamoDB sub-segments in X-Ray traces (needs `aws-xray-sdk` + a packaging
  step — see Architecture.md "X-Ray: Lambda-level tracing only")
- Confirm both SNS email subscriptions (manual step, not automatable)
- Phases 5–6 (Containers, Enterprise DevOps) — not started

## Folder structure

```
aws-portfolio-04-observability/
├── docs/
│   └── Architecture.md        # design rationale — read this first
├── infrastructure/terraform/
│   ├── providers.tf           # aws + aws.us_east_1 alias
│   ├── variables.tf           # includes Phase 3 resource names/ARNs (cross-state refs)
│   ├── sns.tf                 # 2 topics + 2 email subscriptions
│   ├── alarms.tf               # 8 alarms
│   ├── dashboard.tf            # 1 dashboard, 10 widgets, mixed regions
│   ├── log_groups.tf           # retention on Phase 3's 4 existing log groups (import required)
│   └── outputs.tf
└── infrastructure/cloudformation/ # same architecture — reference only, never deployed
    ├── sns.yaml, alarms.yaml, cloudfront-alarms.yaml, dashboard.yaml
```

Phase 3's own `infrastructure/terraform/lambda.tf` and
`infrastructure/cloudformation/lambda.yaml` also each carry a small
tracing-related addition — see Architecture.md.

---

# Phase 04 — Observability（日本語）

ステータス: ✅ デプロイ済み — 公開URLなし（本Phaseは新しいサイトを追加せず、
Phase 3を観測するだけ）。[Dashboardリンク](#dashboard)はAWSコンソール
アクセスが必要。

ドキュメント: [アーキテクチャ・設計判断](./docs/Architecture.md)

## 構成

```
Phase 3（既存）                        Phase 4（本Phase）
┌─────────────────────┐
│ Lambda × 4            │──tracing_config: Active──▶ X-Ray（呼び出しごとのセグメント）
│ (create/list/update/ │──AWSXRayDaemonWriteAccess─┘
│  delete_entry）        │
│                       │──Errors metric────────────▶ CloudWatch Alarm × 4 ──┐
├───────────────────────┤                                                     │
│ API Gateway (HTTP)    │──5xx metric────────────────▶ CloudWatch Alarm × 1 ──┤
├───────────────────────┤                                                     ├──▶ SNS (ap-northeast-1) ──▶ メール
│ DynamoDB (entries)    │──ThrottledRequests─────────▶ CloudWatch Alarm × 1 ──┤
├───────────────────────┤                                                     │
│ CloudFront × 2        │──5xxErrorRate───────────────▶ CloudWatch Alarm × 2 ─┴──▶ SNS (us-east-1) ──▶ メール
│ (Phase 1 + Phase 3)   │        （メトリクスはus-east-1にしか存在しない）
└───────────────────────┘
         │
         └── 上記すべて ──▶ CloudWatch Dashboard × 1（複数リージョンwidget混在）
```

SNSトピックが2つある理由・API Gateway自体にはX-Rayトレーシングが
効かない理由・デプロイ時に遭遇したロググループのimport問題の詳細は
[`docs/Architecture.md`](./docs/Architecture.md)参照。

## なぜこの設計か

- **観測対象を新規に作っていない**——本PhaseはPhase 3の既存Lambda/
  API Gateway/DynamoDB/CloudFrontを計装するだけで、監視のために新しい
  インフラを立てているわけではない。Phase 3自身のTerraformファイル
  （`lambda.tf`）に2箇所、小さく追加的な変更（トレーシング設定・X-Ray
  IAMポリシー）を入れており、別stateから無理に後付けしようとはしていない。
- **Lambdaエラーアラームは関数ごと、集約しない**：`delete_entry`のエラーと
  `list_entries`のエラーは別のバグであり、別々に通知されるべき。
- **CloudFrontのアラーム/SNSトピックは`ap-northeast-1`でなく`us-east-1`**：
  スタイルの選択ではない——CloudWatchはAlarmのSNSアクションがAlarm自身と
  同じリージョンにあることを要求し、CloudFrontはus-east-1にしか
  メトリクスを発行しない。
- **全アラームで`treat_missing_data = "notBreaching"`**：ポートフォリオ
  規模のトラフィックでは、リクエストがゼロの静かな期間は正常であり、
  インシデントではない。
- **Lambdaコードに`aws-xray-sdk`は入れていない**：このプロジェクト初の
  Python第三者依存関係と、まだ存在しないパッケージングステップが
  必要になる（Architecture.md参照）。それがなくてもLambda組み込みの
  アクティブトレーシングは呼び出しごとの実セグメントを生成する——
  見落としではなく意図的なスコープ外。

## デプロイ手順（初回）

```bash
# 1. Phase 3の既存Lambdaにトレーシングを有効化（関数ごと2行追加）
cd aws-portfolio-03-serverless/infrastructure/terraform
terraform plan
terraform apply

# 2. Phase 3が既に作成済みの4つのLambdaロググループをimportしてからPhase 4をapply
cd ../../aws-portfolio-04-observability/infrastructure/terraform
terraform init
for fn in create-entry list-entries update-entry delete-entry; do
  terraform import "aws_cloudwatch_log_group.phase3_lambda[\"aws-portfolio-03-serverless-$fn\"]" \
    "/aws/lambda/aws-portfolio-03-serverless-$fn"
done
terraform plan
terraform apply
```

`apply`後、SNSメールサブスクリプションの確認が必要：AWSが
`var.alert_email`宛に**両方の**トピック（リージョンごとに1つ）分の
確認リンクを送る——それぞれクリックするまで、そのトピックのアラームは
誰にも通知されない。

## Dashboard

```bash
terraform output dashboard_url
```

10個のwidgetを持つCloudWatch Dashboardが開く：Lambda呼び出し数/エラー数/
所要時間（4関数分）、API Gatewayのカウント/4xx/5xx/レイテンシ、DynamoDBの
消費キャパシティ/スロットリング、CloudFrontの2ディストリビューション分の
リクエスト数/5xx率。

### CloudFormation（参照実装・未デプロイ）

Phase 1・Phase 3の前例に倣い、
[`infrastructure/cloudformation/`](./infrastructure/cloudformation/)に
同じ構成をCloudFormationでも用意している。**これらは未デプロイ**——
適用すると実際にTerraformで稼働中のAlarm/Dashboard/トピックと重複した
ものが作成されてしまう。全4テンプレート（`sns.yaml`・`alarms.yaml`・
`cloudfront-alarms.yaml`・`dashboard.yaml`）は`cfn-lint`を通過済み。
Phase 3の`infrastructure/cloudformation/lambda.yaml`への対応する2行追加も
同様。`cloudfront-alarms.yaml`は同じクロスリージョンの理由により自前の
SNSトピックを持つ——`sns.yaml`のパラメータでは**ない**。

```bash
cd aws-portfolio-04-observability/infrastructure/cloudformation

aws cloudformation deploy --template-file sns.yaml --stack-name portfolio-04-sns
aws cloudformation deploy --template-file alarms.yaml --stack-name portfolio-04-alarms \
  --parameter-overrides AlertsTopicArn=<sns.yamlの出力>
aws cloudformation deploy --template-file cloudfront-alarms.yaml --stack-name portfolio-04-cloudfront-alarms \
  --region us-east-1
aws cloudformation deploy --template-file dashboard.yaml --stack-name portfolio-04-dashboard
```

## 残タスク

- X-RayトレースへのDynamoDBサブセグメント追加（`aws-xray-sdk`＋
  パッケージングステップが必要——Architecture.md「X-Ray：Lambda側のみ、
  API Gateway側は非対応」参照）
- SNSメールサブスクリプション2件の確認（手動作業・自動化不可）
- Phase 5〜6（コンテナ・エンタープライズDevOps）——未着手

## フォルダ構成

```
aws-portfolio-04-observability/
├── docs/
│   └── Architecture.md        # 設計の理由——まずこれを読む
├── infrastructure/terraform/
│   ├── providers.tf           # aws + aws.us_east_1 エイリアス
│   ├── variables.tf           # Phase 3のリソース名/ARNを含む（別state参照）
│   ├── sns.tf                 # トピック2つ + メールサブスクリプション2つ
│   ├── alarms.tf               # アラーム8個
│   ├── dashboard.tf            # ダッシュボード1枚・widget10個・複数リージョン混在
│   ├── log_groups.tf           # Phase 3の既存4ロググループの保持期間（要import）
│   └── outputs.tf
└── infrastructure/cloudformation/ # 同じ構成 — 参照実装のみ・未デプロイ
    ├── sns.yaml, alarms.yaml, cloudfront-alarms.yaml, dashboard.yaml
```

Phase 3自身の`infrastructure/terraform/lambda.tf`・
`infrastructure/cloudformation/lambda.yaml`にも、トレーシング関連の
小さな追加がそれぞれ入っている——詳細はArchitecture.md参照。

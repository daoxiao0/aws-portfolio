# Cost Estimation — AWS Portfolio

Pricing based on AWS Tokyo region (ap-northeast-1) as of 2026.
All estimates assume **low-traffic portfolio usage** (~1,000 visits/month).

---

## Phase 01 — Static Site Hosting

### Services Used

| Service | Usage | Free Tier | Estimated Monthly Cost |
|---------|-------|-----------|----------------------|
| S3 Storage | ~2 MB (build files) | 5 GB / 12 months | **$0.00** |
| S3 Requests | ~500 PUT/month (CI/CD deploys) | 2,000 PUT / 12 months | **$0.00** |
| CloudFront Data Transfer | ~0.5 GB/month | 1 TB / always free | **$0.00** |
| CloudFront Requests | ~10,000 req/month | 10M req / always free | **$0.00** |
| CloudFront Invalidations | ~10 paths/month | 1,000 paths / always free | **$0.00** |
| IAM | — | Always free | **$0.00** |
| GitHub Actions | ~5 min/deploy × 10 deploys | Unlimited (public repo) | **$0.00** |

### Phase 01 Total

| Scenario | Monthly | Annual |
|----------|---------|--------|
| Within Free Tier (first 12 months) | **$0.00** | **$0.00** |
| After Free Tier expires | **~$0.01** | **~$0.12** |

> Phase 01 is effectively free. S3 storage cost after free tier: $0.025/GB = ~$0.00005/month for 2MB.

---

## Phase 02 — Custom Domain + HTTPS (Planned)

### Additional Services

| Service | Usage | Free Tier | Estimated Monthly Cost |
|---------|-------|-----------|----------------------|
| ACM Certificate | 1 certificate | Always free (public cert) | **$0.00** |
| Route 53 Hosted Zone | 1 zone | None | **$0.50** |
| Route 53 DNS Queries | ~10,000/month | 1M queries included in $0.50 | **$0.00** |

### Phase 02 Total (incremental)

| Scenario | Monthly | Annual |
|----------|---------|--------|
| Added cost vs Phase 01 | **$0.50** | **$6.00** |

> Route 53 hosted zone is the only meaningful cost at portfolio scale.

---

## Phase 03 — Serverless Application (Deployed 2026-07-11)

### Additional Services

| Service | Usage (actual portfolio scale) | Free Tier | Estimated Monthly Cost |
|---------|-------|-----------|----------------------|
| Cognito User Pool (Essentials tier) | 1 test user | 10,000 MAU/month, always free | **$0.00** |
| API Gateway (HTTP API) | ~100 requests/month | 1M requests / 12 months, then $1.00/million | **$0.00** |
| Lambda (4 functions) | ~400 invocations/month | 1M requests + 400,000 GB-seconds, always free | **$0.00** |
| DynamoDB (on-demand) storage | <1 MB | 25 GB, always free | **$0.00** |
| DynamoDB (on-demand) requests | ~500 reads + 200 writes/month | None for on-demand mode ($0.25/M read, $1.25/M write, US baseline; Tokyo slightly higher) | **$0.00** (well under $0.01) |
| S3 (frontend build, own bucket) | ~2 MB | 5 GB / 12 months | **$0.00** |
| CloudFront (own distribution) | ~0.1 GB/month, ~500 req/month | 1 TB + 10M req, always free | **$0.00** |
| ACM Certificate (journal.daoxiao.org) | 1 certificate | Always free (public cert) | **$0.00** |
| Route 53 record | 1 A record (alias) in existing zone | No extra hosted zone fee — reuses Phase 2's zone | **$0.00** |

### Phase 03 Total (incremental)

| Scenario | Monthly | Annual |
|----------|---------|--------|
| Current portfolio-scale usage | **~$0.00** | **~$0.00** |
| After API Gateway free tier expires (12 months) | **~$0.01** | **~$0.12** |

> Unlike Phase 01/02, DynamoDB on-demand mode has **no free tier for request costs** (only the 25 GB storage allowance is free) — but at portfolio-demo traffic levels the per-request cost rounds to zero. If this app ever gets real user traffic, DynamoDB request cost is the line item to watch first (API Gateway and Lambda free tiers are far larger).

---

## Phase 04 — Observability (Deployed 2026-08-22)

### Additional Services

| Service | Usage (actual, this account) | Free Tier | Estimated Monthly Cost |
|---------|-------|-----------|----------------------|
| CloudWatch Alarms | 8 new (4 Lambda + 1 API GW + 1 DynamoDB, ap-northeast-1; 2 CloudFront, us-east-1) | 10 alarms/account, always free | **See note below — not $0.00** |
| CloudWatch Dashboard | 1 (10 widgets) | 3 dashboards/account, always free | **$0.00** |
| CloudWatch Logs retention | 4 Lambda log groups set to 14 days (was unlimited) | N/A — reduces storage over time | **$0.00** (net cost decrease) |
| X-Ray traces | ~400 invocations/month → ~400 traces/month (Lambda-level only, no DynamoDB sub-segments) | 100,000 traces recorded/month, always free | **$0.00** |
| SNS (2 topics, email only) | <10 notifications/month at this traffic level | 1,000 email notifications/month, always free | **$0.00** |

> **Alarms are the one line item that isn't free**, and the reason is specific to this AWS account, not this phase in isolation: `describe-alarms` showed **9 pre-existing alarms** (from the unrelated `aws-knowledge-collector` / `aws-serverless-social-publisher` projects sharing this account) *before* Phase 04 was applied. Adding this phase's 8 brings the account to **17 alarms total against a 10-alarm free tier**, so up to 7 are billable at $0.10/alarm/month (~**$0.70/month**) if CloudWatch's free tier is account-wide; if it's actually tracked per-Region (`ap-northeast-1`: 9 pre-existing + 6 new = 15 → 5 billable = $0.50/month; `us-east-1`: 2 new, both free = $0.00), the total is **~$0.50/month** instead. I could not confirm which scoping AWS applies without waiting for an actual bill — either way this is the account's cumulative alarm count crossing the free threshold, not something unique to Phase 04's own alarms.

### Phase 04 Total (incremental)

| Scenario | Monthly | Annual |
|----------|---------|--------|
| This account, current usage | **~$0.50–$0.70** | **~$6–$8.40** |
| If this were a fresh AWS account (no other projects' alarms) | **$0.00** | **$0.00** |

---

## Phase 05 — Containers (Deployed 2026-08-22, destroy-between-demos by design)

Unlike Phases 01–04, this phase is **not left running continuously** — see
[`aws-portfolio-05-containers/README.md`](../aws-portfolio-05-containers/README.md#teardown-given-equal-weight-to-deploy--this-is-the-point-of-the-phase)
and `docs/Architecture.md` for why `terraform destroy` was designed and
tested to complete in one command with zero manual cleanup. The numbers
below are **while the stack is up**; it is $0.00 the rest of the time.

### Services Used (while running)

| Service | Usage | Free Tier | Estimated cost while running |
|---------|-------|-----------|----------------------|
| ECS Fargate | 1 task, 0.25 vCPU / 0.5 GB, ap-northeast-1 | None for Fargate compute | **~$0.017/hour** (~$12–13/month if left up all month) |
| Application Load Balancer | 1 ALB, fixed hourly charge + LCU (negligible at demo traffic) | 750 hrs/month for 12 months (new accounts only) | **~$0.025/hour** (~$18/month if left up all month) |
| RDS db.t4g.micro | Single-AZ, 20GB gp3, no Multi-AZ | 750 hrs/month + 20GB for 12 months (new accounts only) | **~$0.02/hour compute** + **~$2.40/month storage** (~$14–17/month if left up all month) |
| ECR storage | 1 image, ~63MB | 500MB/month, always free | **$0.00** |
| Data transfer | Demo-scale traffic | 100GB/month, always free | **$0.00** |

> **List-price approximations, not confirmed via the AWS Pricing API** (this
> account's CLI user isn't granted `pricing:GetProducts`, and adding it
> just to look up a number felt like scope creep for a demo phase — these
> are published Tokyo-region list prices, not a verified quote). If this
> account still has its Free Tier active (new-account only, first 12
> months), Fargate itself has no free tier but ALB and RDS do, which would
> reduce the "left up all month" figures notably.

### Phase 05 Total

| Scenario | Cost |
|----------|------|
| Destroyed (the recommended default between demos) | **$0.00** |
| Running for a 1-hour demo | **~$0.06** |
| Left running for a full month (not recommended) | **~$44–48** |

> This is the **first phase in the portfolio with a real, non-trivial
> running cost** — Phases 01–04 all round to ~$0/month regardless. That's
> exactly why teardown got equal engineering attention to deploy: verified
> for real (`apply` → CRUD test → `destroy`, 18 resources, zero manual
> cleanup → `apply` again), not just assumed to work because the Terraform
> looked right.

---

## Phase 06 — Cost Preview (Planned)

| Phase | Key Services Added | Estimated Monthly Cost |
|-------|-------------------|----------------------|
| 06 DevOps | CodePipeline, CodeBuild | ~$1.00–$5.00 |

---

## Free Tier Summary

| Service | Free Tier Amount | Duration |
|---------|-----------------|----------|
| S3 Storage | 5 GB | First 12 months |
| S3 GET Requests | 20,000 / month | First 12 months |
| S3 PUT Requests | 2,000 / month | First 12 months |
| CloudFront Data Transfer | 1 TB / month | Always free |
| CloudFront HTTP Requests | 10,000,000 / month | Always free |
| CloudFront Invalidations | 1,000 paths / month | Always free |
| ACM Public Certificate | Unlimited | Always free |
| Lambda Invocations | 1,000,000 / month | Always free |
| Lambda Compute | 400,000 GB-seconds / month | Always free |
| DynamoDB Storage | 25 GB | Always free |
| DynamoDB Read/Write (Provisioned mode only) | 25 WCU / 25 RCU | Always free — **does not apply to our on-demand table** |
| Cognito User Pool MAU | 10,000 / month (Essentials tier) | Always free |
| API Gateway HTTP API Requests | 1,000,000 / month | First 12 months only |

---

## Cost Optimization Notes

- **CloudFront invalidation**: `/*` invalidates all paths at once, counting as 1 path toward the 1,000 free limit. Current setup is optimal.
- **S3 versioning**: Disabled intentionally — versioning would accumulate old build files and increase storage costs.
- **GitHub Actions**: Public repos get unlimited free minutes. Keep the repo public to avoid charges.
- **Phase 05 tip**: Stop ECS tasks and RDS instances when not demoing to avoid continuous compute charges.

---

---

# コスト試算 — AWS Portfolio（日本語）

2026年時点の東京リージョン（ap-northeast-1）の料金に基づく。
想定トラフィック: **月間約1,000訪問（ポートフォリオ規模）**

---

## Phase 01 — 静的サイトホスティング

### 使用サービス

| サービス | 使用量 | 無料枠 | 月額試算 |
|---------|--------|--------|---------|
| S3 ストレージ | 約2MB（ビルドファイル） | 5GB / 12ヶ月 | **$0.00** |
| S3 リクエスト | 約500 PUT/月（CI/CDデプロイ） | 2,000 PUT / 12ヶ月 | **$0.00** |
| CloudFront 転送量 | 約0.5GB/月 | 1TB / 常時無料 | **$0.00** |
| CloudFront リクエスト | 約10,000回/月 | 1,000万回 / 常時無料 | **$0.00** |
| CloudFront Invalidation | 約10パス/月 | 1,000パス / 常時無料 | **$0.00** |
| IAM | — | 常時無料 | **$0.00** |
| GitHub Actions | 約5分/デプロイ × 10回 | 無制限（パブリックリポジトリ） | **$0.00** |

### Phase 01 合計

| シナリオ | 月額 | 年額 |
|---------|------|------|
| 無料枠内（最初の12ヶ月） | **$0.00** | **$0.00** |
| 無料枠終了後 | **約$0.01** | **約$0.12** |

> Phase 01 は実質無料。無料枠終了後のS3ストレージ: $0.025/GB × 0.002GB = 月額$0.00005。

---

## Phase 02 — カスタムドメイン + HTTPS（予定）

### 追加サービス

| サービス | 使用量 | 無料枠 | 月額試算 |
|---------|--------|--------|---------|
| ACM 証明書 | 1枚 | 常時無料（パブリック証明書） | **$0.00** |
| Route 53 ホストゾーン | 1ゾーン | なし | **$0.50** |
| Route 53 DNSクエリ | 約10,000回/月 | $0.50に100万クエリ含む | **$0.00** |

### Phase 02 追加コスト

| シナリオ | 月額 | 年額 |
|---------|------|------|
| Phase 01 比 追加分 | **$0.50** | **$6.00** |

> ポートフォリオ規模での唯一の実費はRoute 53ホストゾーン代のみ。

---

## Phase 03 — サーバーレスアプリ（2026-07-11 実機デプロイ済み）

### 追加サービス

| サービス | 使用量（ポートフォリオ規模の実測） | 無料枠 | 月額試算 |
|---------|--------|--------|---------|
| Cognito User Pool（Essentialsティア） | テストユーザー1名 | 10,000 MAU/月・常時無料 | **$0.00** |
| API Gateway（HTTP API） | 約100リクエスト/月 | 100万リクエスト/12ヶ月、以降$1.00/100万 | **$0.00** |
| Lambda（4関数） | 約400回呼び出し/月 | 100万リクエスト＋400,000 GB秒・常時無料 | **$0.00** |
| DynamoDB（オンデマンド）ストレージ | 1MB未満 | 25GB・常時無料 | **$0.00** |
| DynamoDB（オンデマンド）リクエスト | 約500 read + 200 write/月 | オンデマンドモードには無料枠なし（$0.25/100万read・$1.25/100万write、米国基準。東京はやや高め） | **$0.00**（$0.01未満） |
| S3（フロントエンド用・独自バケット） | 約2MB | 5GB / 12ヶ月 | **$0.00** |
| CloudFront（独自ディストリビューション） | 約0.1GB/月・約500リクエスト/月 | 1TB＋1,000万リクエスト・常時無料 | **$0.00** |
| ACM証明書（journal.daoxiao.org） | 1枚 | 常時無料（パブリック証明書） | **$0.00** |
| Route 53 レコード | 既存ゾーンにAレコード(alias)1件追加 | Phase 2のゾーンを流用のため追加のホストゾーン代なし | **$0.00** |

### Phase 03 追加コスト

| シナリオ | 月額 | 年額 |
|---------|------|------|
| 現在のポートフォリオ規模の使用量 | **約$0.00** | **約$0.00** |
| API Gateway無料枠終了後（12ヶ月後） | **約$0.01** | **約$0.12** |

> Phase 01/02と異なり、DynamoDBオンデマンドモードは**リクエスト課金に無料枠が無い**（無料なのはストレージ25GB分のみ）。ただしポートフォリオのデモ規模のトラフィックではリクエスト単価が実質ゼロに丸まる。今後実ユーザーのトラフィックが発生した場合、真っ先に注視すべきコスト項目はDynamoDBのリクエスト課金（API GatewayとLambdaの無料枠ははるかに大きい）。

---

## Phase 04 — オブザーバビリティ（2026-08-22デプロイ）

### 追加サービス

| サービス | 使用量（このアカウントでの実測） | 無料枠 | 月額試算 |
|---------|--------|--------|---------|
| CloudWatch Alarm | 新規8個（Lambda4＋API GW1＋DynamoDB1はap-northeast-1、CloudFront2はus-east-1） | 10個/アカウント・常時無料 | **下記注記参照——$0.00ではない** |
| CloudWatch Dashboard | 1枚（widget10個） | 3枚/アカウント・常時無料 | **$0.00** |
| CloudWatch Logs保持期間 | Lambdaロググループ4個を14日に設定（従来は無期限） | 該当なし——むしろストレージは減少 | **$0.00**（実質コスト減） |
| X-Rayトレース | 約400回呼び出し/月 → 約400トレース/月（Lambda側のみ、DynamoDBサブセグメントなし） | 100,000トレース記録/月・常時無料 | **$0.00** |
| SNS（トピック2つ・メールのみ） | この規模では10通未満/月 | 1,000メール通知/月・常時無料 | **$0.00** |

> **唯一無料でないのがAlarm** で、理由は本Phase単体の問題ではなくこのAWSアカウント固有の事情による：Phase 4適用前の時点で`describe-alarms`を確認したところ、**既存9個のAlarm**が存在していた（このアカウントを共有する無関係な`aws-knowledge-collector`・`aws-serverless-social-publisher`プロジェクト由来）。本Phaseの8個を加えると**アカウント合計17個**となり、10個の無料枠を超える。CloudWatchの無料枠が**アカウント全体で共通**なら超過分7個×$0.10＝**約$0.70/月**、**リージョンごとに個別**なら（`ap-northeast-1`：既存9＋新規6＝15個→超過5個＝$0.50/月、`us-east-1`：新規2個はどちらも無料枠内＝$0.00）合計**約$0.50/月**となる。どちらの区分が実際に適用されるかは実際の請求書が来るまで確認できなかった。いずれにせよ、これは本Phase固有のAlarmの問題ではなく、アカウント全体の累計Alarm数が無料枠を超えたことによるもの。

### Phase 04 追加コスト

| シナリオ | 月額 | 年額 |
|---------|------|------|
| このアカウントでの現状 | **約$0.50〜$0.70** | **約$6〜$8.40** |
| 他プロジェクトのAlarmが無い、まっさらなアカウントだった場合 | **$0.00** | **$0.00** |

---

## Phase 05 — コンテナ（2026-08-22デプロイ・デモの合間はdestroy前提の設計）

Phase 01〜04と異なり、本Phaseは**常時稼働させない**——`terraform destroy`が
手動クリーンアップ0件で1コマンド完走するよう設計・実テスト済みである理由は
[`aws-portfolio-05-containers/README.md`](../aws-portfolio-05-containers/README.md#削除手順deployと同等の重みで記載これが本phaseの主眼)・
`docs/Architecture.md`参照。以下の数値は**スタックが稼働中の間のみ**——
それ以外の時間は$0.00。

### 使用サービス（稼働中）

| サービス | 使用量 | 無料枠 | 稼働中の試算 |
|---------|--------|--------|---------|
| ECS Fargate | タスク1個・0.25 vCPU/0.5GB・ap-northeast-1 | Fargateコンピュートに無料枠なし | **約$0.017/時間**（1ヶ月起きっぱなしなら約$12〜13） |
| Application Load Balancer | ALB1台・固定時間課金＋LCU（デモ規模のトラフィックでは無視できる水準） | 750時間/月・12ヶ月（新規アカウントのみ） | **約$0.025/時間**（1ヶ月起きっぱなしなら約$18） |
| RDS db.t4g.micro | 単一AZ・20GB gp3・Multi-AZなし | 750時間/月＋20GB・12ヶ月（新規アカウントのみ） | **コンピュート約$0.02/時間**＋**ストレージ約$2.40/月**（1ヶ月起きっぱなしなら約$14〜17） |
| ECRストレージ | イメージ1枚・約63MB | 500MB/月・常時無料 | **$0.00** |
| データ転送 | デモ規模のトラフィック | 100GB/月・常時無料 | **$0.00** |

> **AWS Pricing APIでは確認していない、公表リスト価格ベースの概算**
> （このアカウントのCLIユーザーには`pricing:GetProducts`権限がなく、
> デモ用のPhaseのために数値確認だけのために権限を追加するのはスコープ
> 過剰と判断した——これらは東京リージョンの公表リスト価格であり、
> 確認済みの見積もりではない）。このアカウントがまだFree Tier期間
> （新規アカウントのみ・最初の12ヶ月）であれば、Fargate自体には無料枠は
> ないがALB・RDSにはあるため、「1ヶ月起きっぱなし」の数値は実際には
> もっと下がる可能性がある。

### Phase 05 合計

| シナリオ | コスト |
|----------|------|
| destroy済み（デモの合間の推奨デフォルト） | **$0.00** |
| 1時間のデモで稼働 | **約$0.06** |
| 1ヶ月間起きっぱなし（非推奨） | **約$44〜48** |

> ポートフォリオの中で**初めて実質的な稼働コストが発生するPhase**——
> Phase 01〜04はすべてトラフィックに関わらず月額約$0に丸まる。だからこそ
> destroyにdeployと同等のエンジニアリング上の注意を払った——実際に
> 検証済み（`apply`→CRUD確認→`destroy`、18リソース・手動クリーンアップ
> 0件→再`apply`）であり、Terraformの見た目が正しいから動くはずと
> 想定しただけではない。

---

## Phase 06 — コスト概算（予定）

| Phase | 追加主要サービス | 月額概算 |
|-------|---------------|---------|
| 06 DevOps | CodePipeline・CodeBuild | 約$1.00〜$5.00 |

---

## コスト最適化ポイント

- **CloudFront Invalidation**: `/*` で全パスを一括無効化しても「1パス」としてカウント。現在の設定は最適。
- **S3バージョニング**: 意図的に無効化。有効にすると古いビルドファイルが蓄積しストレージコストが増加する。
- **GitHub Actions**: パブリックリポジトリは無料枠が無制限。リポジトリを公開状態に保つことで課金を回避できる。
- **Phase 05 注意**: デモしない期間はECSタスクとRDSインスタンスを停止してコンピューティング課金を抑える。

# Architecture — Phase 04 Observability

## What this phase adds

Phase 3 (the serverless Gratitude Journal) had zero visibility beyond
CloudWatch's default, unconfigured Lambda log groups. Phase 4 adds:

- **X-Ray active tracing** on Phase 3's 4 Lambda functions
- **8 CloudWatch alarms** covering Lambda errors, API Gateway 5xx, DynamoDB
  throttling, and CloudFront 5xx error rate (both distributions)
- **1 CloudWatch dashboard** aggregating all of the above on one screen
- **2 SNS topics** (one per region — see "Why two SNS topics" below) that
  email alarm state changes
- **Explicit 14-day log retention** on the 4 Lambda log groups (previously
  unset = kept forever)

This phase does not add any application code or a public URL — it observes
Phase 3, it doesn't extend it.

## Why Phase 3's own files get touched

Enabling tracing on an existing Lambda function and attaching a new IAM
policy to its existing execution role are changes to resources Phase 3
already owns. There's no way to bolt X-Ray onto someone else's
`aws_lambda_function` from a separate Terraform state — so
`aws-portfolio-03-serverless/infrastructure/terraform/lambda.tf` gets two
small, additive edits per function:

```hcl
tracing_config {
  mode = "Active"
}
```

and an extra `aws_iam_role_policy_attachment` pointing at the AWS-managed
`AWSXRayDaemonWriteAccess` policy, alongside the existing
`AWSLambdaBasicExecutionRole` attachment. Everything else in this phase
(alarms, dashboard, SNS, log retention) lives in Phase 4's own Terraform
state and references Phase 3's resources by name/ARN — the same pattern
`shared-infra/github-oidc/main.tf` already uses to reference Phase 3's S3
bucket and Lambda ARNs from a separate state.

## X-Ray: Lambda-level tracing only, not API Gateway

Phase 3 uses API Gateway **HTTP API** (`aws_apigatewayv2_stage`), not REST
API. I checked the Terraform AWS provider's resource schema directly
(`terraform providers schema -json`) rather than assume: `aws_apigatewayv2_stage`
exposes `access_log_settings` and `default_route_settings` but **no X-Ray
tracing attribute at all** — that toggle only exists on `aws_api_gateway_stage`
(REST API v1). So API Gateway itself does not emit X-Ray segments here.

Lambda's own "Active" tracing config is independent of API Gateway and still
produces a real segment per invocation — function name, duration, cold
start — without any code changes. What's missing is a DynamoDB sub-segment:
the handlers call `boto3` directly with no `aws-xray-sdk` instrumentation
(`patch_all()`), so the DynamoDB call inside each Lambda won't show as its
own child segment in a trace. Adding that would be the natural next
increment, but it means adding this project's first third-party Python
dependency and a build step to vendor it into the Lambda zip (currently
`archive_file` just zips `backend/lambda/<fn>/` directly — no
`pip install -t .` step exists yet). Left as a deliberate scope cut rather
than done silently.

## Why two SNS topics, not one

CloudWatch alarms require their SNS action to live in the **same Region** as
the alarm. Phase 3's Lambda/API Gateway/DynamoDB alarms live in
`ap-northeast-1` (matching the rest of the project), but **CloudFront only
publishes CloudWatch metrics in `us-east-1`** — so the two CloudFront 5xx
alarms have to live there too, and by extension so does the SNS topic they
notify. Discovered by hitting it directly:

```
Error: creating CloudWatch Metric Alarm (...-cloudfront-phase1-5xx-rate):
api error ValidationError: Invalid region ap-northeast-1 specified.
Only us-east-1 is supported.
```

(The message is really about the *SNS topic's* region embedded in its ARN,
not the alarm's own region, which was already correctly `us-east-1` via the
provider alias — CloudWatch was rejecting the cross-region `alarm_actions`
reference.) Fix: a second `aws_sns_topic` + email subscription, provisioned
with `provider = aws.us_east_1`, used only by the two CloudFront alarms. Both
topics point at the same inbox — the split is purely an AWS regional
constraint, not a difference in what gets watched.

## Alarm design

| Alarm | Namespace / Metric | Threshold | Why this shape |
|---|---|---|---|
| Lambda Errors × 4 | `AWS/Lambda` `Errors` | ≥1 / 5 min | One per function, not aggregated — an error in `delete_entry` and one in `list_entries` are different bugs |
| API Gateway 5xx | `AWS/ApiGateway` `5xx` | ≥1 / 5 min | HTTP API's metric name is `5xx` (lowercase) — REST API's `5XXError` doesn't exist on this API type |
| DynamoDB throttling | `AWS/DynamoDB` `ThrottledRequests` | ≥1 / 5 min | On-demand mode can still throttle under a sudden burst; this is the table-wide umbrella metric |
| CloudFront 5xx rate × 2 | `AWS/CloudFront` `5xxErrorRate` | >5% / 5 min | Rate, not count — CloudFront serves cached content directly, so a raw error count is meaningless without knowing total requests |

All 8 alarms use `treat_missing_data = "notBreaching"`: at portfolio-scale
traffic, a metric can go quiet for a period with no requests at all, and
that absence of data is not itself a problem worth paging on.

## Deploy

Same as every other phase's infra: applied locally, never through the OIDC
CI/CD role (that role deliberately has no CloudWatch/SNS/X-Ray/IAM
permissions — see `aws-portfolio-03-serverless/README.md` "Why this
design"). One gotcha hit here specifically: the 4 Lambda log groups already
existed (the functions had already been invoked before this phase), so
`aws_cloudwatch_log_group` had to be `terraform import`-ed first — creating
them fresh would have failed with `ResourceAlreadyExistsException`.

```bash
cd aws-portfolio-03-serverless/infrastructure/terraform
terraform apply   # tracing_config + X-Ray policy attachment on the 4 functions

cd ../../aws-portfolio-04-observability/infrastructure/terraform
terraform import 'aws_cloudwatch_log_group.phase3_lambda["aws-portfolio-03-serverless-create-entry"]' \
  /aws/lambda/aws-portfolio-03-serverless-create-entry
# ...repeat for list-entries / update-entry / delete-entry
terraform apply
```

After `apply`, the SNS subscriptions sit in `PendingConfirmation` until the
confirmation email (sent to both topics' subscribed address) is confirmed by
clicking the link inside it — nothing here can do that step programmatically.

---

# アーキテクチャ — Phase 04 Observability（日本語）

## このPhaseが追加するもの

Phase 3（サーバーレス感謝日記）は、設定なしのデフォルトLambdaロググループ以外、
可視性が一切なかった。Phase 4が追加するのは：

- Phase 3の4つのLambda関数への**X-Rayアクティブトレーシング**
- Lambdaエラー・API Gateway 5xx・DynamoDBスロットリング・CloudFront 5xxエラー率
  （両ディストリビューション）をカバーする**8個のCloudWatch Alarm**
- 上記すべてを1画面に集約する**CloudWatch Dashboard 1枚**
- Alarmの状態変化をメール通知する**SNSトピック2つ**（リージョンごとに1つ。
  理由は下記「なぜSNSトピックが2つなのか」参照）
- Lambdaロググループの**保持期間を14日に明示設定**（従来は無期限）

本Phaseはアプリケーションコードや公開URLを一切追加しない。Phase 3を
「観測する」だけで、「拡張する」わけではない。

## なぜPhase 3自身のファイルにも手を入れるのか

既存のLambda関数のトレーシングを有効化し、既存の実行ロールに新しいIAM
ポリシーをアタッチするのは、Phase 3が既に所有しているリソースへの変更である。
別のTerraform stateから他人の`aws_lambda_function`にX-Rayを後付けする方法は
存在しないため、`aws-portfolio-03-serverless/infrastructure/terraform/lambda.tf`
に関数ごと2箇所、小さく追加的な変更を入れる：

```hcl
tracing_config {
  mode = "Active"
}
```

および、既存の`AWSLambdaBasicExecutionRole`アタッチメントと並んで、
AWS管理ポリシー`AWSXRayDaemonWriteAccess`を指す`aws_iam_role_policy_attachment`
をもう1つ追加。それ以外（Alarm・Dashboard・SNS・ログ保持設定）はすべて
Phase 4自身のTerraform stateに置き、Phase 3のリソースは名前/ARNで参照する
——`shared-infra/github-oidc/main.tf`がPhase 3のS3バケット・Lambda ARNを
別stateから参照しているのと同じ方式。

## X-Ray：Lambda側のみ、API Gateway側は非対応

Phase 3はAPI Gateway **HTTP API**（`aws_apigatewayv2_stage`）を使っており、
REST APIではない。推測ではなく`terraform providers schema -json`で
Terraform AWSプロバイダのリソーススキーマを直接確認したところ、
`aws_apigatewayv2_stage`が持つのは`access_log_settings`・
`default_route_settings`のみで、**X-Rayトレーシングの属性は一切存在しない**
——そのトグルは`aws_api_gateway_stage`（REST API v1）にしかない。
そのため、API Gateway自体はX-Rayセグメントを発行しない。

Lambda自身の「Active」トレーシング設定はAPI Gatewayとは独立しており、
コード変更なしでも呼び出しごとに実際のセグメント（関数名・所要時間・
コールドスタート）を生成する。欠けているのはDynamoDBのサブセグメントで、
各ハンドラーは`aws-xray-sdk`による計装（`patch_all()`）なしに`boto3`を
直接呼んでいるため、Lambda内のDynamoDB呼び出しはトレース上で独立した
子セグメントとしては表示されない。これを追加するのが自然な次の一歩だが、
このプロジェクト初のPython第三者依存関係とビルドステップの追加を意味する
（現状`archive_file`は`backend/lambda/<fn>/`をそのままzip化するだけで、
`pip install -t .`のようなステップは存在しない）。黙って省略するのではなく、
意図的なスコープ外として記録する。

## なぜSNSトピックが2つなのか

CloudWatch Alarmは、そのSNSアクションが**Alarmと同じリージョン**に
存在する必要がある。Phase 3のLambda/API Gateway/DynamoDBアラームは
（プロジェクト全体と同じ）`ap-northeast-1`にあるが、**CloudFrontの
CloudWatchメトリクスは`us-east-1`にしか発行されない**——そのため
CloudFrontの5xxアラーム2つもそちらに置く必要があり、通知先のSNSトピックも
同様にus-east-1に置く必要がある。実際にエラーに遭遇して発見した：

```
Error: creating CloudWatch Metric Alarm (...-cloudfront-phase1-5xx-rate):
api error ValidationError: Invalid region ap-northeast-1 specified.
Only us-east-1 is supported.
```

（メッセージは実際には「SNSトピックのARNに埋め込まれたリージョン」に
ついてであり、Alarm自体のリージョン——providerエイリアスで既に正しく
`us-east-1`を指定済みだった——についてではない。CloudWatchが
クロスリージョンの`alarm_actions`参照を拒否していた。）対処法：
`provider = aws.us_east_1`で作成する2つ目の`aws_sns_topic`＋メール
サブスクリプション。2つのトピックはどちらも同じ宛先に届く——分割は
純粋にAWSのリージョン制約によるもので、監視対象の違いではない。

## Alarm設計

| Alarm | Namespace / Metric | 閾値 | この形にした理由 |
|---|---|---|---|
| Lambda Errors × 4 | `AWS/Lambda` `Errors` | 5分で1回以上 | 関数ごとに分離、集約しない——`delete_entry`のエラーと`list_entries`のエラーは別のバグ |
| API Gateway 5xx | `AWS/ApiGateway` `5xx` | 5分で1回以上 | HTTP APIのメトリクス名は`5xx`（小文字）——このAPIタイプにはREST APIの`5XXError`は存在しない |
| DynamoDBスロットリング | `AWS/DynamoDB` `ThrottledRequests` | 5分で1回以上 | オンデマンドモードでも急激なバーストではスロットリングが起きうる。テーブル全体の統合メトリクス |
| CloudFront 5xx率 × 2 | `AWS/CloudFront` `5xxErrorRate` | 5分で5%超 | 件数ではなく率——CloudFrontはキャッシュ済みコンテンツを直接配信するため、全リクエスト数を知らない生の件数は意味を持たない |

全8アラームとも`treat_missing_data = "notBreaching"`——ポートフォリオ規模の
トラフィックでは、一定期間リクエスト自体が来ないことがあり、データの
不在それ自体は通知すべき問題ではない。

## デプロイ

他の全Phaseのインフラと同様、ローカルから適用し、OIDC CI/CDロール経由では
行わない（そのロールには意図的にCloudWatch/SNS/X-Ray/IAM権限を持たせて
いない——理由は`aws-portfolio-03-serverless/README.md`「なぜこの設計か」参照）。
本Phase固有の落とし穴が1つ：4つのLambdaロググループは既に存在していた
（本Phase着手前に関数が既に呼び出されていたため）ため、
`aws_cloudwatch_log_group`は事前に`terraform import`が必要だった——
新規作成しようとすると`ResourceAlreadyExistsException`で失敗する。

```bash
cd aws-portfolio-03-serverless/infrastructure/terraform
terraform apply   # 4関数へtracing_config + X-Rayポリシーアタッチ

cd ../../aws-portfolio-04-observability/infrastructure/terraform
terraform import 'aws_cloudwatch_log_group.phase3_lambda["aws-portfolio-03-serverless-create-entry"]' \
  /aws/lambda/aws-portfolio-03-serverless-create-entry
# ...list-entries / update-entry / delete-entry も同様に
terraform apply
```

`apply`後、SNSサブスクリプションは確認メール（両トピックの購読先アドレスに
届く）内のリンクをクリックして確認するまで`PendingConfirmation`のまま——
この手順をプログラムから代行することはできない。

# Phase 03 — Serverless Gratitude Journal

Status: ✅ Live — https://journal.daoxiao.org/

Docs: [Architecture & design decisions](./docs/Architecture.md) · [IAM least privilege redesign](./docs/IAM-Least-Privilege.md) · [Frontend design](./docs/Frontend-Design.md) · [Terraform reference](./infrastructure/terraform/README.md) · [Build-from-scratch tutorial (JP only)](./docs/Build-Tutorial/README.md)

## Architecture

```
CloudFront (journal.daoxiao.org) ── S3 (React build)
  │
  ▼  login / signup
Cognito User Pool  ──JWT (ID Token)──┐
                                      ▼
                          API Gateway (HTTP API)
                          JWT Authorizer (backed by Cognito)
                                      │
                    ┌─────────┬───────┼───────┬─────────┐
                POST /entries GET /entries PUT /entries/{id} DELETE /entries/{id}
                    │         │             │             │
              create_entry list_entries update_entry  delete_entry   (Lambda, Python 3.12)
                    └─────────┴───────┬─────┴─────────────┘
                                      ▼
                           DynamoDB (`entries` table)
                           PK: userId / SK: entryId
```

See [`docs/Architecture.md`](./docs/Architecture.md) for the full reasoning
behind every choice below (security model, why single-table design, why HTTP
API, etc.) — this section is just the summary.

## Why this design

- **HTTP API, not REST API**: has a built-in `JWT Authorizer` that natively
  validates Cognito's JWTs. Simpler and cheaper than REST API, and CRUD-scale
  requirements don't need REST API's extra features.
- **Lambda in Python**: the user is learning Python, so the production
  handlers double as learning material.
- **DynamoDB single table, `PK=userId` / `SK=entryId`**: every query is scoped
  to one user's partition — there is no code path that can reach another
  user's data (structural IDOR protection, not a runtime check).
- **Existing IAM user reused (`github-actions-portfolio-01`), no new one
  created**: keeps GitHub Secrets from multiplying with every phase.
- **CI/CD scope is application code only** (Lambda code + frontend build):
  infra changes (Cognito/API Gateway/DynamoDB/IAM/creating S3 buckets or
  CloudFront distributions/Route53/ACM) are deployed manually via
  `terraform apply`, same as Phase 2 — the CI IAM user intentionally can't
  *create* IAM roles, Cognito pools, or CloudFront distributions (only write
  to the existing bucket and invalidate the existing distribution).
- **S3+CloudFront are Phase 3's own bucket/distribution**, independent of
  Phase 1's — so `terraform destroy` in this phase can never touch Phase 1/2.

## Deploy (first time)

```bash
cd aws-portfolio-03-serverless/infrastructure/terraform
terraform init
terraform plan
terraform apply
```

After `apply`, set the following outputs as the React app's environment
variables (`.env.local`):
- `api_endpoint`
- `cognito_user_pool_id`
- `cognito_user_pool_client_id`

See [`infrastructure/terraform/README.md`](./infrastructure/terraform/README.md)
for the full file-by-file breakdown, all outputs, and gotchas hit while
deploying this phase (IAM permissions, ACM region requirement, DynamoDB
on-demand free tier).

### CloudFormation (reference implementation, not deployed)

Following Phase 1's precedent, this phase's infrastructure is also written
as CloudFormation templates in
[`infrastructure/cloudformation/`](./infrastructure/cloudformation/) — to
demonstrate the same architecture in both tools. **These are not deployed**:
the live infrastructure is Terraform-managed, and deploying these templates
would create duplicate resources (a second Cognito pool, second Lambda
functions, etc.) alongside the real ones. All 9 templates pass
`aws cloudformation validate-template`. Deployment order (each step's
Outputs feed the next step's `--parameter-overrides`):

```
dynamodb.yaml ─┐
cognito.yaml ──┼─→ lambda.yaml ─→ api-gateway.yaml
               │
s3-frontend.yaml ─→ cloudfront.yaml ─→ route53.yaml
acm.yaml (us-east-1) ──────────────↗
                                     │
              lambda.yaml + s3-frontend.yaml + cloudfront.yaml outputs
                                     ↓
                              iam-cicd.yaml (last)
```

```bash
cd aws-portfolio-03-serverless/infrastructure/cloudformation

aws cloudformation deploy --template-file dynamodb.yaml --stack-name portfolio-03-dynamodb
aws cloudformation deploy --template-file cognito.yaml --stack-name portfolio-03-cognito
aws cloudformation deploy --template-file lambda.yaml --stack-name portfolio-03-lambda \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides TableName=<from dynamodb> TableArn=<from dynamodb>
aws cloudformation deploy --template-file api-gateway.yaml --stack-name portfolio-03-api \
  --parameter-overrides CognitoUserPoolId=<...> CognitoUserPoolClientId=<...> \
    CreateEntryFunctionArn=<...> CreateEntryFunctionName=<...> ... (4 functions)

aws cloudformation deploy --template-file s3-frontend.yaml --stack-name portfolio-03-s3 \
  --parameter-overrides BucketName=your-bucket-name
aws cloudformation deploy --template-file acm.yaml --stack-name portfolio-03-acm \
  --region us-east-1
aws cloudformation deploy --template-file cloudfront.yaml --stack-name portfolio-03-cloudfront \
  --parameter-overrides BucketName=<...> BucketArn=<...> BucketRegionalDomainName=<...> \
    AcmCertificateArn=<from acm, us-east-1>
aws cloudformation deploy --template-file route53.yaml --stack-name portfolio-03-route53 \
  --parameter-overrides CloudFrontDomainName=<from cloudfront>

aws cloudformation deploy --template-file iam-cicd.yaml --stack-name portfolio-03-iam-cicd \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides CreateEntryFunctionArn=<...> ... FrontendBucketArn=<...> \
    CloudFrontDistributionArn=<...>
```

## React frontend

```bash
cd aws-portfolio-03-serverless/frontend
npm install
cp .env.example .env.local   # fill in with the terraform outputs above
npm start                    # local check
```

Production deploy is automated via `.github/workflows/deploy-03-frontend.yml`
on every push to `frontend/**` — see that file's header comment for the
one-time GitHub repo Variables setup (`PHASE3_API_ENDPOINT`,
`PHASE3_COGNITO_USER_POOL_ID`, `PHASE3_COGNITO_CLIENT_ID`,
`PHASE3_S3_BUCKET_NAME`, `PHASE3_CLOUDFRONT_DIST_ID`; reuses Phase 1's
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` secrets). Manual deploy still works
the same way Phase 1 does:
```bash
npm run build
aws s3 sync build/ s3://<frontend_bucket_name> --delete
aws cloudfront create-invalidation --distribution-id <cloudfront_distribution_id> --paths "/*"
```

- **Auth**: talks to Cognito directly via `amazon-cognito-identity-js`
  (sign up → confirm code → sign in → ID token).
- **API calls**: every request carries the ID token in the `Authorization`
  header. A `401` is treated as an expired session and returns the user to
  the login screen.
- **UI parity with Phase 1**: the journal screen mirrors Phase 1's gratitude
  tree, streak counter, tab layout, and ja/en/zh language cycling — see
  [`docs/Frontend-Design.md`](./docs/Frontend-Design.md) for the component
  structure and the non-obvious logic (streak calculation, day-numbering).
- Verified end-to-end by the user in a real browser session (sign up →
  confirm code → sign in → insert/update/delete → sign out), 2026-07-11.

## Remaining work

None — both CI/CD pipelines (Lambda + frontend) are set up and verified
working end-to-end.

## Folder structure

```
aws-portfolio-03-serverless/
├── docs/
│   ├── Architecture.md          # infra design rationale, security model
│   ├── IAM-Least-Privilege.md   # per-function IAM role redesign rationale
│   └── Frontend-Design.md       # React component/auth/state design rationale
├── infrastructure/terraform/
│   ├── README.md              # file-by-file reference, deploy/destroy, gotchas
│   ├── providers.tf
│   ├── variables.tf
│   ├── cognito.tf             # User Pool + App Client
│   ├── dynamodb.tf            # entries table
│   ├── lambda.tf              # execution role + 4 functions
│   ├── api_gateway.tf         # HTTP API + JWT Authorizer + routes
│   ├── iam.tf                 # scoped policy on the existing GitHub Actions user
│   ├── s3_frontend.tf         # frontend hosting bucket
│   ├── cloudfront.tf          # OAC + CloudFront (journal.daoxiao.org)
│   ├── acm.tf                 # ACM certificate (us-east-1)
│   ├── route53.tf             # A record (alias)
│   └── outputs.tf
├── infrastructure/cloudformation/ # same architecture — reference only, never deployed
│   ├── dynamodb.yaml, cognito.yaml, lambda.yaml, api-gateway.yaml
│   └── s3-frontend.yaml, acm.yaml, cloudfront.yaml, route53.yaml, iam-cicd.yaml
├── backend/lambda/
│   ├── create_entry/handler.py
│   ├── list_entries/handler.py
│   ├── update_entry/handler.py
│   └── delete_entry/handler.py
└── frontend/
    ├── src/auth/cognito.js       # sign up / confirm / sign in / ID token
    ├── src/api/entries.js        # fetch wrapper for the HTTP API
    ├── src/components/AuthScreen.js
    ├── src/components/JournalScreen.js
    ├── src/components/GratitudeTree.js
    └── src/App.js                # switches screen based on auth state
```

---

# Phase 03 — サーバーレス感謝日記（日本語）

ステータス: ✅ 公開中 — https://journal.daoxiao.org/

ドキュメント: [アーキテクチャ・設計判断](./docs/Architecture.md) ・ [IAM最小権限の再設計](./docs/IAM-Least-Privilege.md) ・ [フロントエンド設計](./docs/Frontend-Design.md) ・ [Terraformリファレンス](./infrastructure/terraform/README.md) ・ [ゼロから構築するチュートリアル](./docs/Build-Tutorial/README.md)

## アーキテクチャ

```
CloudFront (journal.daoxiao.org) ── S3（Reactビルド）
  │
  ▼  ログイン / サインアップ
Cognito User Pool  ──JWT (IDトークン)──┐
                                       ▼
                          API Gateway (HTTP API)
                          JWT Authorizer（Cognito連携）
                                       │
                    ┌─────────┬───────┼───────┬─────────┐
                POST /entries GET /entries PUT /entries/{id} DELETE /entries/{id}
                    │         │             │             │
              create_entry list_entries update_entry  delete_entry   (Lambda, Python 3.12)
                    └─────────┴───────┬─────┴─────────────┘
                                      ▼
                           DynamoDB（`entries` テーブル）
                           PK: userId / SK: entryId
```

以下の各設計判断の詳しい理由（セキュリティモデル・シングルテーブル設計の理由・
HTTP APIを選んだ理由など）は[`docs/Architecture.md`](./docs/Architecture.md)を
参照。ここには要約のみ記載する。

## なぜこの設計か

- **HTTP API（REST APIではなく）**: CognitoのJWTをネイティブ検証できる
  `JWT Authorizer`を標準搭載。REST APIより設定がシンプルで低コスト。
  CRUD程度の要件にはREST APIの追加機能は不要。
- **Lambda言語をPython**: ユーザーがPython学習中のため、実務コードがそのまま
  学習教材になる。
- **DynamoDBシングルテーブル + PK=userId/SK=entryId**: すべてのQueryが
  1ユーザーのパーティションに閉じており、他ユーザーのデータへ到達する
  コード経路自体が存在しない（実行時チェックではなく構造的なIDOR対策）。
- **既存IAMユーザー(github-actions-portfolio-01)を再利用**: 新規作成せず、
  Phase毎にGitHub Secretsが増殖しないようにする。
- **CI/CDのスコープはアプリケーションコードの更新のみ**（Lambdaコード・
  フロントエンドビルドの両方）: インフラ変更（Cognito/API Gateway/
  DynamoDB/IAM/S3バケット作成/CloudFront作成/Route53/ACM）はPhase 2と
  同様、ローカルから`terraform apply`で手動デプロイする。CI用IAMユーザーには
  意図的にIAMロール・Cognitoプール・CloudFrontディストリビューション
  「作成」の権限を持たせていない（既存バケットへの書き込みと既存
  ディストリビューションのInvalidationのみ許可）。
- **S3+CloudFrontはPhase 3専用のバケット・ディストリビューション**:
  Phase 1とは完全に独立しており、このPhaseの`terraform destroy`が
  Phase 1・Phase 2に影響することはない。

## デプロイ手順（初回）

```bash
cd aws-portfolio-03-serverless/infrastructure/terraform
terraform init
terraform plan
terraform apply
```

apply完了後、以下のoutputsをReactアプリの環境変数（`.env.local`）に設定する：
- `api_endpoint`
- `cognito_user_pool_id`
- `cognito_user_pool_client_id`

ファイルごとの詳細・全outputs・このPhaseのデプロイで実際に遭遇した注意点
（IAM権限・ACMのリージョン制約・DynamoDBオンデマンドの無料枠）は
[`infrastructure/terraform/README.md`](./infrastructure/terraform/README.md)を参照。

### CloudFormation（参照実装・未デプロイ）

Phase 1の前例に倣い、このPhaseのインフラも
[`infrastructure/cloudformation/`](./infrastructure/cloudformation/)に
CloudFormationテンプレートとして用意している（両ツールで同じ構成を
記述できることを示す目的）。**これらは実際にはデプロイしない**:
本番で稼働しているインフラはTerraform管理であり、これらのテンプレートを
デプロイすると同名の実リソース（2つ目のCognitoプール・2つ目のLambda関数等）
が重複作成されてしまう。全9テンプレートは`aws cloudformation validate-template`
での構文検証済み。デプロイ順序（各ステップのOutputsが次ステップの
`--parameter-overrides`に必要）:

```
dynamodb.yaml ─┐
cognito.yaml ──┼─→ lambda.yaml ─→ api-gateway.yaml
               │
s3-frontend.yaml ─→ cloudfront.yaml ─→ route53.yaml
acm.yaml (us-east-1) ──────────────↗
                                     │
              lambda.yaml + s3-frontend.yaml + cloudfront.yaml のoutputs
                                     ↓
                              iam-cicd.yaml（最後）
```

```bash
cd aws-portfolio-03-serverless/infrastructure/cloudformation

aws cloudformation deploy --template-file dynamodb.yaml --stack-name portfolio-03-dynamodb
aws cloudformation deploy --template-file cognito.yaml --stack-name portfolio-03-cognito
aws cloudformation deploy --template-file lambda.yaml --stack-name portfolio-03-lambda \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides TableName=<dynamodbの出力> TableArn=<dynamodbの出力>
aws cloudformation deploy --template-file api-gateway.yaml --stack-name portfolio-03-api \
  --parameter-overrides CognitoUserPoolId=<...> CognitoUserPoolClientId=<...> \
    CreateEntryFunctionArn=<...> CreateEntryFunctionName=<...> ...(4関数分)

aws cloudformation deploy --template-file s3-frontend.yaml --stack-name portfolio-03-s3 \
  --parameter-overrides BucketName=バケット名
aws cloudformation deploy --template-file acm.yaml --stack-name portfolio-03-acm \
  --region us-east-1
aws cloudformation deploy --template-file cloudfront.yaml --stack-name portfolio-03-cloudfront \
  --parameter-overrides BucketName=<...> BucketArn=<...> BucketRegionalDomainName=<...> \
    AcmCertificateArn=<acmの出力・us-east-1>
aws cloudformation deploy --template-file route53.yaml --stack-name portfolio-03-route53 \
  --parameter-overrides CloudFrontDomainName=<cloudfrontの出力>

aws cloudformation deploy --template-file iam-cicd.yaml --stack-name portfolio-03-iam-cicd \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides CreateEntryFunctionArn=<...> ... FrontendBucketArn=<...> \
    CloudFrontDistributionArn=<...>
```

## React フロントエンド

```bash
cd aws-portfolio-03-serverless/frontend
npm install
cp .env.example .env.local   # 上記のterraform outputsの値を書き込む
npm start                    # ローカル確認
```

本番デプロイは`.github/workflows/deploy-03-frontend.yml`により`frontend/**`への
push時に自動実行される。初回のみGitHub repo Variablesの設定が必要
（`PHASE3_API_ENDPOINT`・`PHASE3_COGNITO_USER_POOL_ID`・`PHASE3_COGNITO_CLIENT_ID`・
`PHASE3_S3_BUCKET_NAME`・`PHASE3_CLOUDFRONT_DIST_ID`。詳細はワークフローファイル
冒頭のコメント参照。AWS認証情報はPhase 1の`AWS_ACCESS_KEY_ID`/
`AWS_SECRET_ACCESS_KEY`シークレットを流用）。手動デプロイもPhase 1と同じ
コマンド体系で可能:
```bash
npm run build
aws s3 sync build/ s3://<frontend_bucket_name> --delete
aws cloudfront create-invalidation --distribution-id <cloudfront_distribution_id> --paths "/*"
```

- **認証**: `amazon-cognito-identity-js`でCognitoと直接通信
  （サインアップ→確認コード→ログイン→IDトークン取得）。
- **API呼び出し**: 全リクエストのAuthorizationヘッダーにIDトークンを付与。
  401が返るとセッション切れとみなしログイン画面へ戻す。
- **Phase 1とのUI統一**: 日記画面はPhase 1の感謝の木・連続日数カウンター・
  タブレイアウト・日英中の言語切替を踏襲している。コンポーネント構成や
  非自明なロジック（連続日数の計算・日数バッジ）の詳細は
  [`docs/Frontend-Design.md`](./docs/Frontend-Design.md)を参照。
- ユーザーが実際のブラウザでサインアップ→確認コード→ログイン→
  insert/update/delete→ログアウトを実施し、動作を確認済み（2026-07-11）。

## 残タスク

なし — Lambda・フロントエンドとも、CI/CDパイプラインの設定・実機での
動作確認まで完了している。

## フォルダ構成

```
aws-portfolio-03-serverless/
├── docs/
│   ├── Architecture.md          # インフラ設計の理由・セキュリティモデル
│   ├── IAM-Least-Privilege.md   # 関数ごとのIAMロール再設計の理由
│   └── Frontend-Design.md       # Reactのコンポーネント/認証/状態設計の理由
├── infrastructure/terraform/
│   ├── README.md              # ファイル別リファレンス・デプロイ/削除・注意点
│   ├── providers.tf
│   ├── variables.tf
│   ├── cognito.tf             # User Pool + App Client
│   ├── dynamodb.tf            # entries テーブル
│   ├── lambda.tf              # 実行ロール + 4関数
│   ├── api_gateway.tf         # HTTP API + JWT Authorizer + ルート
│   ├── iam.tf                 # 既存GitHub Actionsユーザーへの限定ポリシー
│   ├── s3_frontend.tf         # フロントエンド配信用バケット
│   ├── cloudfront.tf          # OAC + CloudFront（journal.daoxiao.org）
│   ├── acm.tf                 # ACM証明書（us-east-1）
│   ├── route53.tf             # Aレコード(alias)
│   └── outputs.tf
├── infrastructure/cloudformation/ # 同じ構成 — 参照実装のみ・未デプロイ
│   ├── dynamodb.yaml, cognito.yaml, lambda.yaml, api-gateway.yaml
│   └── s3-frontend.yaml, acm.yaml, cloudfront.yaml, route53.yaml, iam-cicd.yaml
├── backend/lambda/
│   ├── create_entry/handler.py
│   ├── list_entries/handler.py
│   ├── update_entry/handler.py
│   └── delete_entry/handler.py
└── frontend/
    ├── src/auth/cognito.js       # サインアップ/確認/ログイン/IDトークン取得
    ├── src/api/entries.js        # HTTP APIへのfetchラッパー
    ├── src/components/AuthScreen.js
    ├── src/components/JournalScreen.js
    ├── src/components/GratitudeTree.js
    └── src/App.js                # 認証状態で画面切替
```

# Phase 06 — Enterprise DevOps

Status: ✅ Deployed — a real AWS CodePipeline, not wired to auto-trigger
(see [Architecture.md](./docs/Architecture.md) for why). Run it on demand
to see the full Source → Build → Approve → Deploy flow.

Docs: [Architecture & design decisions](./docs/Architecture.md)

## Architecture

```
GitHub (daoxiao0/aws-portfolio, main)
   │  CodeConnections
   ▼
┌─────────┐    ┌───────────┐    ┌──────────┐    ┌─────────┐
│ Source  │───▶│  Build    │───▶│ Approve  │───▶│ Deploy  │
│ (Code   │    │ (CodeBuild│    │ (manual  │    │ (native │
│ Connect)│    │ docker    │    │  gate)   │    │  ECS    │
└─────────┘    │ build+push│    └──────────┘    │ action) │
                └───────────┘                     └────┬────┘
                                                        ▼
                                          Phase 5's ECS service
                                          (aws-portfolio-05-containers)
```

Manually started only — no EventBridge auto-trigger. See
[`docs/Architecture.md`](./docs/Architecture.md) for why (short version:
Phase 5's GitHub Actions workflow already auto-deploys on app changes;
wiring both to the same trigger means two competing deploys per commit).

## Why this design

- **The point isn't "CodePipeline instead of GitHub Actions"** — it's
  giving the pipeline's service role *real* ECS deploy permissions
  (`ecs:UpdateService` on Phase 5's actual service) and controlling the
  risk with a manual approval gate, instead of the "CI structurally can't
  touch this" answer every prior phase used. See Architecture.md for the
  full framing.
- **Native ECS deploy action, not a second CodeBuild** running
  `aws ecs update-service` — the idiomatic CodePipeline↔ECS integration,
  consumes `imagedefinitions.json` the Build stage writes.
- **No automatic trigger** — a deliberate choice to avoid double-deploying
  alongside Phase 5's existing GitHub Actions image workflow, not an
  oversight. Framed the same way Phase 1 frames its unused CloudFormation
  reference templates: two real implementations, one actively wired up.
- **IAM scoped per resource**: CodeBuild can push to only Phase 5's ECR
  repo; CodePipeline's `iam:PassRole` is scoped by a `Condition`
  (`iam:PassedToService = ecs-tasks.amazonaws.com`) rather than to
  account-wide permissions. Its ECS actions are `ecs:*` — verified
  in practice (not assumed) that AWS's own documented 6-action minimal
  policy for this deploy action instantly fails with `PermissionError`;
  see `docs/Architecture.md`'s IAM gotcha section for the full
  troubleshooting trail.

## Deploy (first time)

```bash
cd aws-portfolio-06-devops/infrastructure/terraform
terraform init
terraform plan
terraform apply
```

**Then, a manual step Terraform can't do**: open
https://console.aws.amazon.com/codesuite/settings/connections, find the
`aws-portfolio-06-devops-github` connection (status `PENDING`), and
complete the GitHub App authorization. `terraform output connection_status`
should read `AVAILABLE` afterward.

## How to run a release

```bash
aws codepipeline start-pipeline-execution --name aws-portfolio-06-devops
```

Watch it in the console, or:

```bash
aws codepipeline get-pipeline-state --name aws-portfolio-06-devops
```

When it reaches the **Approve** stage, approve it (console, or
`aws codepipeline put-approval-result`) to let Deploy proceed. Requires
Phase 5's ECS service to actually exist — if Phase 5 has been destroyed
(its default idle state, given its own standing cost), redeploy it first.

## Teardown

```bash
cd aws-portfolio-06-devops/infrastructure/terraform
terraform destroy
```

Unlike Phase 5's compute, this phase is **not** expected to be
destroyed/rebuilt between demos — CodePipeline/CodeBuild/CodeConnections
are the ~$1/month standing cost noted in `docs/Cost-Estimation.md`, small
enough to leave running. Destroy only if actually decommissioning the
phase.

### CloudFormation (reference implementation, not deployed)

Following Phases 1/3/4/5's precedent,
[`infrastructure/cloudformation/`](./infrastructure/cloudformation/)
mirrors the same architecture across 4 templates (`codeconnections.yaml`,
`s3-artifacts.yaml`, `codebuild.yaml`, `codepipeline.yaml`) — **not
deployed**, `cfn-lint`-clean. Deployment order:

```bash
cd aws-portfolio-06-devops/infrastructure/cloudformation

aws cloudformation deploy --template-file codeconnections.yaml --stack-name portfolio-06-connections

aws cloudformation deploy --template-file s3-artifacts.yaml --stack-name portfolio-06-s3

aws cloudformation deploy --template-file codebuild.yaml --stack-name portfolio-06-codebuild \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ArtifactBucketArn=<from s3-artifacts.yaml output>

aws cloudformation deploy --template-file codepipeline.yaml --stack-name portfolio-06-pipeline \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ArtifactBucketName=<...> ArtifactBucketArn=<...> \
    ConnectionArn=<from codeconnections.yaml, must be AVAILABLE> \
    CodeBuildProjectName=<...> CodeBuildProjectArn=<...>
```

## Remaining work

- Automated tests in the Build stage before push (currently build+push
  only, no test gate)
- A staging vs. production distinction — currently one pipeline, one
  environment (Phase 5), matching that phase's own single-environment
  scope

## Folder structure

```
aws-portfolio-06-devops/
├── buildspec.yml            # CodeBuild: docker build → ECR push → imagedefinitions.json
├── docs/
│   └── Architecture.md      # design rationale — read this first
├── infrastructure/terraform/
│   ├── providers.tf, variables.tf, outputs.tf
│   ├── codeconnections.tf   # GitHub connection (starts PENDING)
│   ├── codebuild.tf         # project + least-privilege role (ECR push scoped to Phase 5's repo)
│   └── codepipeline.tf      # artifact bucket, pipeline role, 4-stage pipeline, no auto-trigger
└── infrastructure/cloudformation/ # same architecture — reference only, never deployed
    ├── codeconnections.yaml, s3-artifacts.yaml, codebuild.yaml, codepipeline.yaml
```

---

# Phase 06 — Enterprise DevOps（日本語）

ステータス: ✅ デプロイ済み——自動トリガーには繋げていない実際のAWS
CodePipeline（理由は[Architecture.md](./docs/Architecture.md)参照）。
Source→Build→Approve→Deployの一連の流れをオンデマンドで確認できる。

ドキュメント: [アーキテクチャ・設計判断](./docs/Architecture.md)

## 構成

```
GitHub (daoxiao0/aws-portfolio, main)
   │  CodeConnections
   ▼
┌─────────┐    ┌───────────┐    ┌──────────┐    ┌─────────┐
│ Source  │───▶│  Build    │───▶│ Approve  │───▶│ Deploy  │
│ (Code   │    │ (CodeBuild│    │（手動    │    │（標準   │
│ Connect)│    │ docker    │    │ 承認     │    │  ECS    │
└─────────┘    │ build+push│    │ ゲート） │    │ アクション│
                └───────────┘    └──────────┘    └────┬────┘
                                                        ▼
                                          Phase 5のECSサービス
                                          (aws-portfolio-05-containers)
```

手動起動専用——EventBridgeの自動トリガーなし。理由は
[`docs/Architecture.md`](./docs/Architecture.md)参照（要約：Phase 5の
GitHub Actionsワークフローが既にアプリ変更時に自動デプロイしており、
同じトリガーに繋ぐと1コミットごとに2つのデプロイが競合するため）。

## なぜこの設計か

- **「GitHub Actionsの代わりにCodePipelineを使う」ことが本質ではない**
  ——パイプラインのサービスロールに*本物の*ECSデプロイ権限
  （Phase 5の実サービスへの`ecs:UpdateService`）を与え、手動承認ゲートで
  リスクを制御する、という選択をしたこと——これまでの全Phaseが使ってきた
  「CIには構造的に触らせない」という答えの代わりに。詳しい説明は
  Architecture.md参照。
- **標準のECSデプロイアクション**（`aws ecs update-service`を叩く
  2つ目のCodeBuildではなく）——CodePipeline↔ECSの慣用的な連携方式で、
  BuildステージがwriteするimageDefinitions.jsonを消費する
- **自動トリガーなし**——Phase 5の既存GitHub Actionsイメージワークフロー
  との二重デプロイを避けるための意図的な選択であり、見落としではない。
  Phase 1が未使用のCloudFormation参照実装に対して取っているのと同じ
  枠組み：同じ仕事の実装が2つあり、片方だけが実際に配線されている
- **IAMはリソース単位で絞る**：CodeBuildがpushできるのはPhase 5の
  ECRリポジトリのみ、CodePipelineの`iam:PassRole`はConditionで絞る
  （`iam:PassedToService = ecs-tasks.amazonaws.com`）——アカウント全体への
  包括的な権限ではない。ただしECSアクションは`ecs:*`——AWS公式ドキュメント
  が示す6アクションの最小権限ポリシーでは実機で毎回即時に
  `PermissionError`となることを検証済み（推測ではない）。詳細な切り分けは
  `docs/Architecture.md`のIAMギャップ節を参照

## デプロイ手順（初回）

```bash
cd aws-portfolio-06-devops/infrastructure/terraform
terraform init
terraform plan
terraform apply
```

**その後、Terraformでは完結しない手動ステップ**：
https://console.aws.amazon.com/codesuite/settings/connections を開き、
`aws-portfolio-06-devops-github`接続（ステータス`PENDING`）を見つけて
GitHub Appの認可を完了させる。完了後`terraform output
connection_status`が`AVAILABLE`になるはず。

## リリースの実行方法

```bash
aws codepipeline start-pipeline-execution --name aws-portfolio-06-devops
```

コンソールで確認するか：

```bash
aws codepipeline get-pipeline-state --name aws-portfolio-06-devops
```

**Approve**ステージに到達したら承認する（コンソール、または
`aws codepipeline put-approval-result`）とDeployが進む。Phase 5のECS
サービスが実在している必要がある——Phase 5がdestroy済み（自身の
稼働コストのためデフォルトはこの状態）なら、先に再デプロイすること。

## 削除手順

```bash
cd aws-portfolio-06-devops/infrastructure/terraform
terraform destroy
```

Phase 5のコンピュートと異なり、本Phaseは**デモの合間にdestroy/再構築
することを想定していない**——CodePipeline/CodeBuild/CodeConnectionsは
`docs/Cost-Estimation.md`に記載の月額約$1の常時コストであり、動かし
続けても十分小さい。実際にこのPhaseを廃止する場合のみdestroyする。

### CloudFormation（参照実装・未デプロイ）

Phase 1・3・4・5の前例に倣い、
[`infrastructure/cloudformation/`](./infrastructure/cloudformation/)に
同じ構成を4テンプレート（`codeconnections.yaml`・`s3-artifacts.yaml`・
`codebuild.yaml`・`codepipeline.yaml`）で用意している——**未デプロイ**・
`cfn-lint`通過済み。デプロイ順序：

```bash
cd aws-portfolio-06-devops/infrastructure/cloudformation

aws cloudformation deploy --template-file codeconnections.yaml --stack-name portfolio-06-connections

aws cloudformation deploy --template-file s3-artifacts.yaml --stack-name portfolio-06-s3

aws cloudformation deploy --template-file codebuild.yaml --stack-name portfolio-06-codebuild \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ArtifactBucketArn=<s3-artifacts.yamlの出力>

aws cloudformation deploy --template-file codepipeline.yaml --stack-name portfolio-06-pipeline \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ArtifactBucketName=<...> ArtifactBucketArn=<...> \
    ConnectionArn=<codeconnections.yamlの出力・AVAILABLEであること> \
    CodeBuildProjectName=<...> CodeBuildProjectArn=<...>
```

## 残タスク

- Buildステージでのpush前の自動テスト（現状はbuild+pushのみ、テスト
  ゲートなし）
- staging/production環境の区別——現状はパイプライン1本・環境1つ
  （Phase 5）のみ、そのPhase自体が単一環境スコープであることに対応

## フォルダ構成

```
aws-portfolio-06-devops/
├── buildspec.yml            # CodeBuild: docker build → ECR push → imagedefinitions.json
├── docs/
│   └── Architecture.md      # 設計の理由——まずこれを読む
├── infrastructure/terraform/
│   ├── providers.tf, variables.tf, outputs.tf
│   ├── codeconnections.tf   # GitHub接続（PENDING状態で開始）
│   ├── codebuild.tf         # プロジェクト＋最小権限ロール（ECR pushはPhase 5のリポジトリに限定）
│   └── codepipeline.tf      # アーティファクトバケット・パイプラインロール・4ステージ・自動トリガーなし
└── infrastructure/cloudformation/ # 同じ構成 — 参照実装のみ・未デプロイ
    ├── codeconnections.yaml, s3-artifacts.yaml, codebuild.yaml, codepipeline.yaml
```

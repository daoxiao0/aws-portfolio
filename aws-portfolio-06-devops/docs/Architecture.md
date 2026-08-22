# Architecture — Phase 06 Enterprise DevOps

## What this phase actually demonstrates

The roadmap calls this "Enterprise DevOps: CodePipeline, Terraform,
GitHub Actions." It would be easy to build a CodePipeline that just does
what Phase 5's GitHub Actions workflow already does — build, push, deploy
— and call that "enterprise." That's not really the interesting part.

**The interesting part is a tension every prior phase's README states
explicitly**: *"infra changes are deployed manually via `terraform apply`
— the CI role deliberately lacks IAM/CloudWatch/ECS/RDS permissions."*
That's the safe answer to "how do you let automation deploy without
over-trusting it": don't give it the permission at all. It's also the
answer that doesn't scale to a real engineering org, where *someone's*
pipeline eventually does need to hold real deploy permissions.

Phase 6 demonstrates the other answer: **give the pipeline the real
permission, and gate the dangerous action behind a human approval step
instead of withholding the permission.** The CodePipeline service role
genuinely can call `ecs:UpdateService` on Phase 5's service — nothing like
every prior phase's OIDC role, which structurally cannot touch ECS/RDS at
all. What makes this safe isn't "the pipeline can't do damage," it's "a
human looks at what's about to ship before it does." That's the actual
enterprise-governance pattern (deployment approval gates, change
management, "who signed off on this release") — not just "we used
CodePipeline instead of GitHub Actions."

## Pipeline shape

```
Source (CodeConnections → GitHub, daoxiao0/aws-portfolio, main)
   │
   ▼
Build (CodeBuild: docker build → ECR push → write imagedefinitions.json)
   │
   ▼
Approve (manual approval action — the actual governance step)
   │
   ▼
Deploy (CodePipeline's native ECS action → updates Phase 5's service)
```

The Deploy stage uses CodePipeline's built-in `ECS` deploy action, not a
second CodeBuild project running `aws ecs update-service`. The native
action registers a new task definition revision (based on Phase 5's
current one, image URI swapped for the one Build just pushed) and updates
the service — this is the standard, idiomatic CodePipeline↔ECS
integration and needs `ecs:RegisterTaskDefinition` +
`iam:PassRole` (scoped to Phase 5's two task roles) rather than reaching
into the CLI directly.

## Why there's no automatic trigger

CodeConnections sources normally wire up an EventBridge rule that starts
the pipeline on every push to the branch. This pipeline **deliberately
doesn't have one**. Phase 5's `deploy-05-containers-image.yml` (GitHub
Actions) already builds, pushes, and force-redeploys automatically on
`aws-portfolio-05-containers/app/**` changes — wiring this pipeline to the
same trigger means every app commit fires two independent, competing
deploys of the same service.

Rather than disable the working GitHub Actions path (or scope this
pipeline's trigger to some other directory it wouldn't meaningfully react
to), the honest choice was: **this pipeline is a complete, real, second
implementation of the same job, left manually-started only**
(`aws codepipeline start-pipeline-execution` or the console's "Release
change"). That's the same relationship Phase 1 has between its live
Terraform and its never-applied CloudFormation reference templates — two
working implementations of the same infrastructure, only one actively
running at a time. Leaving an unused auto-trigger in place and pretending
it wasn't there would have been the quieter-looking but less honest
option.

## The one step I couldn't automate

`aws_codestarconnections_connection` (Terraform) / `AWS::CodeStarConnections::Connection`
(CloudFormation) both create the connection in `PENDING` status — AWS
requires a human to open it in the console and complete the GitHub App
OAuth authorization before `UseConnection` actually works. No IaC tool can
do that handshake; this is the same shape as Phase 4's SNS email
confirmation (I can wire everything up to the last inch, but the final
click has to be a person).

## IAM: least privilege per resource, not per phase

Both service roles (CodeBuild, CodePipeline) follow the same pattern
established in Phase 3's IAM-Least-Privilege redesign — scoped to the
specific resources they touch, not blanket `*Access` managed policies:

- CodeBuild's role can push to **only** Phase 5's ECR repo (by ARN), not
  `ecr:*` account-wide.
- CodePipeline's role can `iam:PassRole` **only** Phase 5's two task
  roles (`-task`, `-task-execution`) — it cannot pass any other role in
  the account, which matters because `PassRole` is exactly the permission
  that turns "can register a task definition" into "can grant a Fargate
  task whatever permissions that role holds."
- `ecs:DescribeServices` / `ecs:RegisterTaskDefinition` / etc. are left at
  `Resource: "*"` because AWS's ECS API doesn't support resource-level
  scoping for most of these actions — not a shortcut, a documented AWS
  limitation (same exception already noted for `ecr:GetAuthorizationToken`
  in Phase 5/6's CodeBuild roles).

---

# アーキテクチャ — Phase 06 Enterprise DevOps（日本語）

## このPhaseが実際に示していること

ロードマップはこれを「Enterprise DevOps: CodePipeline, Terraform, GitHub
Actions」と呼んでいる。Phase 5のGitHub Actionsワークフローが既にやって
いること——build・push・deploy——をそのままやるCodePipelineを作って
「これがエンタープライズです」と言うのは簡単だが、それは本質的な
部分ではない。

**本質的な部分は、これまでの全Phaseのreadmeが明示的に述べてきた
緊張関係にある**：「インフラ変更はローカルから`terraform apply`で
手動デプロイする——CI用のロールには意図的にIAM/CloudWatch/ECS/RDS
権限を持たせていない」。これは「自動化にデプロイを任せつつ、過信しない
にはどうするか」への安全な答えだ：権限そのものを与えない。ただし
これは、実際のエンジニア組織にはスケールしない答えでもある——組織が
大きくなれば、いずれ*誰かの*パイプラインが本物のデプロイ権限を
持たなければならなくなる。

Phase 6はもう一つの答えを示す：**パイプラインに本物の権限を与え、
危険なアクションの手前に人間の承認ステップを置くことで制御する
——権限そのものを取り上げるのではなく。** CodePipelineサービスロールは
実際にPhase 5のサービスに対して`ecs:UpdateService`を呼べる——これまでの
全PhaseのOIDCロール（構造的にECS/RDSに一切触れない）とは根本的に違う。
これを安全にしているのは「パイプラインが害を及ぼせない」ことではなく
「出荷される直前に人間が中身を見る」ことだ。これこそが本物のエンター
プライズ・ガバナンスのパターン（デプロイ承認ゲート・変更管理・
『誰がこのリリースを承認したか』）であり、単に「GitHub Actionsの
代わりにCodePipelineを使った」だけではない。

## パイプラインの構成

```
Source (CodeConnections → GitHub, daoxiao0/aws-portfolio, main)
   │
   ▼
Build (CodeBuild: docker build → ECR push → imagedefinitions.json作成)
   │
   ▼
Approve（手動承認アクション——実質的なガバナンスステップ）
   │
   ▼
Deploy（CodePipeline標準のECSデプロイアクション→Phase 5のサービスを更新）
```

DeployステージはCodePipeline標準の`ECS`デプロイアクションを使用しており、
2つ目のCodeBuildプロジェクトで`aws ecs update-service`を叩く構成にはして
いない。標準アクションは新しいタスク定義リビジョンを登録し（Phase 5の
現行定義をベースに、イメージURIだけBuildが直前にpushしたものへ差し替え）、
サービスを更新する——これがCodePipeline↔ECSの標準的で慣用的な連携方式
であり、そのために`ecs:RegisterTaskDefinition`＋`iam:PassRole`
（Phase 5の2つのタスクロールに限定）が必要になる（CLIを直接叩くのではなく）。

## なぜ自動トリガーを設定しないのか

CodeConnectionsソースは通常、ブランチへのpushごとにパイプラインを
起動するEventBridgeルールを自動配線する。本パイプラインは**意図的に
それを持たない**。Phase 5の`deploy-05-containers-image.yml`（GitHub
Actions）が既に`aws-portfolio-05-containers/app/**`の変更時に自動で
build・push・強制再デプロイを行っている——本パイプラインを同じ
トリガーに繋ぐと、アプリへの1コミットごとに同じサービスへの独立した
デプロイが2つ競合して発火してしまう。

動いているGitHub Actions側を無効化する（あるいは本パイプラインの
トリガーを意味のない別ディレクトリに逃がす）のではなく、率直な選択を
した：**本パイプラインは同じ仕事の完全でリアルな、2つ目の実装として、
意図的に手動起動専用のまま**にする（`aws codepipeline
start-pipeline-execution`、またはコンソールの「Release change」）。
これはPhase 1の、稼働中のTerraformと未適用のCloudFormation参照実装との
関係と同じ形——同じインフラの動く実装が2つあり、そのうち1つだけが
実際に稼働している。未使用の自動トリガーをそのまま残して存在しない
ふりをするより、この方が正直な選択だった。

## 自動化できなかった1ステップ

`aws_codestarconnections_connection`（Terraform）／
`AWS::CodeStarConnections::Connection`（CloudFormation）はどちらも
接続を`PENDING`状態で作成する——AWSは、`UseConnection`が実際に機能する
前に、人間がコンソールでGitHub AppのOAuth認可を完了させることを要求
する。どのIaCツールもこのハンドシェイクを代行できない。これはPhase 4の
SNSメール確認と同じ形（最後の1クリックまで配線はできるが、そのクリック
自体は人間がやるしかない）。

## IAM：Phase単位ではなくリソース単位の最小権限

CodeBuild・CodePipeline両方のサービスロールは、Phase 3のIAM最小権限
再設計で確立したのと同じパターンに従っている——包括的な`*Access`
管理ポリシーではなく、実際に触れる特定のリソースに限定する：

- CodeBuildのロールがpushできるのは**Phase 5のECRリポジトリのみ**
  （ARN指定）、アカウント全体の`ecr:*`ではない
- CodePipelineのロールが`iam:PassRole`できるのは**Phase 5の2つの
  タスクロール**（`-task`・`-task-execution`）のみ——アカウント内の
  他のロールは一切渡せない。これが重要なのは、`PassRole`こそが
  「タスク定義を登録できる」を「そのロールが持つ任意の権限をFargate
  タスクに与えられる」に変える権限だから
- `ecs:DescribeServices`／`ecs:RegisterTaskDefinition`等は
  `Resource: "*"`のまま——ECSのAPIの多くがリソースレベルの権限指定に
  対応していないため（近道ではなく、文書化されたAWS側の制約。
  Phase 5/6のCodeBuildロールで既に注記した`ecr:GetAuthorizationToken`
  と同種の例外）

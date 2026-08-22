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
integration and needs ECS permissions + a conditioned `iam:PassRole`
rather than reaching into the CLI directly (see the IAM gotcha below —
what's actually required here turned out to be broader than AWS's own
documented example).

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
- `iam:PassRole` is scoped with a `Condition` (`iam:PassedToService =
  ecs-tasks.amazonaws.com`, `Resource: "*"`) rather than to Phase 5's two
  task role ARNs directly — see the gotcha below for why.
- `ecs:DescribeServices` / `ecs:RegisterTaskDefinition` / etc. are left at
  `Resource: "*"` because AWS's ECS API doesn't support resource-level
  scoping for most of these actions — not a shortcut, a documented AWS
  limitation (same exception already noted for `ecr:GetAuthorizationToken`
  in Phase 5/6's CodeBuild roles).

## Gotcha: the Deploy stage's pre-flight permission check doesn't match AWS's own documented policy

AWS's own IAM example for the CodePipeline `ECS` deploy action lists
exactly six actions (`ecs:DescribeServices`, `DescribeTaskDefinition`,
`DescribeTasks`, `ListTasks`, `RegisterTaskDefinition`, `UpdateService`)
plus a scoped `iam:PassRole`. That's what this pipeline's role started
with. Every real execution's Deploy stage failed instantly (~1 second,
before Source/Build/Approve's several-minutes-each pace) with
`PermissionError: The provided role does not have sufficient permissions
to access ECS`.

Ruled out step by step, each on a real pipeline run:

1. **Scoped `PassRole` (two explicit role ARNs) → broadened to
   `Resource: "*"` + `iam:PassedToService` condition** (AWS's documented
   pattern for this exact case). Reran — same instant failure.
2. Verified with `aws iam simulate-principal-policy` that all six
   documented actions evaluated as `allowed` against the role. The
   failure persisted anyway, which rules out an actual missing permission
   the ECS API would need at runtime — the check failing here is
   CodePipeline's own pre-flight validation, not a real ECS `AccessDenied`.
3. Added `ecs:DescribeClusters` alone (a plausible pre-check the
   pipeline might run to validate the `ClusterName` parameter). Reran —
   same failure.
4. Added a batch of other plausible candidates in one shot
   (`ecs:ListClusters`, `TagResource`, `UntagResource`,
   `ListTagsForResource`, `DescribeTaskSets`, `CreateTaskSet`,
   `DeleteTaskSet`, `UpdateServicePrimaryTaskSet`). Reran — still failed.
5. Replaced the whole statement with `ecs:*`. Reran — **succeeded**,
   confirmed twice across two separate pipeline executions, each verified
   against the live ECS service (new task definition revision registered,
   rollout `COMPLETED`, `/health` returning 200 through Phase 5's ALB).

Conclusion: this isn't a missing-permission bug in the ordinary sense —
IAM simulation shows the documented six actions as fully allowed, and
adding fourteen more specific candidates on top of them didn't help
either. Whatever check the CodePipeline `ECS` deploy action runs before
starting the Deploy action appears to look for the `ecs:*` wildcard
specifically, not equivalent effective permissions. This directly
contradicts AWS's own published minimal-policy example for this feature.
The role here uses `ecs:*` (`Resource: "*"`, no cross-service reach) as a
documented, deliberate exception to this project's per-resource IAM
policy — not an unexamined shortcut.

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
であり、そのためにECS権限＋Conditionで絞った`iam:PassRole`が必要になる
（CLIを直接叩くのではなく。実際に必要だった権限はAWS公式ドキュメントの
例より広かった——詳細は後述のIAMギャップ参照）。

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
- `iam:PassRole`はPhase 5の2ロールのARN直接指定ではなく、
  `Condition`（`iam:PassedToService = ecs-tasks.amazonaws.com`、
  `Resource: "*"`）で絞っている——理由は下記の実機トラブルシュート参照
- `ecs:DescribeServices`／`ecs:RegisterTaskDefinition`等は
  `Resource: "*"`のまま——ECSのAPIの多くがリソースレベルの権限指定に
  対応していないため（近道ではなく、文書化されたAWS側の制約。
  Phase 5/6のCodeBuildロールで既に注記した`ecr:GetAuthorizationToken`
  と同種の例外）

## 実機で発覚したギャップ：DeployステージのIAM事前チェックはAWS公式ドキュメントの最小権限例と一致しない

CodePipelineの`ECS`デプロイアクション用にAWSが公式ドキュメントで示す
IAM例は、正確に6アクション（`ecs:DescribeServices`・
`DescribeTaskDefinition`・`DescribeTasks`・`ListTasks`・
`RegisterTaskDefinition`・`UpdateService`）と、絞り込んだ`iam:PassRole`
のみ。本パイプラインのロールは最初この6アクションで構築した。しかし
実際のパイプライン実行では、DeployステージがSource／Build／Approve（各
数分かかる）とは対照的に、開始からわずか約1秒で毎回
`PermissionError: The provided role does not have sufficient permissions
to access ECS`で即失敗した。

実機のパイプライン実行を使って、1つずつ切り分けた：

1. **`PassRole`をPhase 5の2ロールARN直接指定 → `Resource: "*"` +
   `iam:PassedToService`のConditionへ拡大**（AWS公式が示すこのケース用の
   パターンそのもの）。再実行——同じ即時失敗
2. `aws iam simulate-principal-policy`で、上記6アクション全てが
   ロールに対して`allowed`と評価されることを確認。それでも失敗は
   再現した——これは実行時にECS APIが要求する権限が本当に不足している
   わけではなく、この失敗がCodePipeline自身の実行前バリデーションで
   あることを示している（実際のECS側`AccessDenied`ではない）
3. `ecs:DescribeClusters`のみを追加（`ClusterName`パラメータの事前検証で
   呼ばれていそうな候補として）。再実行——同じ失敗
4. さらに複数の候補（`ecs:ListClusters`・`TagResource`・
   `UntagResource`・`ListTagsForResource`・`DescribeTaskSets`・
   `CreateTaskSet`・`DeleteTaskSet`・`UpdateServicePrimaryTaskSet`）を
   まとめて追加。再実行——それでも失敗
5. ステートメント全体を`ecs:*`に置き換え。再実行——**成功**。別々の
   パイプライン実行2回で確認済みで、それぞれ実際のECSサービス側でも
   検証した（新しいタスク定義リビジョンが登録され、rolloutは
   `COMPLETED`、Phase 5のALB経由の`/health`も200を返す）

結論：これは通常の意味での「権限不足バグ」ではない——IAMシミュレーション
では公式ドキュメントの6アクションは全て許可されていると評価され、
さらに14個の候補アクションを追加しても解決しなかった。CodePipelineの
`ECS`デプロイアクションがDeploy開始前に行っている何らかのチェックは、
実効的に同等な権限セットではなく、`ecs:*`というワイルドカードの存在
そのものを見ているように見える。これはAWS自身が公開している最小権限
ポリシー例と直接矛盾する。本ロールでは`ecs:*`（`Resource: "*"`、他
サービスへの越境なし）を、本プロジェクトのリソース単位IAM方針に対する
文書化済み・意図的な例外として採用している——見落としによる近道では
ない。

# Architecture — Phase 05 Containers

## What this phase is (and isn't)

The roadmap calls Phase 05 "Containers: ECS Fargate, ALB, RDS." Rather than
re-implement the Gratitude Journal a third time (Phase 3 already covers the
Cognito/JWT auth story thoroughly), this phase is a **deliberately minimal**
FastAPI service — `GET /health`, `GET /notes`, `POST /notes` — whose only
job is to prove the infrastructure pattern actually works end to end:
ECS Fargate task → ALB → RDS Postgres, with a real write and a real read
verified against production AWS, not just `terraform apply` succeeding.

This is also the **first phase with a real standing cost** (Phases 1–4 all
round to ~$0/month). Cost-Estimation.md has the numbers; this doc is about
the architecture decisions that were made specifically to keep that cost
down and to make tearing the phase down, between demos, actually clean.

## No new VPC, no NAT Gateway

The account already has a default VPC (`vpc-0046de735c86c4c3a`) with public
subnets across 3 AZs — checked with `aws ec2 describe-vpcs` /
`describe-subnets` before writing any Terraform, rather than assuming a new
VPC was needed. Reusing it means there's no VPC/Internet Gateway/route
table for this phase to create or later destroy.

More importantly: **there's no NAT Gateway.** The typical "ECS in private
subnets" tutorial puts NAT Gateway in front of the private subnet so tasks
can reach the internet (pull images, call APIs) without being directly
reachable — but NAT Gateway costs ~$32–35/month **whether or not anything
uses it**, and that's true 24/7, demo or no demo. For a portfolio workload
that's the single most avoidable recurring cost in the whole phase.

Instead: the ALB, the ECS tasks, and RDS all sit in the **public** subnets.
- The ALB is meant to be public — no change there.
- ECS tasks get `assign_public_ip = true` and reach the internet (to pull
  from ECR, ship logs) directly, no NAT needed.
- RDS being in a "public" subnet does **not** mean it's reachable from the
  internet — actual access control is the security group, not the subnet's
  route table (see below). A real production system would still put RDS
  and the app tier in private subnets behind NAT; this demo doesn't need
  that isolation to prove the pattern, and paying $32+/month to demonstrate
  it wasn't the point.

## Security groups do the isolation NAT/private-subnets would otherwise do

Three security groups, each only trusting the one before it:

```
Internet ──80──▶ [ALB SG]
                     │  (container port only)
                     ▼
              [ECS task SG]
                     │  (5432 only)
                     ▼
                [RDS SG]
```

RDS's security group accepts port 5432 **only** from the ECS task security
group — not from `0.0.0.0/0`, not even from the rest of the VPC. Despite
sitting in a technically-public subnet, Postgres is unreachable from the
internet. This is the trade-off stated plainly: subnet-level network
isolation (what NAT + private subnets would give you) is replaced with
security-group-level isolation, which is sufficient for a demo of this
shape but is a real, conscious difference from a production reference
architecture.

## Why destroy needed no separate Terraform config

The ask was "build this cheaply enough to tear down between demos." That's
just `terraform destroy` on the same configuration used to create
everything — Terraform doesn't need a second config to delete what it
made. What actually blocks a *clean, one-command* destroy on AWS in
practice is a short list of specific guards, so the resources were
designed from the start with all of them turned off deliberately:

| Resource | Guard that would block destroy | Setting used |
|---|---|---|
| RDS instance | Deletion protection | `deletion_protection = false` |
| RDS instance | Final snapshot requirement | `skip_final_snapshot = true` |
| ECR repository | Refuses to delete while it holds images | `force_delete = true` |

None of these are hidden — they're each one line, sitting right next to
the resource they apply to. **This was actually tested, not just assumed**:
after the first successful `terraform apply` and an end-to-end verification
(`POST /notes` then `GET /notes` returning it), `terraform destroy` was run
immediately and completed — **18 resources destroyed, zero manual
cleanup, no snapshot prompt, no deletion-protection error** — then
`terraform apply` again to bring it back for the CloudFormation reference
build. Total round-trip: ECS service teardown ~7 minutes (waits for the
ALB to deregister the task), RDS teardown ~4 minutes; RDS creation is the
long pole on the way back up (~5 minutes).

## DB credentials: plaintext environment variable, not Secrets Manager

`random_password` generates the RDS password at `apply` time; it's injected
into the ECS task definition as a plain environment variable, visible to
anyone who can read the task definition (e.g. `aws ecs describe-task-definition`)
or the AWS console. The more correct pattern is an ECS `secrets` block
pointing at a Secrets Manager secret or an SSM `SecureString` parameter,
resolved by the ECS agent at task launch rather than baked into the
definition. That wasn't done here — it would add a Secrets Manager
resource + IAM permission on the task execution role for a demo database
holding no real data, and the plan was explicit about keeping this phase
small. Recorded as a deliberate simplification, not an oversight — the
natural next increment if this pattern were used for anything with actual
secrets at stake.

## CloudFormation reference implementation

Following Phases 1/3/4's precedent, `infrastructure/cloudformation/`
mirrors the same five pieces (network/security groups, ECR, RDS, ALB, ECS)
as separate templates — never deployed, `cfn-lint`-clean. One footnote:
the reference `rds.yaml` pins Postgres `16.14` instead of the
Terraform-deployed `16.15`, purely because `cfn-lint`'s bundled version
list doesn't yet include `16.15` (confirmed via the real AWS API — it
deploys and runs fine) — a one-patch-version difference with no functional
effect on a template that's never applied, not a real inconsistency.

---

# アーキテクチャ — Phase 05 Containers（日本語）

## このPhaseは何か（何でないか）

ロードマップのPhase 05は「Containers: ECS Fargate, ALB, RDS」。Gratitude
Journalを3度目の実装として作り直すのではなく（Phase 3が既にCognito/JWT
認証のストーリーを十分にカバーしている）、本Phaseは**意図的に最小限**の
FastAPIサービス——`GET /health`・`GET /notes`・`POST /notes`——であり、
その唯一の役割は「ECS Fargateタスク→ALB→RDS Postgres」というインフラ
パターンが実際にエンドツーエンドで機能することを、`terraform apply`が
成功するだけでなく、本番AWSに対する実際の書き込み・読み取りで証明する
ことにある。

本Phaseは**初めて実質的な常時コストが発生するPhase**でもある（Phase
1〜4はすべて月額$0に丸まる）。数字はCost-Estimation.mdに、本ドキュメントは
そのコストを抑え、かつデモの合間の解体を実際にクリーンにするために
下した設計判断について書く。

## 新規VPCなし、NAT Gatewayなし

このアカウントには既に3AZの公開サブネットを持つデフォルトVPC
（`vpc-0046de735c86c4c3a`）が存在する——Terraformを書く前に
`aws ec2 describe-vpcs`／`describe-subnets`で確認済みで、新規VPCが
必要だと決め打ちしていない。これを流用することで、本Phaseが新たに
作って後で壊すVPC/Internet Gateway/ルートテーブルが存在しない。

さらに重要なのは：**NAT Gatewayを作らない。** 典型的な「ECSをprivate
サブネットに置く」チュートリアルでは、privateサブネットのタスクが
インターネットに到達できるようNAT Gatewayを前段に置くが、NAT Gatewayは
**使われていようがいまいが月額約$32〜35**かかり、しかもそれが24時間
365日続く——デモがある日もない日も関係なく。ポートフォリオ用途の
ワークロードにとって、これは本Phase全体で最も避けやすい経常コストである。

代わりに：ALB・ECSタスク・RDSはすべて**公開**サブネットに置く。
- ALBはもともと公開されるべきものなので変更なし
- ECSタスクは`assign_public_ip = true`でインターネットに直接到達
  （ECRからのpull・ログ送信）——NAT不要
- RDSが「公開」サブネットにあることは、インターネットから到達可能で
  あることを**意味しない**——実際のアクセス制御はサブネットのルート
  テーブルではなくセキュリティグループが担う（下記参照）。本物の
  本番システムであればRDSとアプリ層は依然としてprivateサブネット＋
  NAT配下に置くべきだが、本デモではこのパターンを証明するのにそこまでの
  隔離は不要であり、それを示すためだけに月$32以上払うことが目的では
  なかった

## NAT/privateサブネットの代わりにセキュリティグループが隔離を担う

3つのセキュリティグループが、それぞれ直前の1つだけを信頼する：

```
Internet ──80──▶ [ALB SG]
                     │  （コンテナポートのみ）
                     ▼
              [ECSタスクSG]
                     │  （5432のみ）
                     ▼
                [RDS SG]
```

RDSのセキュリティグループが5432番を許可するのは**ECSタスクの
セキュリティグループからのみ**——`0.0.0.0/0`からではなく、VPC内の
他のものからでもない。技術的には公開サブネットにあるにも関わらず、
Postgresはインターネットから到達不可能。これは率直に述べておくべき
トレードオフである：NAT＋privateサブネットが与えるはずだった
サブネットレベルのネットワーク隔離を、セキュリティグループレベルの
隔離で代替している——この規模のデモには十分だが、本番参照アーキテクチャ
とは実際に異なる、意識的な選択である。

## なぜ「削除用」に別のTerraformが不要だったのか

依頼は「デモの合間に壊しておけるくらい安く作る」ことだった。それは
作成に使ったのと同じ設定に対して`terraform destroy`を実行するだけで
よい——Terraformは、作ったものを消すために2つ目の設定を必要としない。
実際にAWSで「クリーンに1コマンドで完走するdestroy」を妨げるのは、
具体的な数個のガードなので、最初からそれらすべてを意図的に無効化した
状態でリソースを設計した：

| リソース | destroyを妨げるガード | 使用した設定 |
|---|---|---|
| RDSインスタンス | 削除保護 | `deletion_protection = false` |
| RDSインスタンス | 最終スナップショット要求 | `skip_final_snapshot = true` |
| ECRリポジトリ | イメージが残っていると削除拒否 | `force_delete = true` |

どれも隠していない——それぞれ対応するリソースのすぐ隣にある1行のみ。
**これは実際にテストした、想定だけで済ませていない**：最初の
`terraform apply`成功とエンドツーエンド確認（`POST /notes`後に
`GET /notes`で反映を確認）の直後、すぐに`terraform destroy`を実行し、
**18リソース削除・手動クリーンアップ0件・スナップショット確認プロンプト
なし・削除保護エラーなし**で完走した——その後CloudFormation参照実装
作成のため再度`terraform apply`した。往復の所要時間：ECSサービスの
解体に約7分（ALBがタスクを登録解除するまで待つため）、RDSの解体に
約4分。再構築時はRDS作成が律速（約5分）。

## DB認証情報：Secrets Managerではなく平文の環境変数

`random_password`が`apply`時にRDSパスワードを生成し、ECSタスク定義の
環境変数としてそのまま注入している——タスク定義を読める人（例：
`aws ecs describe-task-definition`）やAWSコンソールから見える。より
正しいパターンはECSの`secrets`ブロックでSecrets Manager secretや
SSM `SecureString`パラメータを指し、タスク起動時にECSエージェントが
解決する方式で、定義に焼き込まない。本Phaseではそれをしていない——
実データを持たないデモ用データベースのためにSecrets Managerリソースと
タスク実行ロールへのIAM権限を追加することになり、計画時点で本Phaseを
小さく保つと明示していた。見落としではなく意図的な簡略化として記録
する——このパターンを実際の機密情報を扱う用途に使う場合の、自然な
次の一歩である。

## CloudFormation参照実装

Phase 1・3・4の前例に倣い、`infrastructure/cloudformation/`に同じ5つの
要素（ネットワーク/セキュリティグループ・ECR・RDS・ALB・ECS）を別々の
テンプレートとして用意している——未デプロイ・`cfn-lint`通過済み。
1点補足：参照実装の`rds.yaml`はTerraformでデプロイ済みの`16.15`ではなく
`16.14`を指定している。これは`cfn-lint`が同梱するバージョン一覧に
まだ`16.15`が含まれていないためだけの理由（実際のAWS APIには存在し、
正常に動作することを確認済み）——未デプロイのテンプレートにおける
パッチバージョン1つ分の違いであり、実質的な不整合ではない。

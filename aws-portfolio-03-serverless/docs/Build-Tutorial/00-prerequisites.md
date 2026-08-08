[目次](./README.md) | 次へ: [Part 1 — 全体像](./01-overview.md)

---

# Part 0 — 完全初心者向け準備

**AWSアカウント・IAMユーザー・AWS CLI・Terraformを既に使える人はここを飛ばしてPart 1へ。**

### 0-1. AWSアカウントを作る

1. https://aws.amazon.com/ にアクセスし「無料アカウントを作成」
2. メールアドレス・パスワード・クレジットカード情報を登録する
   （このPhase全体のコストは月$0.00〜$0.01程度。詳細は`docs/Cost-Estimation.md`参照）
3. サインアップ後、AWSマネジメントコンソール（ブラウザの管理画面）にログインできることを確認

> 注意: 最初にログインする「ルートユーザー」は普段使いしない。
> 普段の作業は次のステップで作る「IAMユーザー」で行う（AWSのベストプラクティス）。

### 0-2. 作業用のIAMユーザーを作る

ルートユーザーで毎回作業すると、万一パスワードが漏れたときの被害が大きすぎる。
そのため「自分専用の作業アカウント（IAMユーザー）」を作り、普段はそちらを使う。

1. AWSコンソール上部の検索窓で「IAM」と入力して開く
2. 左メニュー「ユーザー」→「ユーザーを作成」
3. ユーザー名を入力（例: `my-name`）
4. 「AWSマネジメントコンソールへのアクセスを許可する」はチェックしなくてよい
   （コンソールログインではなく、後述のアクセスキーでCLIから操作するため）
5. 「ポリシーを直接アタッチする」→ `AdministratorAccess` を選択
   （学習用の個人環境なので一旦フルアクセスにする。本番運用では最小権限にすべき）
6. ユーザー作成後、そのユーザーの詳細画面 →「セキュリティ認証情報」タブ →
   「アクセスキーを作成」→ ユースケースは「コマンドラインインターフェイス (CLI)」
7. 表示される **アクセスキーID** と **シークレットアクセスキー** を安全な場所に保存
   （シークレットアクセスキーはこの画面でしか表示されない。閉じたら二度と見れない）

### 0-3. AWS CLIをインストールして認証情報を設定する

**Windows:**
```powershell
# https://awscli.amazonaws.com/AWSCLIV2.msi をダウンロードして実行
# インストール後、確認:
aws --version
```

**Mac:**
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
aws --version
```

認証情報を設定する:
```bash
aws configure
```
以下を順に聞かれるので入力:
```
AWS Access Key ID [None]: (0-2で保存したアクセスキーID)
AWS Secret Access Key [None]: (0-2で保存したシークレットキー)
Default region name [None]: ap-northeast-1
Default output format [None]: json
```

確認:
```bash
aws sts get-caller-identity
# 自分のアカウントID・ユーザー名が返ってくればOK
```

### 0-4. Terraformをインストールする

**Windows（推奨: winget）:**
```powershell
winget install Hashicorp.Terraform
```

**Mac（推奨: Homebrew）:**
```bash
brew install terraform
```

確認:
```bash
terraform version
# Terraform v1.x.x のように表示されればOK
```

### 0-5. Node.js / npmをインストールする（フロントエンド用）

https://nodejs.org/ からLTS版（2026年時点で20系または22系）をダウンロードしてインストール。

確認:
```bash
node --version
npm --version
```

### 0-6. Gitの基本（このリポジトリを手元に置く）

```bash
git clone https://github.com/daoxiao0/aws-portfolio.git
cd aws-portfolio
```

> 以降のコマンドはすべて、このリポジトリの `aws-portfolio-03-serverless/` を
> 起点に実行する想定で書いている。

---

[目次](./README.md) | 次へ: [Part 1 — 全体像](./01-overview.md)

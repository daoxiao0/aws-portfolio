# minicheck-proxy

`minicheck.daoxiao.org` → CloudFront → `minicheck.whycreator.workers.dev`
（Cloudflare Workers）へのリバースプロキシ。中国大陸からCloudflareへ直接
アクセスすると不安定になる問題を回避するための、AWSアカウントを経由した迂回路。

設計判断の詳細（なぜCloudFrontか、なぜキャッシュを切るか、Hostヘッダーの扱い、
中国からの疎通保証の限界）は学習ノート側にまとめてある：
`D:\Xiao\knowledge\05-AWS\Portfolio\MiniCheck-CN-Proxy\docs-ja\`

github-oidc と同じく、Phase 01〜06のロードマップには属さない独立スタック。

## デプロイ

```bash
cd infrastructure/minicheck-proxy
terraform init
terraform plan
terraform apply
```

`hosted_zone_id` はPhase 2/3と共通の値（`Z06510601ASWSVLJJY29P`）がデフォルトで
入っているので、通常は変数を指定しなくてよい。

ACM証明書のDNS検証 → CloudFront配布（グローバル伝播）の順で進むため、
`apply` は数分〜30分程度かかることがある。

## 動作確認

```bash
# スタック出力
terraform output

# 疎通確認（このマシンからの結果は中国大陸の経路を代表しない）
curl -sI https://minicheck.daoxiao.org/
```

**中国大陸からの実測を別途行うこと。** `apply` が成功しても
「中国から使える」ことの証明にはならない（詳細: docs-ja/0003）。

## 削除する場合

```bash
terraform destroy
```

このスタックが作成したACM証明書・CloudFront Distribution・Route53レコード
（`minicheck.daoxiao.org` の1件のみ）だけが削除される。`daoxiao.org` の
他のレコード（`gratitude.daoxiao.org` / `journal.daoxiao.org`）には影響しない。

## 前提として未確認のこと

MiniCheckのフロントエンドがAPIを相対パス（`/api/xxx`）で呼んでいるか、
絶対パス（`https://minicheck.whycreator.workers.dev/api/xxx`）で呼んでいるかが
未確認。絶対パスの場合、ブラウザは `minicheck.daoxiao.org` 経由でも結局
Cloudflareに直接リクエストを送ってしまうため、このプロキシを立てても
中国からの到達性は改善しない。

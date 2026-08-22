# ============================================================
# Cognito User Pool
# ユーザー登録・ログインを管理し、認証後にJWT（IDトークン）を発行する
# ============================================================
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  # サインイン方法: メールアドレスをユーザー名として使用
  # 理由: ユーザー名を別途決めさせるより、メール一本化の方がシンプル
  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
    # 理由: 学習用ポートフォリオのため、記号必須までは要求しない
  }

  # -------------------------------------------------------
  # 【設定しない項目】
  # -------------------------------------------------------
  # mfa_configuration: 多要素認証は今回無効（デフォルト "OFF"）
  #   理由: ポートフォリオ規模でMFAは過剰。企業要件が出た場合に有効化。
  #
  # lambda_config（トリガー）: 未設定
  #   理由: サインアップ後処理のカスタマイズは現時点で不要。

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# Cognito User Pool Client
# React SPAがCognitoと通信するためのクライアント設定
# ============================================================
resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.project_name}-spa-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # SPA（ブラウザ上で動くJS）なのでクライアントシークレットは発行しない
  # 理由: シークレットはブラウザに埋め込むと漏洩するため、公開クライアントには使わない
  generate_secret = false

  # ユーザー名/パスワードによる直接認証フローを許可
  # (Amplify/amazon-cognito-identity-js のUSER_SRP_AUTHで使用)
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]
}

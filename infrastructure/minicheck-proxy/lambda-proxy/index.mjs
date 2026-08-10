// MiniCheck CN Proxy — Lambda転送レイヤー
//
// なぜCloudFrontから直接workers.devを叩かないのか：
// CloudFrontのカスタムオリジンとして直接 minicheck.whycreator.workers.dev を
// 指定したところ、Cloudflare側が一貫して502で拒否した（openssl/curlでの手動
// 接続やAWS Lambdaからのfetch()は成功するのに、CloudFrontの源站フェッチャー
// からの接続だけが速攻で拒否される）。切り分けの結果、Cloudflareが
// CloudFrontの出口を狙って拒否している可能性が高いと判断した（詳細:
// docs-ja/0005-CloudFrontの源站フェッチャーがCloudflareに拒否される.md）。
//
// このLambdaはCloudFrontとworkers.devの間に挟まり、実際の発信はLambdaの
// ネットワークから行う（Lambdaからのfetchは動作確認済み）。CloudFront自体は
// 引き続きクライアント向けの窓口（カスタムドメイン・TLS終端・エッジ）として
// 使い続ける。

const ORIGIN = "https://minicheck.whycreator.workers.dev";

// CloudFront経由であることの確認に使う共有シークレット。
// 当初はCloudFront OAC（SigV4署名）でLambda Function URLへのアクセスを
// 制限していたが、POST等body付きリクエストでCloudFrontの署名とLambdaの
// 検証が一致せず「SignatureDoesNotMatch」で失敗する問題が発覚した
// （AWS公式ドキュメントに「Lambda doesn't support unsigned payloads」と
// 明記されている既知の制約）。Function URLをAWS_IAM認証からNONE（公開）に
// 変更し、代わりにこのヘッダーで簡易的な検証を行う（詳細: docs-ja/0006）
const SHARED_SECRET_HEADER = "x-minicheck-proxy-secret";

// クライアント→Lambdaへのリクエストヘッダーのうち、そのままworkers.devへ
// 転送してはいけないもの（Hostを転送すると[[0001]]と同じ問題が起きる。
// その他はLambda/CloudFrontが自動生成するホップバイホップ系）。
// accept-encodingも除外する——ここを転送してしまうと、fetch()が「呼び出し側が
// 圧縮を自前で管理するつもり」と判断して自動デコードをスキップし、
// gzip/br圧縮されたバイト列がそのままarrayBuffer()に返ってくる（実際に
// これが原因でクライアント側が乱码になる事故が起きた。詳細: docs-ja/0005）。
// 除外すればfetch()自身がAccept-Encodingを管理し、レスポンスを正しく
// 自動デコードしてくれる
const EXCLUDED_REQUEST_HEADERS = new Set([
  "host",
  "connection",
  "content-length",
  "x-forwarded-for",
  "x-forwarded-port",
  "x-forwarded-proto",
  "via",
  "accept-encoding",
  SHARED_SECRET_HEADER,
]);

// workers.devからのレスポンスヘッダーのうち、そのままクライアントへ
// 転送してはいけないもの（fetch()が既にデコード済みなのでcontent-encodingを
// 転送すると二重デコード扱いされクライアント側で壊れる。set-cookieは
// 個別処理するため除外）
const EXCLUDED_RESPONSE_HEADERS = new Set([
  "content-encoding",
  "content-length",
  "transfer-encoding",
  "connection",
  "set-cookie",
]);

export const handler = async (event) => {
  const providedSecret = event.headers?.[SHARED_SECRET_HEADER];
  if (providedSecret !== process.env.PROXY_SECRET) {
    return { statusCode: 403, body: "Forbidden" };
  }

  const method = event.requestContext?.http?.method ?? "GET";
  const rawPath = event.rawPath ?? "/";
  const queryString = event.rawQueryString ? `?${event.rawQueryString}` : "";
  const targetUrl = `${ORIGIN}${rawPath}${queryString}`;

  const requestHeaders = {};
  for (const [key, value] of Object.entries(event.headers ?? {})) {
    if (!EXCLUDED_REQUEST_HEADERS.has(key.toLowerCase())) {
      requestHeaders[key] = value;
    }
  }

  let requestBody;
  if (event.body) {
    requestBody = event.isBase64Encoded
      ? Buffer.from(event.body, "base64")
      : event.body;
  }

  const fetchInit = { method, headers: requestHeaders };
  if (!["GET", "HEAD"].includes(method) && requestBody !== undefined) {
    fetchInit.body = requestBody;
  }

  const originResponse = await fetch(targetUrl, fetchInit);

  const responseHeaders = {};
  for (const [key, value] of originResponse.headers.entries()) {
    if (!EXCLUDED_RESPONSE_HEADERS.has(key.toLowerCase())) {
      responseHeaders[key] = value;
    }
  }

  // Set-CookieはHeadersの通常イテレーションではカンマ結合され壊れうるため
  // 専用APIで個別に取り出し、Function URLレスポンスの`cookies`配列に渡す
  const cookies = originResponse.headers.getSetCookie?.() ?? [];

  const bodyBuffer = Buffer.from(await originResponse.arrayBuffer());

  return {
    statusCode: originResponse.status,
    headers: responseHeaders,
    cookies,
    body: bodyBuffer.toString("base64"),
    isBase64Encoded: true,
  };
};

# tanijiri.dev デプロイ手順書

## 0. 全体像と前提
- 配信：Cloudflare Pages。GitHub のリポジトリ（公開）と Git 連携し、`main` に push すると本番に自動でデプロイされる。
- ビルド：なし。`public/` の中身をそのまま配信する（リポジトリ直下は配信しない）。
- ドメイン：`tanijiri.dev`（Cloudflare Registrar）。`www.tanijiri.dev` は `https://tanijiri.dev/` へ 301 で転送する。
- 必要なもの：Cloudflare のアカウント（ドメインと同じ）、GitHub のアカウント。ローカルに必要なのは `git` と `curl` だけ。

## 1. 設定値・シークレット
なし。Git 連携の認可は Cloudflare と GitHub の間で行われ、リポジトリにトークンは置かない。

## 2. 初回セットアップ（Cloudflare のダッシュボード）
画面の名前は変わることがある。見つからないときは Cloudflare のドキュメントで最新の名前を確認する。

1. **Pages のプロジェクトを作る**
   - Workers & Pages → 作成 → Pages → 「Git リポジトリをインポート」（Import an existing Git repository）を選び、GitHub のこのリポジトリを選ぶ。
   - 本番ブランチ：`main`
   - フレームワーク プリセット：なし（None）
   - ビルド コマンド：空欄
   - ビルド出力ディレクトリ：`public`
   - 保存してデプロイすると、`<プロジェクト名>.pages.dev` で見られるようになる。
2. **独自ドメインを割り当てる**
   - Pages のプロジェクト → カスタム ドメイン → `tanijiri.dev` を追加する。ドメインが同じアカウントにあるので、DNS のレコードは自動で作られる。
3. **HTTP を HTTPS に転送する**
   - `tanijiri.dev` のゾーン → SSL/TLS → エッジ証明書 → 「常に HTTPS を使用」（Always Use HTTPS）をオンにする。
4. **www を転送する**
   - DNS に `www` のレコードがなければ、プロキシを有効にした AAAA レコード（名前 `www`、値 `100::`）を追加する（転送のためだけの仮の宛先）。
   - ルール → リダイレクト ルール → テンプレート「WWW からルートにリダイレクト」（Redirect from WWW to root）で作成する。ステータスは 301、クエリ文字列は保持。
5. 下の「4. デプロイ後の動作確認」を実行する。

## 3. デプロイ
```bash
git push origin main   # 本番に自動でデプロイされる
```
- `main` 以外のブランチを push すると、プレビュー用の URL にデプロイされる（本番は変わらない）。
- デプロイの状況は Pages のプロジェクト → デプロイ で見られる。

## 4. デプロイ後の動作確認
```bash
scripts/check.sh   # 本番（https://tanijiri.dev）を確認。すべて OK なら終了コード 0
```
- 仕様書 000〜002 の受け入れ条件のうち、コマンドで確認できるもの（トップが 200、存在しないパスが 404、`public/` の外が見えない、http→https、www→apex、文言、リンク先が 200、色、メタ情報、画像の重さなど）をまとめて確認する。
- 手元で確認するとき：`python3 -m http.server -d public 8000` を起動して `scripts/check.sh http://localhost:8000`（http→https と www は本番でだけ確認する）。
- スクリプトで確認できないもの（スマホ実機での表示、QR からの読み取り、Lighthouse）は、仕様書の検証方法に従って手で確認する。

## 5. 運用メモ

### サイトの中身を書き換える
- 文言・リンク・作っているものは、すべて `public/index.html` にある。書き換えて `main` に push すれば反映される。
- 名刺と共通の文言（氏名・肩書き・一行紹介）は、名刺と揃える（CLAUDE.md）。

### アイコン・favicon を作り直す
元画像（512×512 の PNG）は Git 管理外の `brief/` にある。
```bash
scripts/make-icons.sh                 # brief/ の元画像から public/ の3ファイルを作り直す
scripts/make-icons.sh path/to/new.png # 別の画像から作る
```
- 256×256 の WebP（表示用）、32×32 の PNG（favicon）、180×180 の PNG（iPhone のホーム画面用）を作る。
- `sips` は PNG に EXIF と cHRM のチャンクを付けるので、スクリプトの中で取り除いている（中身は解像度などで個人情報ではないが、不要なため）。
- 必要なもの：`cwebp`（`brew install webp`）。

### メール（`hiroshi@tanijiri.dev`）
- 受信：Cloudflare の Compute > Email Service > Email Routing。ルーティング ルールは `hiroshi@tanijiri.dev` → 本名用 Gmail（メールに送信）、キャッチオールは無効。
- DNS（Email Routing が自動で追加）：MX `route1〜3.mx.cloudflare.net`、SPF `v=spf1 include:_spf.mx.cloudflare.net ~all`、DKIM `cf2024-1._domainkey`。消さない。
- 確認コマンド：`dig +short MX tanijiri.dev`、`dig +short TXT tanijiri.dev`
- 送信：Gmail の「他のアドレスからメールを送信」（Gmail の SMTP）。Google アカウントのパスワードを変えるとアプリパスワードが無効になり、送信できなくなる。そのときはアプリパスワードを作り直して Gmail に入れ直す。
- DMARC レコードは今は置かない。置くなら `p=none` にする（理由は docs/TECH_NOTES.md）。

### ドメイン
- 名刺の QR と NFC の飛び先なので、ドメインが切れるとすべて使えなくなる。Cloudflare Registrar で自動更新がオンになっていること、支払い方法が期限切れでないことを年に1回確認する。

## 6. ロールバック
- **すぐ戻す**：Pages のプロジェクト → デプロイ → 戻したい過去のデプロイ → 「このデプロイにロールバック」。Git の履歴は変わらない。
- **履歴ごと戻す**：`git revert <コミット>` して `main` に push する。
- ロールバック後も `scripts/check.sh` を実行して確認する。

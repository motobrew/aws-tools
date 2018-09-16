### 利用したプログラミング言語名

Python (3.6)

### 利用したデータベース名

Amazon Athena

### 作成したプログラムの実行方法

#### 開発環境
以下の環境で開発と動作確認を行いました。
- MacOS 10.13.4
- docker v18.06.0-ce

#### 必要な環境
1. 東京リージョンのS3バケット
2. 以下の権限を持ったAWSアクセスキーとシークレットキー
  - 1のS3バケットへの書き込み権限（分析対象のアクセスログとクエリの実行結果を保管します）
  - AthenaのCREATE DATABASE/TABLE、ジョブ実行に必要な権限
3. docker
4. makeコマンド

#### 実行方法
1. 以下の環境変数を設定します
  - AWS_ACCESS_KEY_ID
  - AWS_SECRET_ACCESS_KEY
  - S3_BUCKET（Athenaで使うバケット名、事前に作成）

```
# 設定例
export AWS_ACCESS_KEY_ID=AKIAxxxxxxxxxxxxxxxx
export AWS_SECRET_ACCESS_KEY=59wHJTYNouIgxxxxxxxxxxxxxxxxxxxxxxxxxxx
export S3_BUCKET=motobrew-devops-test
```

2. dockerコンテナをビルドします
```
make build
```
logsがカレントディレクトリ以外にある場合は、MakefileのLOGS_DIRにフルパスで指定してください

3. Athenaのセットアップを行います
```
make init
```
logs配下のアクセスログをS3に配置してDATABASE/TABLE/VIEWを作成、パーティションを認識させます。

4. 各uriごとのの日毎のアクセス数を集計します
```
make uri_count
```
SQL: src/queries/uri_count.sql

5. 各日の Top 10 のリクエストタイムをもつログデータ抽出
```
make top10_reqtime
```
SQL: src/queries/top10_reqtime.sql

#### 結果の確認方法
- 上の3~5では以下の３つを標準出力に表示します
  - 実行するDDLやSQL
  - DDL/SQLの実行結果
  - 実行結果のS3パス（Athenaでは結果がS3にCSV形式で置かれます）

### どのような側面について考慮し、または妥協したのか

大きく分けて2つの側面で考慮しました。SQLを実行する技術選定の部分と環境構築をどうするかの部分です。

技術選定の部分では、アクセスログの分析で利用することを想定し、GB単位のログファイルでも問題なくクエリが実行できるようにAthenaかBigQueryでパーティショニングする方法を考えました。ファイルのフォーマットがLTSVのgzipだったので、そのままSQLを実行できる点でメリットが大きいと考えてAthenaを選びました。UIとしては利用頻度が高くなければAWSコンソールでSQLを実行したり、頻度が増えたりエンジニア以外が実行するならRedashを使う想定になります。
LTSVだとAthenaではmap型として１つのカラムに入るようなので、SQLが直感的にわかりにくくなる課題が途中ありました。AWSのコンソールやRedashから直接テーブルに対してSQLを実行する場合に以下のようになります。
```
SELECT
  record['method'] AS method,
  record['level'] AS level,
  record['reqtime'] AS reqtime,
  record['time'] AS time,
  record['id'] AS id,
  record['uri'] AS uri
FROM "motobrew_devops_test"."access_log"
ORDER BY reqtime DESC
limit 10;
```
幸いAthenaでviewが使えるようになっていたので、map型のカラムを展開したviewを作ることで対応しました。ファイル名の日付(YYYYMMDD)をパーティションキーdtとしています。

2つ目の環境構築については、実際の業務のようにヒアリングできない点が難しく感じました。環境構築ではなるべく手間を省きたいと考えつつ、1度しか実行しないかもしれないCREATE DB/TABLEをコード化するとしたら環境構築のために環境構築をするような感じになったり、Ansibleなどの構成管理ツールを使ったら余計に複雑になったりするのではと思い、その辺りのバランスで悩みました。
はじめは環境変数をファイルに書いてそれをスクリプトやMakefile内で読み込んでいましたが、アクセスキーがgitやコンテナに残ってしまうのが良くないと思い修正しました。
最終的にアクセスログのS3への展開を行うシェルスクリプト(copy_logs.sh)と、AthenaのDDL/SQLを実行するPythonスクリプト(execute.py)を1つのコンテナに入れて、それらを実行するdockerコマンドをmakeでまとめる形になりました。

### 実行環境の削除について
1. 以下のコマンドを実行するとAthenaのDATABASEを削除します
```
make clean
```

2. `必要な環境`のところで用意した、アクセスキーとシークレットキー、S3バケットを削除してください

3. Dockerのイメージを手動で削除してください

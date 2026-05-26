# くちとじウォッチ Android MVP

テレビ視聴中に子どもの口が開き始めたことを端末内で検知し、一定時間続いたら音と振動で知らせるAndroid向けMVPです。顔画像や動画は保存せず、クラウド送信もしません。

## できること

- カメラプレビュー
- ML Kit Face Detectionによる顔輪郭検出
- 上唇内側と下唇内側の距離を口幅で割った「口開きスコア」計算
- しきい値とアラートまでの秒数調整
- アラート音、振動、アラート回数表示
- 前面/背面カメラ切り替え

## セットアップ

この作業環境には、プロジェクト内ポータブル環境としてFlutter/JDK/Android SDKを入れています。PowerShellでは先に以下を読み込んでください。

```powershell
powershell -ExecutionPolicy Bypass
. .\tool\android_env.ps1
```

その後、以下を実行できます。

```bash
flutter pub get
dart run flutter_launcher_icons
flutter run
```

## 非公開テストまでの実行順

1. PowerShellで`. .\tool\android_env.ps1`を読み込みます。
2. Androidの権限文言とSDK設定を下記の通り確認します。
3. `dart run flutter_launcher_icons`で`store/icons/app-icon-1024.png`からランチャーアイコンを生成します。
4. `flutter run`で実機確認します。
5. `flutter build appbundle --release`でAABを作り、Play Consoleの内部テストまたはクローズドテストにアップロードします。

ストア提出用の下書きは`store/`に配置しています。

- `store/privacy-policy.html`: 公開URLへアップロードするプライバシーポリシー
- `store/listing-ja.md`: ストア掲載文案
- `store/review-notes-ja.md`: 審査メモ案
- `store/test-plan.md`: 非公開テスト計画
- `store/release-checklist.md`: リリース前チェックリスト
- `store/icons/app-icon-1024.png`: ストア/ランチャー用アイコン原稿
- `store/screenshots/`: スクリーンショットのドラフト画像。最終提出では実機スクリーンショットに差し替えてください。

## Android設定

`android/app/build.gradle`または`android/app/build.gradle.kts`で、CameraX/ML Kit要件に合わせて以下を満たしてください。

```kotlin
android {
    compileSdk = 36

    defaultConfig {
        minSdk = 21
        targetSdk = 35
    }
}
```

CameraXの画像ストリームは`ImageFormatGroup.nv21`を指定しています。

Androidのカメラ権限説明やストア文言では、以下の表現に揃えてください。

```text
カメラは、口の開き具合を端末内で判定するために使用します。録画、保存、クラウド送信、顔認証、個人識別には使用しません。
```

## リリースビルド

Android:

```bash
flutter build appbundle --release
```

出力先:

```text
build/app/outputs/bundle/release/app-release.aab
```

現在の署名設定は以下のローカルファイルを使います。どちらも`.gitignore`済みです。

```text
android/app/upload-keystore.jks
android/key.properties
```

この2つはPlay Consoleにアップロードした後の更新版ビルドでも必要です。必ず安全な場所にバックアップしてください。

## 判定ロジック

```text
口開きスコア = 上唇内側と下唇内側の縦距離 / 口の横幅
```

初期値は以下です。

- しきい値: `0.20`
- アラート開始: `1.5秒`
- 処理間隔: 約`120ms`

テレビ横に置く距離や角度でスコアが変わるため、実機では「口を閉じた状態」と「少し開いた状態」を見ながらしきい値を調整してください。

## 参考にした一次情報

- Flutter camera package: https://pub.dev/packages/camera
- google_mlkit_face_detection: https://pub.dev/packages/google_mlkit_face_detection
- google_mlkit_commons InputImage setup: https://pub.dev/packages/google_mlkit_commons

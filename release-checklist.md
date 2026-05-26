# Androidリリース前チェックリスト

## 共通

- [ ] アプリ名を決定: くちとじウォッチ
- [ ] アイコン生成: `store/icons/app-icon-1024.png`
- [ ] 実機スクリーンショット撮影
- [ ] プライバシーポリシーを公開URLへアップロード
- [ ] 問い合わせメールを実アドレスへ変更
- [ ] アプリ内の情報ダイアログを確認
- [ ] 医療上の診断・治療を示す表現をストア文言から除外
- [ ] 録画しない、保存しない、クラウド送信しない、顔認証しないことを明記

## Android

- [x] Androidプロジェクト雛形を生成
- [x] `android/app/build.gradle.kts`で`minSdk 21`、`targetSdk 35`、`compileSdk 36`を設定
- [x] `android/app/src/main/AndroidManifest.xml`のアプリ名とカメラ権限を設定
- [x] `dart run flutter_launcher_icons`
- [x] `flutter build appbundle --release`
- [x] AAB生成: `build/app/outputs/bundle/release/app-release.aab`
- [ ] Play Consoleで内部テストへアップロード
- [ ] Data safetyを入力
- [ ] Target audience and contentを入力
- [ ] Content ratingを入力
- [ ] `android/app/upload-keystore.jks`と`android/key.properties`を安全な場所へバックアップ

# SilenceCutter

・前提  
win環境(Pwoershell)  
FFmpegのインストールとパス通し  
CUDAが利用可能

・動作  
音声付き動画ファイルの無音区間を除去したファイルを生成、```_silenceCut```というサフィックスを付与して```.\SilenceCut```以下に格納する  
これをスクリプトのあるディレクトリ以下全てのファイルに対して実行する

例)  
```
実行前

test/
├── silenceCutter.ps1
├── aaa.mp4
└── bbb/
    ├── ccc.mp4
    └── ddd/
        └── eee.mp4
```
```
実行後

test/
├── silenceCutter.ps1
├── aaa.mp4
├── bbb/
│   ├── ccc.mp4
│   └── ddd/
│       └── eee.mp4
└── Silencecut/
    ├── aaa_silenceCut.mp4
    └── bbb/
        ├── ccc_silenceCut.mp4
        └── ddd/
            └── eee_silenceCut.mp4
```

現状h264以外には非対応  
全くエラーハンドリングとかしてないのでバグっても泣かないこと
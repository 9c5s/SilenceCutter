### 定数 ###
# 無音の閾値
$SILENCE_THRESHOLD = -50
# 無音の長さ
$SILENCE_DURATION = 0.5

### 設定 ###
# ログレベル
$loglevel = "warning"
# 出力ディレクトリ名
$rootDirName = "SilenceCut"
# 出力ファイルのサフィックス
$suffix = "_silenceCut"


### 関数 ###
# 無音の検出
function DetectSilence {
    param(
        [string]$filePath
    )

    # a:0で判定
    $silenceDetectOutput = ffmpeg -v $loglevel -i $filePath -vn -map 0:a:0 -c:a pcm_s16le -f wav - |
    ffmpeg -hide_banner -i - -af "silencedetect=noise=$($SILENCE_THRESHOLD)dB:d=$($SILENCE_DURATION)" -f null - 2>&1

    # 無音部分の開始と終了時間を抽出
    $silenceRanges = $silenceDetectOutput | Select-String -Pattern "silence_(start|end)" | ForEach-Object {
        if ($_ -match ".*silence_(start|end): (\d+(\.\d+)?).*") {
            $matches[2]
        }
    }

    # 無音区間が存在しない場合
    if ($silenceRanges.Count -eq 0) {
        $mode = 0
        $startTime = 0
        $endTime = 0
    }

    # 無音区間が1つのみの場合
    if ($silenceRanges.Count -eq 2) {
        $mode = 1
        $startTime = [double]$silenceRanges[0]
        $endTime = [double]$silenceRanges[1]
    }

    # 無音区間が2つ以上の場合
    if ($silenceRanges.Count -ge 4) {
        # 先頭の無音の終了時間と最後の無音の開始時間
        $mode = 2
        $startTime = [double]$silenceRanges[1]
        $endTime = [double]$silenceRanges[-1]
    }

    # 無音の開始と終了時間を返す
    return @{
        Mode = $mode;
        Start = $startTime;
        End   = $endTime
    }
}


### メイン処理 ###
$rootDir = ".\" + $rootDirName
Get-ChildItem -Path . -Recurse -File | ForEach-Object {
    $file = $_

    # ファイルの内容チェック(音声付き動画のみ処理)
    $streamInfo = ffmpeg -hide_banner -i $file.FullName -map 0 -c copy 2>&1
    $videoStreams = ($streamInfo | Select-String "Video:").Count
    $audioStreams = ($streamInfo | Select-String "Audio:").Count
    if ($videoStreams -eq 0 -or $audioStreams -eq 0) { return }

    # 出力フォルダ内の処理済ファイルはスキップ
    if ($file.DirectoryName -match $rootDirName) { return }

    # 出力ディレクトリ確認
    $outputDir = $rootDir + $file.DirectoryName -replace [regex]::Escape($PWD), ''
    if (!(Test-Path -Path $outputDir)) {
        # ディレクトリが存在しない場合は作成
        New-Item -Path $outputDir -ItemType Directory
    }

    # 最終出力パス定義
    $outputPath = $outputDir + "\" + $file.BaseName + $suffix + $file.Extension

    # 処理済ファイルが存在する場合はスキップ
    if (Test-Path -Path $outputPath) { return }

    # 一時ファイル定義
    $cutFile = $env:TEMP + "\" + $file.BaseName + "_cut" + $file.Extension
    $segmentFile = $env:TEMP + "\segment_%04d" + $file.Extension
    $segmentZero = $env:TEMP + "\segment_0000" + $file.Extension
    $segmentZeroCut = $env:TEMP + "\segment_0000_cut" + $file.Extension

    # 無音部分の検出
    $silenceInfo = DetectSilence -filePath $file.FullName

    # 無音部分をカットしつつv:0とa:0のみ抽出
    if ($silenceInfo.Mode -eq 0) {
        # カットしない
        ffmpeg -v $loglevel -y -i $file.FullName -map 0:v:0 -map 0:a:0 -c copy $cutFile
    }

    if ($silenceInfo.Mode -eq 1) {
        if ($silenceInfo.Start -eq 0) {
            # 先頭の無音部分をカット
            ffmpeg -v $loglevel -y -ss $silenceInfo.Start -i $file.FullName -map 0:v:0 -map 0:a:0 -c copy -avoid_negative_ts make_zero $cutFile
        }
        if ($silenceInfo.End -eq 0) {
            # ？？？
        }
        # 最後の無音部分をカット
        ffmpeg -v $loglevel -y -i $file.FullName -to $silenceInfo.Start -map 0:v:0 -map 0:a:0 -c copy -avoid_negative_ts make_zero $cutFile
    }

    if ($silenceInfo.Mode -eq 2) {
        # 先頭と最後の無音部分をカット
        ffmpeg -v $loglevel -y -ss $silenceInfo.Start -i $file.FullName -to $silenceInfo.End -map 0:v:0 -map 0:a:0 -c copy -avoid_negative_ts make_zero $cutFile
    }

    # ファイルをセグメント単位で分割
    ffmpeg -v $loglevel -y -i $cutFile -c copy -map 0 -f segment -segment_time 0 -break_non_keyframes 0 $segmentFile

    #先頭セグメント(無音と有音の境界)に対して再度無音検出
    $segmentSilenceInfo = DetectSilence -filePath $segmentZero

    if ($segmentSilenceInfo.Mode -eq 1) {
        # 先頭セグメントの無音部分カット(エンコード)
        ffmpeg -v $loglevel -y -i $segmentZero -ss $segmentSilenceInfo.End -c:v h264_nvenc -preset slow -c:a copy -fps_mode passthrough -avoid_negative_ts make_zero $segmentZeroCut
        # 無音カット前の先頭セグメントを削除
        Remove-Item $segmentZero -Force
    }

    # 結合ファイルのリストを作成
    $fileList = [System.IO.Path]::GetTempFileName()
    Get-ChildItem -Path $env:TEMP -Filter "segment*" -File | ForEach-Object {
        "file '$($_.FullName)'" | Add-Content -Path $fileList
    }

    # ファイルの結合
    ffmpeg -v $loglevel -y -f concat -safe 0 -i $fileList -c copy -reset_timestamps 1 $outputPath

    # 一時ファイル削除
    Remove-Item $cutFile -Force
    Remove-Item $fileList -Force
    Get-ChildItem -Path $env:TEMP -Filter "$($file.BaseName)*" -File | ForEach-Object {
        Remove-Item -Path $_.FullName -Force
    }
    Get-ChildItem -Path $env:TEMP -Filter "segment*" -File | ForEach-Object {
        Remove-Item -Path $_.FullName -Force
    }
}
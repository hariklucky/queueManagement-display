; 安装完成后将配置模板复制到安装目录（安装程序有管理员权限，可写入 Program Files）
; Tauri NSIS 会把 bundle.resources 中的文件直接解压到 $INSTDIR（与 exe 同级）
!macro NSIS_HOOK_POSTINSTALL
  IfFileExists "$INSTDIR\config.json" done 0

  IfFileExists "$INSTDIR\config.example.json" 0 try_resources
    CopyFiles /SILENT "$INSTDIR\config.example.json" "$INSTDIR\config.json"
    Goto done

  try_resources:
  IfFileExists "$INSTDIR\resources\config.example.json" 0 try_up
    CopyFiles /SILENT "$INSTDIR\resources\config.example.json" "$INSTDIR\config.json"
    Goto done

  try_up:
  IfFileExists "$INSTDIR\resources\_up_\config.example.json" 0 done
    CopyFiles /SILENT "$INSTDIR\resources\_up_\config.example.json" "$INSTDIR\config.json"

  done:
!macroend

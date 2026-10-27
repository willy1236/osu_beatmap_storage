; Windows 安裝檔。CI 以 `iscc /DAppVersion=x.y.z installer/setup.iss` 建置，
; 來源是 flutter build windows 的 Release 資料夾。
; 裝在使用者目錄、不需管理員權限：config.json、bin/ 與自動更新都要寫入 exe 所在的資料夾。

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "osu_beatmap_storage"
#define AppExe "osu_beatmap_storage.exe"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
; AppId 決定升級與解除安裝時認得是同一個程式，發佈後不可更改
AppId={{8C00BB22-9985-4B24-A4A4-B90B111005CE}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=willy1236
AppPublisherURL=https://github.com/willy1236/osu_beatmap_storage
PrivilegesRequired=lowest
DefaultDirName={userpf}\{#AppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
; 程式在背景執行時（系統匣）由 Restart Manager 關閉後再覆蓋
CloseApplications=yes
OutputDir=..\build\installer
OutputBaseFilename={#AppName}_setup_v{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; 系統語言是正體中文或英文時直接套用，其餘才跳語言選單
ShowLanguageDialog=auto

[Languages]
Name: "chinesetraditional"; MessagesFile: "compiler:Languages\ChineseTraditional.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; config.json 是執行時產生的使用者設定，不隨安裝檔覆蓋
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Excludes: "config.json"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{userprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; 開機自動啟動的 Run 項目由程式自己寫入，這裡只負責解除安裝時移除
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "{#AppName}"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; danser 下載內容與自動更新殘留；config.json 保留，重裝後登入與路徑設定還在
Type: filesandordirs; Name: "{app}\bin"
Type: filesandordirs; Name: "{app}\.update_backup"
Type: filesandordirs; Name: "{app}\.update_staging"

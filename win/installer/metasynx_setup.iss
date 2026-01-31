; MetaSynx Installer Script
; Inno Setup Script

[Setup]
AppName=MetaSynx
AppVersion=1.0.0
AppPublisher=MetaSynx
AppPublisherURL=https://metasynx.io
AppSupportURL=https://metasynx.io
AppUpdatesURL=https://metasynx.io
DefaultDirName={autopf}\MetaSynx
DefaultGroupName=MetaSynx
OutputDir=C:\Users\Administrator\metaSynx\win\installer_output
OutputBaseFilename=MetaSynx_Setup
SetupIconFile=C:\Users\Administrator\metaSynx\win\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\metasynx.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "C:\Users\Administrator\metaSynx\win\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MetaSynx"; Filename: "{app}\win.exe"; IconFilename: "{app}\data\flutter_assets\assets\app_icon.ico"
Name: "{group}\Uninstall MetaSynx"; Filename: "{uninstallexe}"
Name: "{autodesktop}\MetaSynx"; Filename: "{app}\win.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\win.exe"; Description: "{cm:LaunchProgram,MetaSynx}"; Flags: nowait postinstall skipifsilent

; Instalador de Cabina para Windows (Inno Setup). Se instala para el usuario, sin pedir permisos de administrador.
[Setup]
AppId={{6C1B5D0A-2B0E-4E6B-9B6E-CAB10A000001}
AppName=Cabina
AppVersion=0.1
AppPublisher=Muyuna.org
AppPublisherURL=https://muyuna.org
DefaultDirName={autopf}\Cabina
DefaultGroupName=Cabina
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\salida
OutputBaseFilename=Cabina-Instalador
SetupIconFile=..\Recursos\cabina.ico
UninstallDisplayIcon={app}\Cabina.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "escritorio"; Description: "Crear un acceso directo en el escritorio"

[Files]
Source: "..\salida\Cabina\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Cabina"; Filename: "{app}\Cabina.exe"
Name: "{autodesktop}\Cabina"; Filename: "{app}\Cabina.exe"; Tasks: escritorio

[Run]
Filename: "{app}\Cabina.exe"; Description: "Abrir Cabina"; Flags: nowait postinstall skipifsilent

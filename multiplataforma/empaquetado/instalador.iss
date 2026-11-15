; Instalador de Proyectapp para Windows (Inno Setup). Se instala para el usuario, sin pedir permisos de administrador.
[Setup]
AppId={{2F7C0C52-6E1B-4C0F-9A53-5B0F2D7A91C4}
AppName=Proyectapp
AppVersion=1.0
AppPublisher=Muyuna.org
AppPublisherURL=https://muyuna.org
DefaultDirName={autopf}\Proyectapp
DefaultGroupName=Proyectapp
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\salida
OutputBaseFilename=Proyectapp-Instalador
SetupIconFile=..\Recursos\proyectapp.ico
UninstallDisplayIcon={app}\Proyectapp.exe
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
Source: "..\salida\Proyectapp\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Proyectapp"; Filename: "{app}\Proyectapp.exe"
Name: "{autodesktop}\Proyectapp"; Filename: "{app}\Proyectapp.exe"; Tasks: escritorio

[Run]
Filename: "{app}\Proyectapp.exe"; Description: "Abrir Proyectapp"; Flags: nowait postinstall skipifsilent

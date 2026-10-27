' TrayCal silent launcher - run this script to start TrayCal without a console window
' Content kept ASCII-only: VBS files are parsed as ANSI by WSH
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\TrayCal.ps1""", 0, False

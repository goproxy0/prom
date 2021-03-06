Option Explicit
Dim wsh, fso, link, BtnCode, ScriptDir, FilePaths, i

Set wsh = WScript.CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

Function CreateShortcut(FilePath)
    Set wsh = WScript.CreateObject("WScript.Shell")
    Set link = wsh.CreateShortcut(wsh.SpecialFolders("Startup") + "\prom.lnk")
    link.TargetPath = FilePath
    link.Arguments = ""
    link.WindowStyle = 7
    link.Description = "Prom"
    link.WorkingDirectory = wsh.CurrentDirectory
    link.Save()
End Function

BtnCode = wsh.Popup("是否将 prom.exe 加入到启动项？(本对话框 6 秒后消失)", 6, "Prom 对话框", 1+32)
If BtnCode = 1 Then
    ScriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
    FilePaths = Array(ScriptDir + "\promgui.exe", ScriptDir + "\prom.exe")
    For i = 0 to ubound(FilePaths)
        If Not fso.FileExists(FilePaths(i)) Then
            wsh.Popup "当前目录下不存在 " + FilePaths(i), 5, "Prom 对话框", 16
            WScript.Quit
        End If
    Next
    CreateShortcut(FilePaths(0))
    wsh.Popup "成功加入 Prom 到启动项", 5, "Prom 对话框", 64
End If

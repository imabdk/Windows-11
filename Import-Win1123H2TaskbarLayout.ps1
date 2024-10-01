$taskbarFile = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml"
[xml]$taskbarXml = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />
        <taskbar:DesktopApp DesktopApplicationID="MSEdge"/>
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Office.OUTLOOK.EXE.15" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
 </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
if (-NOT[string]::IsNullOrEmpty($taskbarXml)) {
    $taskbarXml.Save($taskbarFile)
}

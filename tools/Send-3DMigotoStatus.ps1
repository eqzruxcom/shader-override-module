param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [int]$ProcessId = 0,

    [string]$ProcessName = 'ff7remake_'
)

$ErrorActionPreference = 'Stop'
$capacityCharacters = 512
$capacityBytes = $capacityCharacters * 2

if ($Message.Length -ge $capacityCharacters) {
    throw "Status message must be shorter than $capacityCharacters UTF-16 characters."
}

if ($ProcessId -le 0) {
    $processes = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    if ($processes.Count -ne 1) {
        throw "Expected exactly one '$ProcessName' process, found $($processes.Count). Pass -ProcessId explicitly when needed."
    }
    $ProcessId = $processes[0].Id
}

$requestName = "Local\3DMigotoRemoteStatus_$ProcessId"
$ackName = "Local\3DMigotoRemoteStatusAck_$ProcessId"
$mappingName = "Local\3DMigotoRemoteStatusBuffer_$ProcessId"

$request = $null
$ack = $null
$mapping = $null
$view = $null

try {
    $request = [System.Threading.EventWaitHandle]::OpenExisting($requestName)
    $ack = [System.Threading.EventWaitHandle]::OpenExisting($ackName)
    $mapping = [System.IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting(
        $mappingName,
        [System.IO.MemoryMappedFiles.MemoryMappedFileRights]::ReadWrite)
    $view = $mapping.CreateViewAccessor(0, $capacityBytes, [System.IO.MemoryMappedFiles.MemoryMappedFileAccess]::ReadWrite)

    $bytes = [System.Text.Encoding]::Unicode.GetBytes($Message + [char]0)
    $empty = New-Object byte[] $capacityBytes
    $view.WriteArray[byte](0, $empty, 0, $empty.Length)
    $view.WriteArray[byte](0, $bytes, 0, $bytes.Length)
    $view.Flush()

    [void]$ack.Reset()
    [void]$request.Set()
    if (-not $ack.WaitOne(3000)) {
        throw "3Dmigoto did not acknowledge the status message within 3 seconds."
    }

    [pscustomobject]@{
        ProcessId = $ProcessId
        Message = $Message
        Acknowledged = $true
    }
}
finally {
    if ($view) { $view.Dispose() }
    if ($mapping) { $mapping.Dispose() }
    if ($ack) { $ack.Dispose() }
    if ($request) { $request.Dispose() }
}

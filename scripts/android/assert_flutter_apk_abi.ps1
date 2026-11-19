function Assert-FlutterApkAbi {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('armeabi-v7a', 'arm64-v8a', 'x86_64')][string]$Abi
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $apk = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $nativeAbis = @($apk.Entries | Where-Object {
            $_.Name -and $_.FullName -match '^lib/[^/]+/'
        } | ForEach-Object { ($_.FullName -split '/')[1] } | Sort-Object -Unique)
        if ($nativeAbis.Count -ne 1 -or $nativeAbis[0] -cne $Abi) {
            throw "Expected only $Abi native libraries in the APK. Found: $($nativeAbis -join ', ')."
        }

        $machine = @{ 'armeabi-v7a' = 40; 'arm64-v8a' = 183; 'x86_64' = 62 }[$Abi]
        foreach ($library in 'libflutter.so', 'libapp.so') {
            $entry = $apk.GetEntry("lib/$Abi/$library")
            if ($null -eq $entry) { throw "Missing $Abi $library in the APK." }
            $reader = [IO.BinaryReader]::new($entry.Open())
            try {
                $header = $reader.ReadBytes(20)
                if ($header.Length -ne 20 -or [BitConverter]::ToUInt32($header, 0) -ne 0x464c457f -or
                    $header[5] -ne 1 -or [BitConverter]::ToUInt16($header, 18) -ne $machine) {
                    throw "Invalid $Abi ELF header for $library in the APK."
                }
            } finally { $reader.Dispose() }
        }
    } finally { $apk.Dispose() }
}

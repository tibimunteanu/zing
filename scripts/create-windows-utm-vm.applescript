on run argv
    if (count of argv) is less than 1 then
        error "usage: osascript scripts/create-windows-utm-vm.applescript /absolute/path/to/windows-arm64.iso"
    end if

    set isoPath to item 1 of argv
    set isoFile to POSIX file isoPath

    tell application "UTM"
        set existingVMs to virtual machines whose name is "Zing Win32"
        if (count of existingVMs) is greater than 0 then
            return "Zing Win32 already exists"
        end if

        make new virtual machine with properties {backend:qemu, configuration:{name:"Zing Win32", architecture:"aarch64", memory:8192, hypervisor:true, drives:{{removable:true, source:isoFile}, {guest size:131072}}}}
        return "Created Zing Win32"
    end tell
end run

"""
Mock Swift compiler for CapriGramIsland on Windows.

Since Xcode and Swift toolchain aren't available, this script creates stub
binaries that match the expected structure: a framework bundle and a widget
extension. The real compilation happens on macOS; this is for testing the
packaging pipeline and verifying that the integration points are correct.
"""
import os
import shutil
import zipfile
from pathlib import Path

def create_mock_framework(output_dir: Path, name: str = "CapriGramIslandKit"):
    """Creates a mock .framework bundle structure."""
    fw = output_dir / f"{name}.framework"
    fw.mkdir(parents=True, exist_ok=True)
    
    # Main binary (stub)
    binary = fw / name
    binary.write_bytes(b'\xca\xfe\xba\xbe' + b'\x00' * 100)  # Mach-O magic + padding
    
    # Info.plist
    info_plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>{name}</string>
    <key>CFBundleIdentifier</key>
    <string>com.evoidk.caprigram.IslandKit</string>
    <key>CFBundleName</key>
    <string>{name}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>13.1.3</string>
    <key>CFBundleVersion</key>
    <string>3837</string>
    <key>MinimumOSVersion</key>
    <string>16.2</string>
</dict>
</plist>"""
    (fw / "Info.plist").write_text(info_plist, encoding="utf-8")
    
    # Modules (for Swift)
    modules = fw / "Modules"
    modules.mkdir(exist_ok=True)
    (modules / f"{name}.swiftmodule").mkdir(exist_ok=True)
    
    return fw

def create_mock_appex(output_dir: Path, name: str = "CapriGramIsland"):
    """Creates a mock .appex bundle structure."""
    appex = output_dir / f"{name}.appex"
    appex.mkdir(parents=True, exist_ok=True)
    
    # Main binary (stub)
    binary = appex / name
    binary.write_bytes(b'\xca\xfe\xba\xbe' + b'\x00' * 100)
    
    # Info.plist from the widget source
    source_plist = Path(r"C:\Users\Administrator\Desktop\CpriGram\CapriGramIsland\Widget\Info.plist")
    if source_plist.exists():
        shutil.copy2(source_plist, appex / "Info.plist")
    else:
        info_plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>CapriGram</string>
    <key>CFBundleExecutable</key>
    <string>CapriGramIsland</string>
    <key>CFBundleIdentifier</key>
    <string>com.evoidk.caprigram.Island</string>
    <key>CFBundleName</key>
    <string>CapriGramIsland</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>13.1.3</string>
    <key>CFBundleVersion</key>
    <string>3837</string>
    <key>MinimumOSVersion</key>
    <string>16.2</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
    <key>NSSupportsLiveActivities</key>
    <true/>
</dict>
</plist>"""
        (appex / "Info.plist").write_text(info_plist, encoding="utf-8")
    
    return appex

def main():
    # Output directories
    build_dir = Path(r"C:\Users\Administrator\Desktop\CpriGram\CapriGramIsland\build")
    build_dir.mkdir(exist_ok=True)
    
    print("Creating mock framework...")
    fw = create_mock_framework(build_dir)
    print(f"  {fw}")
    
    print("Creating mock widget extension...")
    appex = create_mock_appex(build_dir)
    print(f"  {appex}")
    
    print("\nMock build complete. Products:")
    print(f"  Framework: {fw.relative_to(build_dir.parent)}")
    print(f"  Extension: {appex.relative_to(build_dir.parent)}")
    print("\nNote: These are stub binaries for packaging verification.")
    print("Real compilation requires Xcode on macOS.")

if __name__ == "__main__":
    main()

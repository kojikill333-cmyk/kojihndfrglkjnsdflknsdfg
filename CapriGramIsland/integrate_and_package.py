"""
Embeds CapriGramIsland framework and extension into Swiftgram.app and
repackages it as an IPA.

Steps:
1. Unpack the existing CapriGram.ipa
2. Copy CapriGramIslandKit.framework into Swiftgram.app/Frameworks/
3. Copy CapriGramIsland.appex into Swiftgram.app/PlugIns/
4. Update Info.plist with island-specific keys
5. Repackage as CapriGram-Island.ipa
"""
import os
import shutil
import zipfile
import plistlib
from pathlib import Path

def extract_ipa(ipa_path: Path, extract_to: Path) -> Path:
    """Extracts IPA to a directory and returns the Payload path."""
    print(f"Extracting {ipa_path.name}...")
    extract_to.mkdir(parents=True, exist_ok=True)
    
    with zipfile.ZipFile(ipa_path, 'r') as z:
        z.extractall(extract_to)
    
    payload = extract_to / "Payload"
    if not payload.exists():
        raise FileNotFoundError("Payload directory not found in IPA")
    
    return payload

def update_info_plist(app_bundle: Path):
    """Updates Swiftgram.app/Info.plist with island configuration."""
    plist_path = app_bundle / "Info.plist"
    print(f"Updating {plist_path.name}...")
    
    with open(plist_path, 'rb') as f:
        info = plistlib.load(f)
    
    # NSSupportsLiveActivities
    info["NSSupportsLiveActivities"] = True
    info["NSSupportsLiveActivitiesFrequentUpdates"] = True
    
    # BGTaskSchedulerPermittedIdentifiers
    if "BGTaskSchedulerPermittedIdentifiers" not in info:
        info["BGTaskSchedulerPermittedIdentifiers"] = []
    if "com.evoidk.caprigram.island" not in info["BGTaskSchedulerPermittedIdentifiers"]:
        info["BGTaskSchedulerPermittedIdentifiers"].append("com.evoidk.caprigram.island")
    
    # App Groups (if not already present)
    # Note: This is declarative; actual entitlement must be set in the provisioning profile
    
    # Write back
    with open(plist_path, 'wb') as f:
        plistlib.dump(info, f)
    
    print("  ✓ Added NSSupportsLiveActivities")
    print("  ✓ Added BGTaskSchedulerPermittedIdentifiers")

def embed_island(payload: Path, framework_path: Path, appex_path: Path):
    """Embeds framework and extension into the app bundle."""
    app_bundle = payload / "Swiftgram.app"
    if not app_bundle.exists():
        raise FileNotFoundError(f"App bundle not found: {app_bundle}")
    
    # Frameworks
    frameworks_dir = app_bundle / "Frameworks"
    frameworks_dir.mkdir(exist_ok=True)
    
    fw_dest = frameworks_dir / framework_path.name
    if fw_dest.exists():
        shutil.rmtree(fw_dest)
    print(f"Copying {framework_path.name} -> Frameworks/")
    shutil.copytree(framework_path, fw_dest)
    
    # PlugIns
    plugins_dir = app_bundle / "PlugIns"
    plugins_dir.mkdir(exist_ok=True)
    
    appex_dest = plugins_dir / appex_path.name
    if appex_dest.exists():
        shutil.rmtree(appex_dest)
    print(f"Copying {appex_path.name} -> PlugIns/")
    shutil.copytree(appex_path, appex_dest)
    
    # Update Info.plist
    update_info_plist(app_bundle)

def create_ipa(payload_dir: Path, output_ipa: Path):
    """Packages Payload directory back into an IPA."""
    print(f"\nCreating {output_ipa.name}...")
    
    with zipfile.ZipFile(output_ipa, 'w', zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(payload_dir.parent):
            for file in files:
                file_path = Path(root) / file
                arcname = file_path.relative_to(payload_dir.parent)
                z.write(file_path, arcname)
    
    size_mb = output_ipa.stat().st_size / (1024 * 1024)
    print(f"  [+] {output_ipa.name} ({size_mb:.1f} MB)")

def main():
    base = Path(r"C:\Users\Administrator\Desktop\CpriGram")
    
    # Inputs
    original_ipa = base / "CapriGram.ipa"
    framework = base / "CapriGramIsland" / "build" / "CapriGramIslandKit.framework"
    appex = base / "CapriGramIsland" / "build" / "CapriGramIsland.appex"
    
    # Working directory
    work_dir = base / "build"
    work_dir.mkdir(exist_ok=True)
    
    # Output
    output_ipa = base / "CapriGram-Island.ipa"
    
    # Validate inputs
    if not original_ipa.exists():
        raise FileNotFoundError(f"Original IPA not found: {original_ipa}")
    if not framework.exists():
        raise FileNotFoundError(f"Framework not found: {framework}. Run mock_build.py first.")
    if not appex.exists():
        raise FileNotFoundError(f"Extension not found: {appex}. Run mock_build.py first.")
    
    # Clean previous build
    if work_dir.exists():
        for item in work_dir.iterdir():
            if item.is_dir():
                shutil.rmtree(item)
            else:
                item.unlink()
    
    # Extract
    payload = extract_ipa(original_ipa, work_dir)
    
    # Embed
    embed_island(payload, framework, appex)
    
    # Repackage
    create_ipa(payload, output_ipa)
    
    print("\n[SUCCESS] Island integration complete!")
    print(f"   Output: {output_ipa.relative_to(base.parent)}")
    print("\nNote: This IPA contains mock binaries for testing packaging.")
    print("For a working build, compile CapriGramIsland on macOS with Xcode.")

if __name__ == "__main__":
    main()

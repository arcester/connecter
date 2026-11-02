#!/bin/zsh
# Builds a Mac App Store .pkg ready for Transporter, without Xcode's export.
#
# Why: Xcode's export writes the designated requirement with the certificate
# name "José Guzmán Arce Sáez" in decomposed Unicode, which no longer matches
# the certificate and App Store Connect rejects the upload (ITMS-90238).
# Here the app is re-signed with a requirement based on the Team ID instead.
# The App Store re-signs the app with Apple's certificate, so users never
# see this requirement.
#
# Needs in the login keychain: "Apple Distribution" and
# "3rd Party Mac Developer Installer" (Xcode → Settings → Accounts →
# Manage Certificates), and Xcode's "Mac Team Store Provisioning Profile"
# listing that distribution certificate (an export with
# -allowProvisioningUpdates regenerates it).
#
# Usage: tools/release/app-store-pkg.sh <output dir>
set -euo pipefail

TEAM=4XDZ484XHZ
BUNDLE_ID=es.guzman.connecter
OUT=${1:?usage: $0 <output dir>}
ROOT=${0:A:h:h:h}
WORK=$OUT/work
mkdir -p $OUT && rm -rf $WORK && mkdir $WORK

xcodebuild -project $ROOT/connecter.xcodeproj -scheme connecter -configuration Release \
    -derivedDataPath $WORK/dd -archivePath $WORK/Connecter.xcarchive \
    -destination generic/platform=macOS -allowProvisioningUpdates -quiet archive
APP=$WORK/Connecter.app
ditto $WORK/Connecter.xcarchive/Products/Applications/Connecter.app $APP

# Newest Xcode-managed App Store profile for the bundle ID.
PROFILE=""
for f in ${(f)"$(ls -t ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.provisionprofile)"}; do
    security cms -D -i $f > $WORK/profile.plist 2>/dev/null || continue
    if grep -q "<string>Mac Team Store Provisioning Profile: $BUNDLE_ID</string>" $WORK/profile.plist; then
        PROFILE=$f; break
    fi
done
[[ -n $PROFILE ]] || { echo "No App Store profile for $BUNDLE_ID" >&2; exit 1; }
cp $PROFILE $APP/Contents/embedded.provisionprofile

ENT=$WORK/entitlements.plist
cp $ROOT/connecter/connecter.entitlements $ENT
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM.$BUNDLE_ID" \
    -c "Add :com.apple.developer.team-identifier string $TEAM" $ENT

codesign --force --sign "Apple Distribution: " --options runtime --entitlements $ENT \
    --requirements "=designated => anchor apple generic and identifier \"$BUNDLE_ID\" and certificate leaf[subject.OU] = \"$TEAM\"" \
    $APP
codesign --verify --deep --strict $APP
codesign -d --entitlements - $APP 2>&1 | grep -q get-task-allow && { echo "get-task-allow present" >&2; exit 1; }

VERSION=$(plutil -extract CFBundleVersion raw $APP/Contents/Info.plist)
PKG=$OUT/Connecter-$VERSION.pkg
productbuild --component $APP /Applications --sign "3rd Party Mac Developer Installer: " $PKG
pkgutil --check-signature $PKG | head -3
echo "Ready for Transporter: $PKG"

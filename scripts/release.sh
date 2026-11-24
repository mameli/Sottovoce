#!/bin/bash
# Builds Sottovoce in Release, signs it with the "Developer ID Application" certificate, has Apple
# notarize it (notarytool profile "sottovoce", or $SOTTOVOCE_NOTARY_PROFILE), staples the ticket,
# packs it into a disk image, signs and notarizes that too, publishes a GitHub Release tagged
# v<MARKETING_VERSION> (from Config/Base.xcconfig), and updates the Homebrew cask in the tap
# (../homebrew-sottovoce or $SOTTOVOCE_TAP).
#
#   scripts/release.sh            build, sign, notarize, pack, then ask before publishing
#   scripts/release.sh --dry-run  build, sign, notarize and pack only
#
# Once per Mac:
#   - Developer ID Application certificate in the keychain
#   - xcrun notarytool store-credentials sottovoce --apple-id <Apple ID> --team-id <Team ID>
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/^MARKETING_VERSION = //p' Config/Base.xcconfig)
tag="v$version"
app=build/release/DerivedData/Build/Products/Release/Sottovoce.app
zip=build/release/Sottovoce.zip
dmg="build/release/Sottovoce-$version.dmg"
latest=build/release/Sottovoce.dmg
built=build/release/commit
tap=${SOTTOVOCE_TAP:-../homebrew-sottovoce}
cask="$tap/Casks/sottovoce.rb"
identity="Developer ID Application"
notary=${SOTTOVOCE_NOTARY_PROFILE:-sottovoce}

if [[ -n $(git status --porcelain) ]]; then
    echo "Commit or stash your changes first: the Release must match a commit." >&2
    exit 1
fi
if gh release view "$tag" >/dev/null 2>&1; then
    echo "Release $tag already exists: raise MARKETING_VERSION in Config/Base.xcconfig." >&2
    exit 1
fi
released=$(sed -n "s/^## $version (\(....-..-..\))\$/\1/p" CHANGELOG.md)
if [[ -z $released ]]; then
    echo "CHANGELOG.md has no \"## $version (YYYY-MM-DD)\" section." >&2
    exit 1
fi
changes=$(awk -v head="## $version (" 'index($0, head) == 1 { on = 1; next } /^## / { on = 0 } on' CHANGELOG.md \
    | perl -0777 -pe 's/^\s+|\s+$//g')

if [[ ${1:-} != --dry-run && -f $built && $(cat "$built") == $(git rev-parse HEAD) && -f $dmg && -f $latest ]]; then
    xcrun stapler validate -q "$dmg" || { echo "$dmg has no notarization ticket: delete build/release and run again." >&2; exit 1; }
    echo "Reusing $dmg: built and notarized from this commit by the dry-run."
else
    team=$(security find-certificate -c "$identity" -p 2>/dev/null | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
        | sed -n 's/^ *organizationalUnitName *= *//p')
    if [[ -z $team ]]; then
        echo "No \"$identity\" certificate in the keychain." >&2
        exit 1
    fi
    if ! xcrun notarytool history --keychain-profile "$notary" >/dev/null 2>&1; then
        echo "No notarytool profile \"$notary\": run xcrun notarytool store-credentials $notary --apple-id <Apple ID> --team-id $team" >&2
        exit 1
    fi

    rm -rf build/release
    xcodebuild -project Sottovoce.xcodeproj -scheme Sottovoce -configuration Release \
        -derivedDataPath build/release/DerivedData \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp \
        clean build | grep -E "error: |BUILD"

    codesign --verify --strict --deep "$app"
    [[ $(codesign -dvv "$app" 2>&1) == *"Authority=$identity"* ]] || { echo "Not signed with $identity." >&2; exit 1; }

    notarize() {
        xcrun notarytool submit "$1" --keychain-profile "$notary" --wait --output-format json > build/release/notary.json || true
        if [[ $(plutil -extract status raw -o - build/release/notary.json 2>/dev/null) != Accepted ]]; then
            cat build/release/notary.json >&2
            id=$(plutil -extract id raw -o - build/release/notary.json 2>/dev/null)
            [[ -n $id ]] && xcrun notarytool log "$id" --keychain-profile "$notary" >&2
            echo "Notarization of $1 failed." >&2
            exit 1
        fi
    }

    ditto -c -k --keepParent "$app" "$zip"
    notarize "$zip"
    rm "$zip"
    xcrun stapler staple -q "$app"
    spctl --assess --type execute "$app" || { echo "Gatekeeper refuses the notarized app." >&2; exit 1; }

    staging=$(mktemp -d)
    trap 'rm -rf "$staging"' EXIT
    cp -R "$app" "$staging/"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "Sottovoce $version" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
    codesign --sign "$identity" --timestamp "$dmg"
    notarize "$dmg"
    xcrun stapler staple -q "$dmg"
    spctl --assess --type open --context context:primary-signature "$dmg" || { echo "Gatekeeper refuses the disk image." >&2; exit 1; }
    cp "$dmg" "$latest"
    git rev-parse HEAD > "$built"
    echo "Ready: $dmg (notarized)"
fi

[[ ${1:-} == --dry-run ]] && exit 0
read -r -p "Publish $tag on GitHub? [y/N] " answer
[[ $answer == y ]] || exit 0

gh release create "$tag" "$dmg" "$latest" --target main --title "Sottovoce $version" --notes-file - <<NOTES
### What's new

$changes

Apple Silicon Mac, macOS 15 or later (macOS 26+ for on-device Translation).
NOTES

if [[ -f $cask && -z $(git -C "$tap" status --porcelain) ]]; then
    sha=$(shasum -a 256 "$dmg" | cut -d ' ' -f 1)
    git -C "$tap" pull --ff-only -q
    sed -i '' -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$cask"
    git -C "$tap" commit -q -am "Sottovoce $version"
    git -C "$tap" -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -q origin main
    echo "Homebrew cask updated to $version."
else
    echo "Skipping Homebrew tap update (set SOTTOVOCE_TAP to a clean tap clone with Casks/sottovoce.rb)."
fi

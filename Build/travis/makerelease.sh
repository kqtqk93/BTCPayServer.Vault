#!/bin/bash
set -e
[ -x "$(command -v jq)" ] || apt-get intall jq
if ! [[ "$AZURE_STORAGE_CONNECTION_STRING" ]] || ! [[ "$AZURE_STORAGE_CONTAINER" ]]; then
    echo "Skipping github release (AZURE_STORAGE_CONNECTION_STRING or AZURE_STORAGE_CONTAINER not set)"
    exit 0
fi

if ! [[ "$GITHUB_TOKEN" ]]; then
    echo "Skipping github release (GITHUB_TOKEN is not set)"
    exit 0
fi

if ! [[ "$TRAVIS_TAG" ]]; then
    echo "Skipping github release (TRAVIS_TAG is not set)"
    exit 0
fi

AZURE_ACCOUNT_NAME="$(echo "$AZURE_STORAGE_CONNECTION_STRING" | cut -d'=' -f3 | cut -d';' -f1)"
DIRECTORY_NAME="dist-$TRAVIS_BUILD_ID"
wget -O azcopy.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy.tar.gz --strip-components=1
mkdir -p dist
# Our container is public, so the SAS token should not be needed
# But AzCopy is broken https://github.com/Azure/azure-storage-azcopy/issues/971
./azcopy cp "https://$AZURE_ACCOUNT_NAME.blob.core.windows.net/$AZURE_STORAGE_CONTAINER/$DIRECTORY_NAME/*?sv=2019-02-02&ss=b&srt=co&sp=rl&se=2100-04-21T15:00:00Z&st=2020-04-21T19:07:13Z&spr=https&sig=5hMGP4ZR3MUVVp4AVxFDS%2BuFY%2FsU4M8%2B2wKOr8utpWI%3D" \
            "dist"

release="$(cat Build/RELEASE.md)"
version="$(echo "$TRAVIS_TAG" | cut -d'/' -f2)"
payload="$(jq -M --arg "tag_name" "$TRAVIS_TAG" \
   --arg "name" "BTCPayServer Vault $version" \
   --arg "body" "$release" \
   --argjson "draft" false \
   --argjson "prerelease" true \
   '. | .tag_name=$tag_name | .name=$name | .body=$body | .draft=$draft | .prerelease=$prerelease' \
   <<<'{}')"
echo "Creating release to https://api.github.com/repos/$TRAVIS_REPO_SLUG/releases"
echo "$payload"
response="$(curl --fail -s -S -X POST https://api.github.com/repos/$TRAVIS_REPO_SLUG/releases \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload")"
release_id="$(echo $response | jq ".id")"

cd dist
for f in *; do
  [[ $f == *.deb ]] && media_type="application/x-debian-package"
  [[ $f == *.dmg ]] && media_type="application/x-apple-diskimage"
  [[ $f == *.exe ]] && media_type="application/x-msdos-program"
  [[ $f == *.tar.gz ]] && media_type="application/x-tar"
  [[ $f == *.asc ]] && media_type="text/plain"
  if ! [[ "$media_type" ]]; then
    echo "Unable to guess media type for file $f"
    exit 1
  fi
  echo "Uploading $f to github release"
  curl --fail -s -S \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: $media_type" \
    --data-binary @"$f" \
    "https://uploads.github.com/repos/$TRAVIS_REPO_SLUG/releases/$release_id/assets?name=$f"
done

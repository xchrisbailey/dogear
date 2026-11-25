#!/bin/sh
# Xcode Cloud runs this after cloning. The Xcode project is generated from project.yml and
# isn't committed, so generate it before Xcode Cloud resolves packages and archives.
set -eu
cd "$CI_PRIMARY_REPOSITORY_PATH"
brew install xcodegen
xcodegen generate

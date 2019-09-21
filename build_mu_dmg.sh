#!/bin/sh

# TODO: share with .travis and build_python.sh
PYVER=python3.7
PATCH=3.7.4
MACVER=10.9
PYBUNDLE=python-$PATCH-osx-$MACVER.zip

# Setup mu-bundle directory with the portable python, the dmg builder and Mu
[ -d mu-bundle ] && rm -r mu-bundle
cd mu-bundle
git clone https://github.com/mu-editor/mu.git
git clone https://github.com/andreyvit/yoursway-create-dmg.git
unzip -q ../upload/PYBUNDLE

# Install Mu from master branch
python-portable/bin/$PYVER -m pip install ./mu

# Strip the pycache files created when installing mu
find python-portable -name "__pycache__" | xargs rm -r

# Process Python build with Mu and create an App Bundle to upload
python ../create_app_bundle.py "python-portable" "Mu"
mv "mu-portable.zip" "../upload/mu-portable.zip"
#curl --upload-file ./upload/Mu-portable.zip https://transfer.sh/Mu-portable.zip | tee -a output_urls.txt && echo "" >> output_urls.txt

# Create Mu DMG package
# TODO: Create background and add it with "--background "installer_background.png""
yoursway-create-dmg/create-dmg \
    --volname "Mu Installer" \
    --volicon "../app_bundle/appIcon.icns" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon Application.app 200 190 \
    --hide-extension Mu.app \
    --app-drop-link 600 185 \
    "../upload/Mu-Installer.dmg" \
    "Mu.app/"

#curl --upload-file ../upload/Mu-Installer.dmg https://transfer.sh/Mu-Installer.dmg | tee -a output_urls.txt && echo "" >> output_urls.txt

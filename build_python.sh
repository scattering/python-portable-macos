#!/bin/sh

# Generates a relocatable Python.framework in python-embed.  This can be
# used as the basis of a shipping application.  Just need to put the framework
# in your app then pip install your packages.
#
# You should probably strip the cached pyc files before shipping to make
# the app smaller, and because they have the path for the build embedded
# within them:
#
#    find Python.framework -name __pycache__ | xargs rm -r
#
# Unfortunately, this will increase startup time on first launch.
#

# TODO: need update scripts to use relocatable python
# Executable scripts in Python.framework/.../bin such as pip3.7 need to use
# relative paths to find the interpreter otherwise the framework is not
# relocatable.  Doing this in such a way that it allows symbolic links as
# well as unicode or spaces in the linked name is complicated.
#
# Need to change:
#
#    #!/path/to/python
#
# into:
#
#    #!/bin/sh
#    "exec" "$PYTHON" "$0" "$@"
#
# This will work because the shell parser sees the second line as:
#
#    exec /path/to/python scriptname scriptargs...
#
# whie python sees it as a single comment (the python interpreter joins
# consecutive strings into one string).
#
# The path to the python interpreter, $PYTHON, is found using shell tricks:
#
#    # $0 is the name use to invoke the script
#    SCRIPT="$0"
#    # If it is a link, we can use "readlink $SCRIPT" to resolve the link.
#    # This raises an error if it is not a link, so on error just echo the
#    # the script name.
#    REAL_SCRIPT="$(readlink "$SCRIPT" || echo "$SCRIPT")"
#    # We need the directory name not the filename for the script
#    APP_DIR="$(dirname "$REAL_SCRIPT")"
#    # ... and in particular, we need its parent ...
#    APP_ROOT="$(cd "$APP_DIR/.."; pwd -P)"
#    # ... because the path to python is relative to the parent directory.
#    PYTHON="$APP_ROOT/Resources/Python.app/Contents/MacOS/Python"
#
# Expanding, the full shebang is:
#
#    #!/bin/sh
#    "exec" """$(cd "$(dirname "$(readlink "$0" || echo "$0")")/.."; pwd -P)/Resources/Python.app/Contents/MacOS/Python""" "$0" "$@"
#
# The triple-double-quote is treated like a single quote in sh and like a
# multi-line string in python; this lets us have embedded quotes in the
# expression and be compatible with both the shell parser and the python parser.

# Details about building the relocatable python framework were cribbed from
# the following package:
#
#    https://github.com/Sigil-Ebook/Sigil
#
# in the file: docs/Building_A_Relocatable_Python_3.7_Framework_on_MacOSX.txt
# Sigil is released under the GPLv3 license.

# TODO: A number of the tests are failing in the python framework build.
# Need to sort out the failed tests before promising a complete python.

# Aim for the OS 10.9 and above
MACOSX_DEPLOYMENT_TARGET=10.9
export MACOSX_DEPLOYMENT_TARGET

# Full python needs openssl, xz, gdbm and maybe pkg-config
# osaudiodev and spwd not built (these are unix packages, not for mac?)
OPENSSL_VERSION="1.1.1d"
XZ_VERSION="5.2.4"
PYTHON_VERSION="3.7.4"
MAJOR_MINOR="3.7"


# Note: To upgrade to newer release of openssl or python you need to
# change the version numbers in the line below to the updated version
# number.  You also need to generate the sha256 files so that you can
# perform the checksum on the build:
#
#    shasum -a 256 openssl-$SSL_VERSION.tar.gz > openssl.sha256
#    shasum -a 256 Python-$PYTHON_VERSION.tgz > python.sha256
#    shasum -a 256 xz-$XZ_VERSION.tgz > xz.sha256
#
# Be sure to check these updated files into the repo.
#
# You need to verify that you have the correct file before generating
# the new SHA256.  You can do this by comparing the following to the
# values given on the respective websites:
#
#    shasum -a 1 opensll-$SSL_VERSION.tar.gz
#    md5 Python-$PYTHON_VERSION.tgz
#    ?? xz PGP signature check?
#
# There is some insecurity in this method. OpenSSL provides
# SHA1, SHA256 and PGP signatures and python.org provides MD5 and GPG
# signatures on their web pages. However, if the site is hacked then the
# compromised signatures can be uploaded with the compromised source.
# In theory, PGP/GPG is more secure since it requires a private key to sign.
# However the corresponding public keys comes from the same site as the
# downloaded file, so a compromised public key could be uploaded and
# there is no benefit.  Although SHA1 and MD5 are not secure (a MITM could
# substitute a new file for the old while keeping the same signature),
# that same MITM could more easily substitute both the file and the signature,
# so SHA256 offers no more protection.

alias large_echo='{ set +x; } 2> /dev/null; f(){ echo "#\n#\n# $1\n#\n#"; set -x; }; f'
CURRENT_DIR="$PWD"

OPENSSL_SOURCE=openssl-$OPENSSL_VERSION
OPENSSL_BUNDLE=openssl-$OPENSSL_VERSION.tar.gz
OPENSSL_URL=https://www.openssl.org/source/$OPENSSL_BUNDLE
OPENSSL_INSTALL_PREFIX="$CURRENT_DIR/ssl"

XZ_SOURCE=xz-$XZ_VERSION
XZ_BUNDLE=xz-$XZ_VERSION.tar.gz
XZ_URL=https://tukaani.org/xz/$XZ_BUNDLE
XZ_INSTALL_PREFIX="$CURRENT_DIR/ssl"

PYTHON_SOURCE=Python-$PYTHON_VERSION
PYTHON_BUNDLE=Python-$PYTHON_VERSION.tgz
PYTHON_URL=https://www.python,org/ftp.python/$PYTHON_VERSION/$PYTHON_BUNDLE
PYTHON_INSTALL_PREFIX="$CURRENT_DIR/python-portable"

echo $CURRENT_DIR

# For framework builds, need to make sure that we don't tromp on an existing
# python installation.  Test this *before* doing any real work.
if true; then
    IDLE_INSTALL="/Applications/Python $MAJOR_MINOR.app"
    IDLE_TARGET="$PYTHON_INSTALL_PREFIX/Python $MAJOR_MINOR.app"
    if test -d "$IDLE_INSTALL"; then
        # python framework installer dumps idle into /Applications/Python 3.x
        echo "'$IDLE_INSTALL' is not empty; can't build without replacing it"
        exit 1
    fi
fi

if [ ! -f $OPENSSL_BUNDLE ]; then
    large_echo "Download and uncompress openssl $OPENSSL_VERSION source"
    curl -O $OPENSSL_URL
    shasum -a 1 -c openssl.sha256
fi
if [ ! -d $OPENSSL_SOURCE ]; then
    tar -zxvf $OPENSSL_BUNDLE &> /dev/null
fi

if [ ! -f $XZ_BUNDLE ]; then
    large_echo "Download and uncompress xz $XZ_VERSION source"
    curl -L $XZ_URL -o $XZ_BUNDLE
    shasum -a 1 -c xz.sha256
fi
if [ ! -d $XZ_SOURCE ]; then
    tar -zxvf $XZ_BUNDLE &> /dev/null
    # Note: for 10.12, Sigil needed to patch xz so that configure does
    # not search for "futimens".  This wasn't a problem on my box, but
    # maybe I have a newer target architecture.
fi

if [ ! -f $PYTHON_BUNDLE ]; then
    large_echo "Download and uncompress Python $PYTHON_VERSION source"
    curl -OPENSSL_BUNDLE $PYTHON_URL
    shasum -a 1 -c python.sha256
fi
if [ ! -d $PYTHON_SOURCE ]; then
    tar -zxvf $PYTHON_BUNDLE &> /dev/null
fi

if true; then
    large_echo "Build openssl $OPENSSL_VERSION"
    cd "$CURRENT_DIR/$OPENSSL_SOURCE"
    mkdir build
    ./config no-shared --prefix="$OPENSSL_INSTALL_PREFIX"
    # Note: restrict install to software, certificates or docs using one of:
    #    install_sw install_ssldirs install_docs
    # Can also use "make install" to install everything.
    make install_sw
fi

if true; then
    large_echo "Build xz $XZ_VERSION"
    cd "$CURRENT_DIR/$XZ_SOURCE"
    mkdir build
    ./configure --disable-shared --prefix="$XZ_INSTALL_PREFIX"
    make install
fi

large_echo "Build python $PYTHON_VERSION"
cd "$CURRENT_DIR/$PYTHON_SOURCE"
if false; then
    ./configure \
        --prefix="$PYTHON_INSTALL_PREFIX"  \
        --with-openssl="$OPENSSL_INSTALL_PREFIX" \
        --enable-optimizations
    make altinstall
    # TODO: strip __pycache__ and tests as we do in the framework build
else
    ./configure \
        --prefix="$PYTHON_INSTALL_PREFIX" \
        --with-openssl="$OPENSSL_INSTALL_PREFIX" \
        --enable-framework="$PYTHON_INSTALL_PREFIX" \
        --enable-optimizations
    # Note: make altinstall without make does not run the python tests.  This
    # may be a good thing because they can take awhile, and because some of
    # them test network access.
    #make -j4
    make altinstall

    # Move the Python "app" (idle) from /Applications to python-embed
    # TODO: attach the framework to the idle app.
    [ -d "$IDLE_TARGET" ] && rm -r "$IDLE_TARGET"
    mv "$IDLE_INSTALL" "$IDLE_TARGET"

    # Now a complete Python.framework has been built in ${PYTHON_INSTALL_PREFIX}
    # But we still need to make it a relocatable framework

    # To make it relocatable we need to use otool and install_name_tool to change
    # the dylib name and path to it from all executables in the Python.framework

    # A Quick Guide: On Mac OS X, one may use:
    #     "otool -D <file>" to view the install name of a dylib
    #     "otool -L <file>" to view the dependencies
    #     "otool -l <file> | grep LC_RPATH -A2" to view the RPATHs
    #     "install_name_tool -id ..." to change an install name
    #     "install_name_tool -change ..." to change the dependencies
    #     "install_name_tool -rpath ... -add_rpath ... -delete_rpath ..." to change RPATHs

    # Make the framework's main dylib relocatable using rpath

    LINK="$PYTHON_INSTALL_PREFIX/Python.framework/Versions/$MAJOR_MINOR"
    PYVER=python$MAJOR_MINOR
    cd "$LINK"
    chmod u+w Python
    otool -D ./Python
    install_name_tool -id @rpath/Python ./Python
    chmod u-w Python
    otool -D ./Python

    # Change the dependencies of the executable files in bin to point to the relocatable
    # framework in a relative way and add the proper rpath to find the Python (renamed dylib)

    cd bin
    install_name_tool -change $LINK/Python @rpath/Python ./$PYVER
    install_name_tool -change $LINK/Python @rpath/Python ./${PYVER}m
    install_name_tool -add_rpath @executable_path/../ ./$PYVER
    # so that python3 can find the Qt Frameworks and proper plugins for PyQt5
    install_name_tool -add_rpath @executable_path/../../../../ ./$PYVER

    # now do the same for the Python.app stored inside the Python.framework Resources
    # This app is needed to allow gui use by python for plugins

    cd $LINK/Resources/Python.app/Contents/MacOS
    install_name_tool -change $LINK/Python @rpath/Python ./Python
    install_name_tool -add_rpath @executable_path/../../../../ ./Python

    # Correct symlinks in the python-portable/bin directory
    # TODO: make relative shebang in the Python.framework/.../bin directory
    RELBIN="../Python.framework/Versions/$MAJOR_MINOR/bin"
    cd "$PYTHON_INSTALL_PREFIX/bin"
    for f in *; do ln -sfn $RELBIN/$f $f; done
    ln -sfn $RELBIN/python$MAJOR_MINOR python3
    ln -sfn $RELBIN/python$MAJOR_MINOR python
    ln -sfn $RELBIN/pip$MAJOR_MINOR pip3
    ln -sfn $RELBIN/pip$MAJOR_MINOR pip

    # We should now have a fully relocatable Python.framework

    # Strip the pyc files (~80 MB)
    cd "$LINK"
    find . -name "__pycache__" | xargs rm -r

    # Strip the test directory (~30 MB)
    [ -d lib/$PYVER/test ] && rm -r lib/$PYVER/test
    [ -d lib/$PYVER/unittest/test ] && rm -r lib/$PYVER/unittest/test

    # Bundle should now be ~40 MB uncompressed.
    # Could perhaps squeeze another 10 MB out if we cared to, but then it
    # would no longer be the "batteries included" python.

    # The process_python_build.py script strips the following:
    #     __pycache__, idlelib, ensurepip, test
    # Much easier to do this in bash if we want it.

    # TODO: putting the libraries into zip files full of pyc will make
    # startup much faster, but will destroy flexibility.
fi

# Build the upload zip file
cd "$CURRENT_DIR"
[ ! -d upload ] && mkdir upload
UPLOAD_FILE=python-$PYTHON_VERSION-osx-$MACOSX_DEPLOYMENT_TARGET.zip
UPLOAD_PATH=upload/$UPLOAD_FILE
zip --symlinks -r $UPLOAD_PATH python-portable 1> /dev/null
# curl --upload-file $UPLOAD_PATH https://transfer.sh/$UPLOAD_FILE | tee -a output_urls.txt && echo "" >> output_urls.txt

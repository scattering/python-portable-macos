#!/bin/bash

# Get the directory where this file is located and App Bundle Resources
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
CONTENTS="$(dirname "$DIR")"
echo $CONTENTS

# Add to the top of Path the Python bin
PATH="$CONTENTS/Frameworks/Python.framework/Versions/3.7/bin/:$PATH"
export PATH
echo $PATH
echo `which python3.7`
python3.7 -m mu

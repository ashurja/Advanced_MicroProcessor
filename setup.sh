#!/bin/sh

if [ $1 == "0" ]; then
    export export CSE148_TOOLS='/software/CSE/cs148sp22/tools'
    env | grep '^CSE148_TOOLS='
else 
    source /Users/jamshedashurov/Desktop/CSE148/CSE148/tools/oss-cad-suite/environment
    export CSE148_TOOLS="/Users/jamshedashurov/Desktop/CSE148/CSE148/tools"
fi

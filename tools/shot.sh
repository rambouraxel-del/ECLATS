#!/usr/bin/env bash
# Capture d'écran sous Xvfb (rendu logiciel). Usage : GODOT=... tools/shot.sh <scène.tscn> <sortie.png> [arguments de capture.gd]
scene=$1; out=$2; shift 2
timeout 600 xvfb-run -a -s "-screen 0 1600x900x24" "${GODOT:-godot}" --rendering-driver opengl3 -s tools/capture.gd -- "$scene" "$out" "$@" 2>&1 | grep -E "SCRIPT|saved|rendu|ERROR: [^C]" 

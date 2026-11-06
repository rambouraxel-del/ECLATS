#!/usr/bin/env bash
# Compile Godot 4.3-stable AVEC le module Voxel Tools 1.3.0 (prototype C du comparatif de terrain).
#   tools/build_godot_voxel.sh [DOSSIER_DE_TRAVAIL]      → DOSSIER/godot/bin/godot.linuxbsd.editor.x86_64
# Pré-requis (Ubuntu 24.04) : gcc/g++, python3, scons (pip install scons), libx11-dev libxcursor-dev libxi-dev libxrandr-dev
#   libxinerama-dev libgl-dev libxkbcommon-dev libegl-dev. Durée : ≈ 40 min sur 4 cœurs.
# Le moteur obtenu est un Godot 4.3 ordinaire (même GDScript, même rendu) + les classes Voxel*, ZN_FastNoiseLite… Le projet ÉCLATS
# reste exécutable avec le Godot 4.3 officiel : seules les scènes/outils qui instancient la méthode C exigent ce moteur.
set -euo pipefail
W="${1:-$HOME/gd}"
mkdir -p "$W" && cd "$W"
[ -d godot ] || git clone --depth 1 --branch 4.3-stable https://github.com/godotengine/godot godot
[ -d voxel ] || { git clone https://github.com/Zylann/godot_voxel voxel && git -C voxel checkout v1.3.0; }
rm -rf godot/modules/voxel && mkdir godot/modules/voxel && cp -r voxel/. godot/modules/voxel/ && rm -rf godot/modules/voxel/.git
cd godot
scons platform=linuxbsd target=editor -j"$(nproc)" tests=no debug_symbols=no vulkan=no wayland=no speechd=no fontconfig=no \
  alsa=no pulseaudio=no dbus=no udev=no module_openxr_enabled=no module_mono_enabled=no module_webxr_enabled=no \
  module_camera_enabled=no module_multiplayer_enabled=no module_enet_enabled=no module_websocket_enabled=no \
  module_webrtc_enabled=no module_upnp_enabled=no module_mobile_vr_enabled=no module_theora_enabled=no \
  module_vorbis_enabled=no module_ogg_enabled=no module_minimp3_enabled=no
ls -la bin/

#!/bin/bash
# Axiom OS Identity System - "The Silent Feather"
# Version: 1.0.0 (Production Build)

ROOT="/etc/axiom/ui"
LOGO_DIR="$ROOT/branding"
mkdir -p "$LOGO_DIR"

echo "Deploying Axiom OS Identity: The Silent Feather..."

# 1. Generate the Primary Identity SVG
# This uses a mask to define the feather shape as negative space
cat <<'SVG_EOT' > "$LOGO_DIR/axiom_feather_core.svg"
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <mask id="AxiomFeatherMask">
      <circle cx="50" cy="50" r="48" fill="white"/>
      <path d="M52 82 C 55 70 52 58 48 48 C 45 40 46 30 50 20 
               L 48 18 C 42 28 41 40 44 50 C 47 60 48 72 45 84 Z" fill="black"/>
      <path d="M48 18 C 30 25 32 45 35 60 C 37 75 32 82 45 84 Z" fill="black"/>
    </mask>
  </defs>
  
  <circle cx="50" cy="50" r="48" fill="white" mask="url(#AxiomFeatherMask)"/>
</svg>
SVG_EOT

# 2. Deploy to System Locations
# Deploying to launcher, icons, and plymouth (boot screen)
cp "$LOGO_DIR/axiom_feather_core.svg" "/usr/share/icons/hicolor/scalable/apps/axiom-launcher.svg"
cp "$LOGO_DIR/axiom_feather_core.svg" "/usr/share/plymouth/themes/axiom/logo.svg"

# 3. Apply System-wide CSS for UI Transparency
# Ensures the background texture is visible through the logo negative space
cat <<'CSS_EOT' > "$ROOT/identity.css"
.axiom-start-button {
    background: transparent;
    border: none;
    mask-image: url('file:///usr/share/icons/hicolor/scalable/apps/axiom-launcher.svg');
    -webkit-mask-image: url('file:///usr/share/icons/hicolor/scalable/apps/axiom-launcher.svg');
}

.axiom-start-button:hover {
    filter: drop-shadow(0 0 8px rgba(255, 255, 255, 0.4));
    cursor: pointer;
}
CSS_EOT

echo "Identity Build Complete. Axiom OS is now defined by the Silent Feather."

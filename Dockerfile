# =============================================================================
# Antigravity Tools Docker Container (Optimized)
# Provides Web VNC access to the Tauri desktop application
# Automatically fetches latest version from GitHub
# =============================================================================

FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# Display configuration
ENV DISPLAY=:99
ENV RESOLUTION=1280x720x24

# Target architecture: amd64 or aarch64
ARG TARGETARCH=amd64

# =============================================================================
# Install dependencies in single layer with aggressive cleanup
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # X11 and display (minimal)
    xvfb \
    x11vnc \
    # Lightweight window manager
    openbox \
    # noVNC for web access
    novnc \
    websockify \
    # GTK and WebKit dependencies (required by Tauri) - minimal set
    libgtk-3-0t64 \
    libwebkit2gtk-4.1-0 \
    # Additional Tauri dependencies
    libayatana-appindicator3-1 \
    librsvg2-common \
    # Utilities (minimal)
    wget \
    curl \
    ca-certificates \
    dbus-x11 \
    libfuse2 \
    jq \
    # squashfs-tools for extracting AppImage (needed for QEMU cross-arch builds)
    squashfs-tools \
    # Python for reliable offset detection
    python3 \
    # Process management
    supervisor \
    # Fonts - use lighter alternative (only ~5MB vs 100MB+ for noto-cjk)
    fonts-wqy-microhei \
    # Clean up aggressively
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc/* \
    && rm -rf /usr/share/man/* \
    && rm -rf /usr/share/locale/* \
    && rm -rf /var/cache/apt/*

# =============================================================================
# Download latest Antigravity Tools AppImage from GitHub
# =============================================================================
RUN mkdir -p /opt/antigravity && \
    # Map Docker TARGETARCH to AppImage arch naming
    APPIMAGE_ARCH=$(case "${TARGETARCH}" in \
        "arm64") echo "aarch64" ;; \
        "amd64"|*) echo "amd64" ;; \
    esac) && \
    echo "Target architecture: ${APPIMAGE_ARCH}" && \
    # Fetch latest release info from GitHub API
    echo "Fetching latest release from GitHub..." && \
    RELEASE_INFO=$(curl -sS --retry 3 --retry-delay 5 "https://api.github.com/repos/lbjlaq/Antigravity-Manager/releases/latest") && \
    # Extract version using grep (more portable than jq)
    VERSION=$(echo "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"v\?\([^"]*\)".*/\1/') && \
    # Validate VERSION is not empty
    if [ -z "$VERSION" ]; then \
        echo "ERROR: Failed to fetch version from GitHub API" && \
        echo "API Response (first 500 chars): $(echo "$RELEASE_INFO" | head -c 500)" && \
        exit 1; \
    fi && \
    echo "Latest version: ${VERSION}" && \
    # Save version for labels
    echo "${VERSION}" > /opt/antigravity/VERSION && \
    # Construct download URL
    DOWNLOAD_URL="https://github.com/lbjlaq/Antigravity-Manager/releases/download/v${VERSION}/Antigravity.Tools_${VERSION}_${APPIMAGE_ARCH}.AppImage" && \
    echo "Downloading: ${DOWNLOAD_URL}" && \
    # Download AppImage with retry and fail on error
    wget --retry-connrefused --waitretry=5 --tries=3 -q "${DOWNLOAD_URL}" -O /opt/antigravity/antigravity.AppImage && \
    # Verify download succeeded
    if [ ! -f /opt/antigravity/antigravity.AppImage ] || [ ! -s /opt/antigravity/antigravity.AppImage ]; then \
        echo "ERROR: Download failed or file is empty" && exit 1; \
    fi && \
    chmod +x /opt/antigravity/antigravity.AppImage && \
    echo "Download successful: $(ls -lh /opt/antigravity/antigravity.AppImage)" && \
    cd /opt/antigravity && \
    # Try AppImage self-extraction first (works on native arch)
    # If it fails (e.g., QEMU cross-arch build), fallback to unsquashfs with precise offset detection
    (APPIMAGE_EXTRACT_AND_RUN=1 ./antigravity.AppImage --appimage-extract 2>/dev/null && \
     mv squashfs-root app && echo "AppImage self-extraction successful!") || \
    (echo "AppImage self-extraction failed, using unsquashfs fallback..." && \
     # Use Python for reliable SquashFS magic number detection
     OFFSET=$(python3 -c "import sys; f=open('antigravity.AppImage','rb'); d=f.read(); o=d.find(b'hsqs'); print(o) if o!=-1 else sys.exit(1)") && \
     echo "Found SquashFS at offset: ${OFFSET}" && \
     unsquashfs -offset ${OFFSET} -d app antigravity.AppImage && \
     echo "unsquashfs extraction successful!") && \
    rm -f antigravity.AppImage && \
    # Verify extraction succeeded
    if [ ! -f app/AppRun ]; then \
        echo "ERROR: Extraction failed - app/AppRun not found" && \
        ls -la app/ 2>/dev/null || echo "app/ directory does not exist" && \
        exit 1; \
    fi && \
    echo "AppImage extraction verified successfully!" && \
    # Remove unnecessary files from extracted app
    rm -rf app/usr/share/doc app/usr/share/man 2>/dev/null || true

WORKDIR /opt/antigravity

# =============================================================================
# Configuration files
# =============================================================================
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh && mkdir -p /root/.antigravity_tools

# Labels
LABEL org.opencontainers.image.source="https://github.com/lbjlaq/Antigravity-Manager"

# =============================================================================
# Expose ports
# =============================================================================
EXPOSE 6080 8045

# =============================================================================
# Volume for persistent data
# =============================================================================
VOLUME ["/root/.antigravity_tools"]

# =============================================================================
# Health check
# =============================================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -sf http://localhost:6080/ || exit 1

# =============================================================================
# Start
# =============================================================================
CMD ["/start.sh"]

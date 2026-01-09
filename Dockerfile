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
    # squashfs-tools for extracting AppImage (works in QEMU emulation)
    squashfs-tools \
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
    # Fetch latest release info from GitHub API
    echo "Fetching latest release from GitHub..." && \
    RELEASE_INFO=$(curl -s "https://api.github.com/repos/lbjlaq/Antigravity-Manager/releases/latest") && \
    VERSION=$(echo "$RELEASE_INFO" | jq -r '.tag_name' | sed 's/^v//') && \
    echo "Latest version: ${VERSION}" && \
    # Save version for labels
    echo "${VERSION}" > /opt/antigravity/VERSION && \
    # Construct download URL
    DOWNLOAD_URL="https://github.com/lbjlaq/Antigravity-Manager/releases/download/v${VERSION}/Antigravity.Tools_${VERSION}_${APPIMAGE_ARCH}.AppImage" && \
    echo "Downloading: ${DOWNLOAD_URL}" && \
    # Download AppImage
    wget -q "${DOWNLOAD_URL}" -O /opt/antigravity/antigravity.AppImage && \
    chmod +x /opt/antigravity/antigravity.AppImage && \
    # Extract using unsquashfs (works in QEMU emulation, doesn't need FUSE)
    cd /opt/antigravity && \
    OFFSET=$(grep -aobm1 'hsqs' antigravity.AppImage | cut -d: -f1) && \
    unsquashfs -offset $OFFSET -d app antigravity.AppImage && \
    rm antigravity.AppImage && \
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

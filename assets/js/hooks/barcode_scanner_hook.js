/**
 * Barcode Scanner Hook
 *
 * Uses the device camera to scan barcodes.
 * Falls back to manual entry on unsupported devices.
 */

const BarcodeScannerHook = {
  mounted() {
    this.stream = null;
    this.scanning = false;
    this.barcodeDetector = null;

    // Check for BarcodeDetector API support
    if ("BarcodeDetector" in window) {
      this.barcodeDetector = new BarcodeDetector({
        formats: [
          "ean_13",
          "ean_8",
          "upc_a",
          "upc_e",
          "code_128",
          "code_39",
          "qr_code",
        ],
      });
    }

    this.setupEventListeners();
  },

  setupEventListeners() {
    this.handleEvent("start_scan", () => this.startScanning());
    this.handleEvent("stop_scan", () => this.stopScanning());
  },

  async startScanning() {
    const video = this.el.querySelector("video");
    if (!video) {
      this.pushEvent("scan_error", { error: "Video element not found" });
      return;
    }

    try {
      // Request camera access with back camera preference
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: "environment",
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
      });

      video.srcObject = this.stream;
      await video.play();

      this.scanning = true;
      this.pushEvent("scan_started", {});

      // Start detection loop
      this.detectBarcode(video);
    } catch (error) {
      console.error("Camera error:", error);
      this.pushEvent("scan_error", {
        error: error.message || "Failed to access camera",
      });
    }
  },

  async detectBarcode(video) {
    if (!this.scanning || !this.barcodeDetector) {
      // Fall back to manual detection using canvas analysis
      this.detectBarcodeManual(video);
      return;
    }

    try {
      const barcodes = await this.barcodeDetector.detect(video);

      if (barcodes.length > 0) {
        const barcode = barcodes[0];
        this.pushEvent("barcode_detected", {
          code: barcode.rawValue,
          format: barcode.format,
        });
        this.stopScanning();
        return;
      }
    } catch (error) {
      console.error("Detection error:", error);
    }

    // Continue scanning
    if (this.scanning) {
      requestAnimationFrame(() => this.detectBarcode(video));
    }
  },

  detectBarcodeManual(video) {
    // Simple manual detection fallback
    // In production, you'd use a library like zxing-js/library

    if (!this.scanning) return;

    // For browsers without BarcodeDetector, inform user
    this.pushEvent("scan_fallback", {
      message: "Automatic detection not supported. Please enter barcode manually.",
    });
  },

  stopScanning() {
    this.scanning = false;

    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop());
      this.stream = null;
    }

    const video = this.el.querySelector("video");
    if (video) {
      video.srcObject = null;
    }

    this.pushEvent("scan_stopped", {});
  },

  destroyed() {
    this.stopScanning();
  },
};

export default BarcodeScannerHook;

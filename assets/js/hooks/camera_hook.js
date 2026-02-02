/**
 * Camera Hook
 *
 * Provides camera capture and image upload functionality.
 */

const CameraHook = {
  mounted() {
    this.stream = null;
    this.setupEventListeners();
  },

  setupEventListeners() {
    // Handle capture button click
    this.handleEvent("start_camera", () => {
      this.startCamera();
    });

    this.handleEvent("stop_camera", () => {
      this.stopCamera();
    });

    // File input for image upload
    const fileInput = this.el.querySelector('input[type="file"]');
    if (fileInput) {
      fileInput.addEventListener("change", (e) => this.handleFileSelect(e));
    }

    // Capture button
    const captureBtn = this.el.querySelector("[data-capture]");
    if (captureBtn) {
      captureBtn.addEventListener("click", () => this.captureImage());
    }
  },

  async startCamera() {
    try {
      const video = this.el.querySelector("video");
      if (!video) return;

      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: "environment", // Prefer back camera for food photos
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
      });

      video.srcObject = this.stream;
      video.play();

      this.pushEvent("camera_started", {});
    } catch (error) {
      console.error("Error accessing camera:", error);
      this.pushEvent("camera_error", { error: "Camera access denied" });
    }
  },

  stopCamera() {
    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop());
      this.stream = null;
    }

    const video = this.el.querySelector("video");
    if (video) {
      video.srcObject = null;
    }

    this.pushEvent("camera_stopped", {});
  },

  captureImage() {
    const video = this.el.querySelector("video");
    const canvas = this.el.querySelector("canvas") || document.createElement("canvas");

    if (!video || !video.videoWidth) {
      this.pushEvent("camera_error", { error: "Camera not ready" });
      return;
    }

    // Set canvas size to video dimensions
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;

    // Draw video frame to canvas
    const ctx = canvas.getContext("2d");
    ctx.drawImage(video, 0, 0);

    // Convert to base64
    const imageData = canvas.toDataURL("image/jpeg", 0.8);

    this.pushEvent("image_captured", { image: imageData });

    // Stop camera after capture
    this.stopCamera();
  },

  handleFileSelect(event) {
    const file = event.target.files[0];
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith("image/")) {
      this.pushEvent("camera_error", { error: "Please select an image file" });
      return;
    }

    // Validate file size (max 10MB)
    if (file.size > 10 * 1024 * 1024) {
      this.pushEvent("camera_error", { error: "Image too large. Max 10MB." });
      return;
    }

    const reader = new FileReader();
    reader.onload = (e) => {
      // Optionally resize if too large
      this.resizeImage(e.target.result, 1920, (resizedData) => {
        this.pushEvent("image_uploaded", { image: resizedData });
      });
    };
    reader.onerror = () => {
      this.pushEvent("camera_error", { error: "Failed to read file" });
    };
    reader.readAsDataURL(file);
  },

  resizeImage(dataUrl, maxDimension, callback) {
    const img = new Image();
    img.onload = () => {
      let { width, height } = img;

      // Only resize if larger than max
      if (width > maxDimension || height > maxDimension) {
        if (width > height) {
          height = (height * maxDimension) / width;
          width = maxDimension;
        } else {
          width = (width * maxDimension) / height;
          height = maxDimension;
        }
      }

      const canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;

      const ctx = canvas.getContext("2d");
      ctx.drawImage(img, 0, 0, width, height);

      callback(canvas.toDataURL("image/jpeg", 0.85));
    };
    img.src = dataUrl;
  },

  destroyed() {
    this.stopCamera();
  },
};

export default CameraHook;

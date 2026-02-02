/**
 * Voice Input Hook
 *
 * Provides tap-to-talk functionality using the Web Speech API.
 * Falls back to Whisper WASM for browsers without native speech recognition.
 */

const VoiceInputHook = {
  mounted() {
    this.isRecording = false;
    this.mediaRecorder = null;
    this.audioChunks = [];
    this.silenceTimer = null;
    this.audioContext = null;
    this.analyser = null;
    this.silenceThreshold = 0.01;
    this.silenceDuration = 3000; // 3 seconds of silence to auto-stop

    // Check for browser support
    this.hasNativeSpeechRecognition =
      "webkitSpeechRecognition" in window || "SpeechRecognition" in window;

    this.setupEventListeners();
  },

  setupEventListeners() {
    const button = this.el;

    // Handle tap-to-talk
    button.addEventListener("click", () => {
      if (this.isRecording) {
        this.stopRecording();
      } else {
        this.startRecording();
      }
    });

    // Handle push events from server
    this.handleEvent("voice_recording_stopped", () => {
      this.stopRecording();
    });
  },

  async startRecording() {
    try {
      // Request microphone permission
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });

      this.isRecording = true;
      this.updateUI("recording");
      this.pushEvent("voice_recording_started", {});

      // Use native Speech Recognition if available
      if (this.hasNativeSpeechRecognition) {
        this.startNativeSpeechRecognition();
      } else {
        // Fall back to recording audio for Whisper processing
        this.startAudioRecording(stream);
      }

      // Start silence detection
      this.startSilenceDetection(stream);
    } catch (error) {
      console.error("Error accessing microphone:", error);
      this.pushEvent("voice_error", { error: "Microphone access denied" });
    }
  },

  startNativeSpeechRecognition() {
    const SpeechRecognition =
      window.SpeechRecognition || window.webkitSpeechRecognition;
    this.recognition = new SpeechRecognition();

    this.recognition.continuous = false;
    this.recognition.interimResults = true;
    this.recognition.lang = "en-US";

    let finalTranscript = "";

    this.recognition.onresult = (event) => {
      let interimTranscript = "";

      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i];
        if (result.isFinal) {
          finalTranscript += result[0].transcript;
        } else {
          interimTranscript += result[0].transcript;
        }
      }

      // Send interim results for live feedback
      if (interimTranscript) {
        this.pushEvent("voice_interim", { text: interimTranscript });
      }
    };

    this.recognition.onend = () => {
      if (finalTranscript) {
        this.pushEvent("voice_transcribed", { text: finalTranscript.trim() });
      }
      this.cleanup();
    };

    this.recognition.onerror = (event) => {
      console.error("Speech recognition error:", event.error);
      this.pushEvent("voice_error", { error: event.error });
      this.cleanup();
    };

    this.recognition.start();
  },

  startAudioRecording(stream) {
    // Record audio for Whisper processing
    this.mediaRecorder = new MediaRecorder(stream);
    this.audioChunks = [];

    this.mediaRecorder.ondataavailable = (event) => {
      if (event.data.size > 0) {
        this.audioChunks.push(event.data);
      }
    };

    this.mediaRecorder.onstop = async () => {
      const audioBlob = new Blob(this.audioChunks, { type: "audio/webm" });
      await this.processWithWhisper(audioBlob);
      this.cleanup();
    };

    this.mediaRecorder.start();
  },

  startSilenceDetection(stream) {
    this.audioContext = new AudioContext();
    const source = this.audioContext.createMediaStreamSource(stream);
    this.analyser = this.audioContext.createAnalyser();
    this.analyser.fftSize = 512;

    source.connect(this.analyser);

    const dataArray = new Uint8Array(this.analyser.frequencyBinCount);
    let silenceStart = null;

    const checkSilence = () => {
      if (!this.isRecording) return;

      this.analyser.getByteFrequencyData(dataArray);

      // Calculate average volume
      const average = dataArray.reduce((a, b) => a + b, 0) / dataArray.length;
      const normalizedVolume = average / 255;

      if (normalizedVolume < this.silenceThreshold) {
        if (!silenceStart) {
          silenceStart = Date.now();
        } else if (Date.now() - silenceStart > this.silenceDuration) {
          // 3 seconds of silence detected
          this.stopRecording();
          return;
        }
      } else {
        silenceStart = null;
      }

      requestAnimationFrame(checkSilence);
    };

    checkSilence();
  },

  async processWithWhisper(audioBlob) {
    // Convert audio to base64 and send to server for Whisper processing
    const reader = new FileReader();
    reader.onloadend = () => {
      const base64Audio = reader.result.split(",")[1];
      this.pushEvent("voice_audio_data", { audio: base64Audio });
    };
    reader.readAsDataURL(audioBlob);
  },

  stopRecording() {
    if (!this.isRecording) return;

    this.isRecording = false;
    this.updateUI("idle");

    if (this.recognition) {
      this.recognition.stop();
    }

    if (this.mediaRecorder && this.mediaRecorder.state !== "inactive") {
      this.mediaRecorder.stop();
    }

    this.pushEvent("voice_recording_stopped", {});
  },

  cleanup() {
    this.isRecording = false;
    this.updateUI("idle");

    if (this.silenceTimer) {
      clearTimeout(this.silenceTimer);
      this.silenceTimer = null;
    }

    if (this.audioContext) {
      this.audioContext.close();
      this.audioContext = null;
    }

    if (
      this.mediaRecorder &&
      this.mediaRecorder.stream &&
      this.mediaRecorder.stream.getTracks
    ) {
      this.mediaRecorder.stream.getTracks().forEach((track) => track.stop());
    }

    this.recognition = null;
    this.mediaRecorder = null;
  },

  updateUI(state) {
    const button = this.el;

    if (state === "recording") {
      button.classList.add("recording", "btn-error");
      button.classList.remove("btn-ghost");
      button.setAttribute("aria-label", "Stop recording");
    } else {
      button.classList.remove("recording", "btn-error");
      button.classList.add("btn-ghost");
      button.setAttribute("aria-label", "Start voice input");
    }
  },

  destroyed() {
    this.cleanup();
  },
};

export default VoiceInputHook;

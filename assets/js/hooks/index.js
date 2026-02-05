import VoiceInputHook from "./voice_input_hook";
import CameraHook from "./camera_hook";
import BarcodeScannerHook from "./barcode_scanner_hook";
import ChatDrawerHook from "./chat_drawer_hook";

const Hooks = {
  VoiceInput: VoiceInputHook,
  Camera: CameraHook,
  BarcodeScanner: BarcodeScannerHook,
  ChatDrawer: ChatDrawerHook,
};

export default Hooks;

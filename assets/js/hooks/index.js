import VoiceInputHook from "./voice_input_hook";
import CameraHook from "./camera_hook";
import BarcodeScannerHook from "./barcode_scanner_hook";
import ChatDrawerHook from "./chat_drawer_hook";
import RestockToastHook from "./restock_toast_hook";

const Hooks = {
  VoiceInput: VoiceInputHook,
  Camera: CameraHook,
  BarcodeScanner: BarcodeScannerHook,
  ChatDrawer: ChatDrawerHook,
  RestockToast: RestockToastHook,
};

export default Hooks;

const ChatDrawerHook = {
  mounted() {
    this.scrollToBottom();

    // Close drawer on Escape key
    this.handleKeydown = (e) => {
      if (e.key === "Escape") {
        this.pushEvent("drawer_toggle", {});
      }
    };
    document.addEventListener("keydown", this.handleKeydown);
  },

  updated() {
    this.scrollToBottom();
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeydown);
  },

  scrollToBottom() {
    const messagesEl = document.getElementById("drawer-messages");
    if (messagesEl) {
      requestAnimationFrame(() => {
        messagesEl.scrollTop = messagesEl.scrollHeight;
      });
    }
  },
};

export default ChatDrawerHook;

const RestockToast = {
  mounted() {
    this.timer = setTimeout(() => {
      this.el.classList.add("opacity-0", "transition-opacity", "duration-500");
      setTimeout(() => {
        this.pushEvent("dismiss_restock", {
          "item-id": this.el.id.replace("restock-toast-", ""),
        });
      }, 500);
    }, 30000);
  },

  destroyed() {
    if (this.timer) clearTimeout(this.timer);
  },
};

export default RestockToast;
